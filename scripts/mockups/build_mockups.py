"""Builds Glide's device mockups in Blender, from each device's published dimensions and reference photographs.

    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
        --python scripts/mockups/build_mockups.py -- Mockups [device ids...]

For every device this writes <out>/<id>/model.blend (the editable source: named parts, each motion kept as an action,
a studio and a camera, so it renders in Cycles as it stands), <out>/<id>/model.usdz (what Glide draws) and
<out>/<id>/device.json (where the screen is, and every motion baked at 60 frames a second). <out>/index.json lists the
devices and <out>/studio.hdr is the lighting they are all shown in.

Surfaces are modelled as lofts: an outline swept along a profile of insets and heights. Every vertex's normal comes from
the shape itself, not from averaging faces, so flat faces stay flat and a bevel catches light the way a machined edge
does. Corners are continuous-curvature curves, not circular arcs.

Blender's axes are kept throughout: +X is right, +Z is up, and the viewer stands at -Y looking toward +Y.
Lengths are metres. The models carry no logos.
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector, geometry

FPS = 60
MM = 0.001
TEXT_FONT = "/System/Library/Fonts/Helvetica.ttc"
SYMBOL_FONT = "/System/Library/Fonts/Apple Symbols.ttf"


def srgb(hex_value):
    """Blender's colours are linear; these are written the way they look."""
    def channel(value):
        value /= 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    return (channel((hex_value >> 16) & 255), channel((hex_value >> 8) & 255), channel(hex_value & 255), 1)


def material(name, color, metallic=0.0, roughness=0.5, coat=0.0, coat_roughness=0.05, image=None):
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    made = bpy.data.materials.new(name)
    made.use_nodes = True
    node = made.node_tree.nodes["Principled BSDF"]
    node.inputs["Base Color"].default_value = srgb(color)
    node.inputs["Metallic"].default_value = metallic
    node.inputs["Roughness"].default_value = roughness
    node.inputs["Coat Weight"].default_value = coat
    node.inputs["Coat Roughness"].default_value = coat_roughness
    if image:
        texture = made.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = bpy.data.images.load(image, check_existing=True)
        made.node_tree.links.new(texture.outputs["Color"], node.inputs["Base Color"])
    return made


# MARK: Shapes

def rounded(width, height, radii, center=(0, 0), continuous=True, segments=20):
    """A closed outline as (x, y, normal x, normal y), counter-clockwise from the right edge. `radii` is one radius, or
    four for the top right, top left, bottom left and bottom right. A continuous corner eases into its straight edges
    (Lame curve, exponent 3.26, over 1.53 radii), which is what separates an Apple corner from a circular arc."""
    x0, y0 = center
    radii = radii if isinstance(radii, (tuple, list)) else (radii,) * 4
    half_w, half_h = width / 2, height / 2
    points = []
    spots = [(half_w, half_h), (-half_w, half_h), (-half_w, -half_h), (half_w, -half_h)]
    for quadrant, ((cx, cy), radius) in enumerate(zip(spots, radii)):
        if radius <= 0:
            length = math.hypot(cx, cy)
            points.append((x0 + cx, y0 + cy, cx / length, cy / length))
            continue
        reach = radius * 1.5287 if continuous else radius
        limit = min(half_w, half_h)
        if reach > limit:
            reach = limit
        exponent = 3.26 if continuous and reach > radius else 2.0
        ox = cx - math.copysign(reach, cx)
        oy = cy - math.copysign(reach, cy)
        for step in range(segments + 1):
            angle = (math.pi / 2) * step / segments
            c, s = max(math.cos(angle), 0.0), max(math.sin(angle), 0.0)
            ex, ey = c ** (2 / exponent), s ** (2 / exponent)
            nx, ny = ex ** (exponent - 1), ey ** (exponent - 1)
            length = math.hypot(nx, ny) or 1
            nx, ny = nx / length, ny / length
            # Turned to this corner's quadrant.
            lx, ly = reach * ex, reach * ey
            for _ in range(quadrant):
                lx, ly, nx, ny = -ly, lx, -ny, nx
            points.append((x0 + ox + lx, y0 + oy + ly, nx, ny))
    return points


def circle(radius, center=(0, 0), segments=48):
    x0, y0 = center
    return [(x0 + radius * math.cos(2 * math.pi * i / segments), y0 + radius * math.sin(2 * math.pi * i / segments),
             math.cos(2 * math.pi * i / segments), math.sin(2 * math.pi * i / segments)) for i in range(segments)]


def inset(outline, distance):
    return [(x - nx * distance, y - ny * distance, nx, ny) for x, y, nx, ny in outline]


def arc(center_inset, center_z, radius, start, end, steps=4):
    """Profile points around a centre: 0 degrees faces outward, 90 faces up, -90 faces down, 180 faces inward."""
    points = []
    for step in range(steps + 1):
        angle = math.radians(start + (end - start) * step / steps)
        points.append((center_inset - radius * math.cos(angle), center_z + radius * math.sin(angle), math.cos(angle), math.sin(angle)))
    return points


def slab_profile(bottom, top, bottom_radius, top_radius, steps=4):
    """A solid plate's edge from its underside to its top: rounded at both ends, upright in between."""
    points = []
    if bottom_radius > 0:
        points += arc(bottom_radius, bottom + bottom_radius, bottom_radius, -90, 0, steps)
    else:
        points += [(0, bottom, 1, 0)]
    if top_radius > 0:
        points += arc(top_radius, top - top_radius, top_radius, 0, 90, steps)
    else:
        points += [(0, top, 1, 0)]
    return points


def point_in_loop(x, y, loop):
    inside = False
    for a, b in zip(loop, loop[1:] + loop[:1]):
        if (a[1] > y) != (b[1] > y) and x < a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1]):
            inside = not inside
    return inside


class Builder:
    """Collects shapes into one mesh, each vertex with its own normal."""

    def __init__(self, name):
        self.name = name
        self.verts, self.normals, self.faces, self.face_mats, self.loop_uvs = [], [], [], [], []
        self.materials = []
        self.matrix = Matrix.Identity(4)
        self.uv = lambda x, y, z: (x * 10, y * 10)
        # A very slight "bow" in the normals of big flat faces, which no outline shows. It sweeps their reflection across
        # the studio's graded lights, the way real light falls off across a panel.
        self.bow = None

    def _material_index(self, mat):
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def _bowed(self, x, y, z):
        if not self.bow:
            return 0, 0, 1
        (cx, cy, half_x, half_y, bend_x, bend_y) = self.bow
        return bend_x * (x - cx) / half_x, bend_y * (y - cy) / half_y, 1

    def _vertex(self, x, y, z, nx, ny, nz):
        at = self.matrix @ Vector((x, y, z))
        turned = self.matrix.to_3x3() @ Vector((nx, ny, nz))
        turned.normalize()
        self.verts.append((at.x, at.y, at.z))
        self.normals.append((turned.x, turned.y, turned.z))
        self._uv_source.append(self.uv(x, y, z))
        return len(self.verts) - 1

    _uv_source = None

    def _face(self, indices, mat_index):
        # Wind the face to agree with its vertices' normals, so that it is not culled.
        a, b, c = (Vector(self.verts[i]) for i in indices[:3])
        cross = (b - a).cross(c - a)
        if len(indices) > 3 and cross.length < 1e-14:
            a, b, c = (Vector(self.verts[i]) for i in (indices[0], indices[2], indices[3]))
            cross = (b - a).cross(c - a)
        if cross.length < 1e-16:
            return
        normal = Vector((0, 0, 0))
        for i in indices:
            normal += Vector(self.normals[i])
        if cross.dot(normal) < 0:
            indices = list(reversed(indices))
        self.faces.append(tuple(indices))
        self.face_mats.append(mat_index)
        self.loop_uvs.extend(self._uv_source[i] for i in indices)

    def loft(self, outline, profile, mat, cap_start=False, cap_end=False):
        """Sweeps an outline along a profile of (inset, z, outward normal, upward normal)."""
        if self._uv_source is None:
            self._uv_source = []
        index = self._material_index(mat)
        count = len(outline)
        rings = []
        for depth, z, nr, nz in profile:
            ring = [self._vertex(x - nx * depth, y - ny * depth, z, nx * nr, ny * nr, nz) for x, y, nx, ny in outline]
            rings.append(ring)
        for low, high in zip(rings, rings[1:]):
            for i in range(count):
                j = (i + 1) % count
                self._face([low[i], low[j], high[j], high[i]], index)
        if cap_start:
            self._face(self._cap_ring(outline, profile[0], -1), index)
        if cap_end:
            self._face(self._cap_ring(outline, profile[-1], 1), index)

    def _cap_ring(self, outline, point, direction):
        depth, z, _, _ = point
        ring = []
        for x, y, nx, ny in outline:
            at_x, at_y = x - nx * depth, y - ny * depth
            bx, by, bz = self._bowed(at_x, at_y, z)
            ring.append(self._vertex(at_x, at_y, z, bx, by, bz * direction))
        return ring

    def plate(self, outline, z, mat, up=True):
        if self._uv_source is None:
            self._uv_source = []
        index = self._material_index(mat)
        direction = 1 if up else -1
        verts = []
        for p in outline:
            bx, by, bz = self._bowed(p[0], p[1], z)
            verts.append(self._vertex(p[0], p[1], z, bx, by, bz * direction))
        self._face(verts, index)

    def plate_with_holes(self, outer, holes, z, mat):
        """A flat face at height z with holes cut through it."""
        if self._uv_source is None:
            self._uv_source = []
        index = self._material_index(mat)
        coords, edges = [], []
        for loop in [outer] + holes:
            start = len(coords)
            coords += [Vector((p[0], p[1])) for p in loop]
            edges += [(start + i, start + (i + 1) % len(loop)) for i in range(len(loop))]
        result = geometry.delaunay_2d_cdt(coords, edges, [], 1, 1e-9)
        out_verts, out_faces = result[0], result[2]
        lookup = [self._vertex(v.x, v.y, z, *self._bowed(v.x, v.y, z)) for v in out_verts]
        for face in out_faces:
            cx = sum(out_verts[i].x for i in face) / len(face)
            cy = sum(out_verts[i].y for i in face) / len(face)
            if not any(point_in_loop(cx, cy, hole) for hole in holes):
                self._face([lookup[i] for i in face], index)

    def object(self, parent, origin=(0, 0, 0)):
        """The finished part, its vertices measured from `origin`, which is where its parent already stands."""
        mesh = bpy.data.meshes.new(self.name)
        offset = Vector(origin)
        verts = [tuple(Vector(v) - offset) for v in self.verts]
        mesh.from_pydata(verts, [], self.faces)
        mesh.update()
        for mat in self.materials:
            mesh.materials.append(mat)
        mesh.polygons.foreach_set("material_index", self.face_mats)
        mesh.polygons.foreach_set("use_smooth", [True] * len(self.faces))
        uv_layer = mesh.uv_layers.new(name="UVMap")
        uv_layer.data.foreach_set("uv", [component for uv in self.loop_uvs for component in uv])
        mesh.normals_split_custom_set_from_vertices(self.normals)
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = parent
        return obj


def screen_size(diagonal_inches, pixels):
    """Width and height in metres of a display from its diagonal and its pixels."""
    diagonal = diagonal_inches * 0.0254
    scale = diagonal / math.hypot(pixels[0], pixels[1])
    return pixels[0] * scale, pixels[1] * scale


def side_matrix(direction, y, z, surface):
    """Local x along Y, local y along Z, local z pointing out of the device's side at x = surface."""
    x_axis = Vector((0, direction, 0))
    y_axis = Vector((0, 0, 1))
    z_axis = Vector((direction, 0, 0))
    matrix = Matrix((x_axis, y_axis, z_axis)).transposed().to_4x4()
    matrix.translation = (surface, y, z)
    return matrix


# MARK: Keyboard
# An ANSI MacBook keyboard, measured from Apple's top-down photographs: six rows on an 18.8 mm pitch.

KEY_PITCH = 18.68 * MM
KEY_GAP = 2.8 * MM
WELL_WIDTH = 279.2 * MM
WELL_DEPTH = 114.0 * MM

FUNCTION_GLYPHS = ["☼", "☀", "▦", "⌕", "♩", "☾", "◀◀", "▶", "▶▶", "◁", "◁", "◁"]


def keyboard_layout():
    """Every key as (x, y, width, height, legends), centred on the well. A legend is (text, dx, dy, size, font)."""
    def pair(top, bottom):
        return [(top, 0, 2.5 * MM, 2.3 * MM, "text"), (bottom, 0, -2.3 * MM, 2.3 * MM, "text")]

    def letter(text):
        return [(text, 0, 0, 3.4 * MM, "text")]

    def word(text, align=-1, symbol=None):
        return [(text, align, -4.2 * MM, 1.9 * MM, "word")] + ([(symbol, align, 3.8 * MM, 2.5 * MM, "symbol-word")] if symbol else [])

    function = [("esc", 1.75, word("esc"))]
    for number in range(1, 13):
        function.append((f"F{number}", 1.0, [(f"F{number}", 0, -4.2 * MM, 1.6 * MM, "text"),
                                             (FUNCTION_GLYPHS[number - 1], 0, 1.5 * MM, 3.2 * MM, "symbol")]))
    function.append(("touch", 1.0, []))
    numbers = [(a + b, 1.0, pair(a, b)) for a, b in zip("~!@#$%^&*()_+", "`1234567890-=")] + [("delete", 1.75, word("delete", 1))]
    top = [("tab", 1.75, word("tab"))] + [(c, 1.0, letter(c)) for c in "QWERTYUIOP"] + [("[", 1.0, pair("{", "[")), ("]", 1.0, pair("}", "]")), ("\\", 1.0, pair("|", "\\"))]
    middle = [("caps", 2.1, word("caps lock"))] + [(c, 1.0, letter(c)) for c in "ASDFGHJKL"] + [(";", 1.0, pair(":", ";")), ("'", 1.0, pair('"', "'")), ("return", 1.65, word("return", 1))]
    lower = [("lshift", 2.6, word("shift"))] + [(c, 1.0, letter(c)) for c in "ZXCVBNM"] + [(",", 1.0, pair("<", ",")), (".", 1.0, pair(">", ".")), ("/", 1.0, pair("?", "/")), ("rshift", 2.15, word("shift", 1))]
    bottom = [("fn", 1.0, word("fn")), ("control", 1.0, word("control", 0, "⌃")), ("option", 1.0, word("option", 0, "⌥")),
              ("command", 1.25, word("command", 0, "⌘")), ("space", 5.25, []), ("rcommand", 1.25, word("command", 0, "⌘")),
              ("roption", 1.0, word("option", 0, "⌥"))]

    rows = [function, numbers, top, middle, lower, bottom]
    span = 14.75 * KEY_PITCH
    keys = []
    first_y = (len(rows) - 1) * KEY_PITCH / 2
    for row_index, row in enumerate(rows):
        x = -span / 2
        y = first_y - row_index * KEY_PITCH
        for label, width, legends in row:
            key_width = width * KEY_PITCH
            keys.append(dict(label=label, x=x + key_width / 2, y=y, w=key_width - KEY_GAP, h=KEY_PITCH - KEY_GAP, legends=legends))
            x += key_width
        if row is bottom:
            # The arrows: left and right at full height's lower half, up and down stacked between them.
            half = (KEY_PITCH - KEY_GAP * 0.75) / 2
            lower_y = y - KEY_PITCH / 2 + KEY_GAP / 2 + half / 2
            upper_y = lower_y + half + KEY_GAP * 0.25
            for offset, arrow_y, glyph in ((0, lower_y, "◀"), (1, lower_y, "▼"), (1, upper_y, "▲"), (2, lower_y, "▶")):
                keys.append(dict(label=f"arrow{offset}{glyph}", x=x + (offset + 0.5) * KEY_PITCH, y=arrow_y, w=KEY_PITCH - KEY_GAP, h=half - KEY_GAP * 0.25,
                                 legends=[(glyph, 0, 0, 2.0 * MM, "symbol")]))
    return keys


def render_keyboard_texture(path):
    """Draws the legends once as a picture, so that at any size they are smoothly filtered instead of shimmering."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 4096
    scene.render.resolution_y = round(4096 * WELL_DEPTH / WELL_WIDTH)
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    world = bpy.data.worlds.new("Key")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb(0x0C0C0E)
    scene.world = world

    ink = bpy.data.materials.new("Ink")
    ink.use_nodes = True
    tree = ink.node_tree
    tree.nodes.clear()
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = srgb(0xF0F0F2)
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])

    text_font = bpy.data.fonts.load(TEXT_FONT)
    symbol_font = bpy.data.fonts.load(SYMBOL_FONT)
    for key in keyboard_layout():
        for text, dx, dy, size, kind in key["legends"]:
            curve = bpy.data.curves.new("Legend", 'FONT')
            curve.body = text
            curve.size = size * 1.35
            curve.font = symbol_font if kind.startswith("symbol") else text_font
            curve.align_y = 'CENTER'
            x = key["x"] + (dx if kind in ("text", "symbol") else 0)
            if kind in ("word", "symbol-word"):
                # dx is which way a word sits: -1 at the left of the key, 1 at the right, 0 in the middle.
                margin = key["w"] / 2 - 1.3 * MM
                curve.align_x = {-1: 'LEFT', 0: 'CENTER', 1: 'RIGHT'}[dx]
                x = key["x"] + dx * margin
            else:
                curve.align_x = 'CENTER'
            obj = bpy.data.objects.new("Legend", curve)
            scene.collection.objects.link(obj)
            obj.location = (x, key["y"] + dy, 0)
            curve.materials.append(ink)

    camera = bpy.data.cameras.new("Top")
    camera.type = 'ORTHO'
    camera.ortho_scale = WELL_WIDTH
    camera.clip_start = 0.001
    holder = bpy.data.objects.new("Top", camera)
    scene.collection.objects.link(holder)
    holder.location = (0, 0, 0.1)
    scene.camera = holder
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def grille_texture(path, body_color):
    """The speaker grilles: rows of fine holes in the deck's own colour."""
    width, height = 256, 1792
    pitch = 16
    ys, xs = np.mgrid[0:height, 0:width]
    row = (ys // pitch).astype(int)
    cx = (xs + (row % 2) * pitch / 2) % pitch - pitch / 2
    cy = ys % pitch - pitch / 2
    distance = np.hypot(cx, cy)
    hole = np.clip((3.6 - distance) / 1.5, 0, 1)
    fade = np.clip(np.minimum(np.minimum(xs, width - 1 - xs), np.minimum(ys, height - 1 - ys)) / 2, 0, 1)
    hole *= fade
    pixels = np.ones((height, width, 4), dtype=np.float32)
    base = srgb(body_color)
    for channel in range(3):
        pixels[:, :, channel] = base[channel] * (1 - hole) + 0.002 * hole
    image = bpy.data.images.new(os.path.basename(path), width, height, alpha=True)
    image.pixels.foreach_set(pixels[::-1].ravel())
    image.filepath_raw = path
    image.file_format = 'PNG'
    image.save()
    return path


# MARK: MacBooks

def stadium(width, height, center=(0, 0), segments=10):
    return rounded(width, height, min(width, height) / 2, center, continuous=False, segments=segments)


def inlay(builder, direction, surface, y, z, width, height, rise, mat, inner=None):
    """A small part set into a device's side, such as a port: a rounded lip, and optionally a dark inside."""
    builder.matrix = side_matrix(direction, y, z, surface)
    outline = stadium(width, height)
    builder.loft(outline, slab_profile(-0.0002, rise, 0, min(rise, 0.00008), 2), mat, cap_end=inner is None)
    if inner:
        builder.plate(inset(outline, min(width, height) * 0.14), rise + 0.00001, inner)
    builder.matrix = Matrix.Identity(4)


def build_macbook(spec, rig, shared):
    width, depth, total = spec["w"], spec["d"], spec["h"]
    pro = spec["line"] == "pro"
    lid_t = (5.2 if pro else 4.1) * MM
    gap = 0.35 * MM
    base_h = total - lid_t - gap
    corner = spec["corner"] * MM

    body = material("Aluminium", spec["color"], 1.0, spec.get("roughness", 0.36))
    well_mat = material("KeyboardWell", 0x020203, 0.0, 0.95)
    dark = material("Shadow", 0x020203, 0.0, 0.7)
    pad_mat = material("TrackpadGlass", spec["trackpad"], 0.85, 0.27)
    rubber = material("Rubber", 0x101012, 0.0, 0.8)
    port_mat = material("PortMetal", 0x2A2A2C, 1.0, 0.4)
    hinge_mat = material("Hinge", 0x1B1B1D, 0.9, 0.42)
    bezel = material("BezelGlass", 0x020203, 0.0, 0.05)
    lens_glass = material("LensGlass", 0x05060C, 0.0, 0.04)

    # Base: rounded underneath, with a tight machined edge around the deck.
    base = Builder("Base")
    outline = rounded(width, depth, corner, segments=22)
    edge = 0.42 * MM
    under = (2.3 if pro else 1.5) * MM
    base.loft(outline, slab_profile(0, base_h, under, edge, 6), body, cap_start=True)

    well_y = depth / 2 - (17.0 if pro else 16.0) * MM - WELL_DEPTH / 2
    well = rounded(WELL_WIDTH, WELL_DEPTH, 3.0 * MM, (0, well_y), continuous=False, segments=6)
    pad_w, pad_h = spec["pad"][0] * MM, spec["pad"][1] * MM
    front_margin = 5.2 * MM
    pad_y = -depth / 2 + front_margin + pad_h / 2
    pad_gap = 0.36 * MM
    pad_hole = rounded(pad_w + 2 * pad_gap, pad_h + 2 * pad_gap, 4.6 * MM, (0, pad_y), continuous=False, segments=8)
    base.bow = (0, 0, width / 2, depth / 2, 0.018, -0.075)
    base.plate_with_holes(inset(outline, edge), [well, pad_hole], base_h, body)
    base.bow = None

    # The keyboard sits in a well, with a soft edge around it.
    well_floor = base_h - 0.55 * MM
    soften = 0.14 * MM
    base.loft(well, arc(0, base_h - soften, soften, 90, 180, 3) + [(soften, well_floor, -1, 0)], body)
    base.plate(inset(well, soften), well_floor, well_mat)

    # The trackpad floats in a hair-thin gap.
    pad_floor = base_h - 0.9 * MM
    base.loft(pad_hole, arc(0, base_h - 0.08 * MM, 0.08 * MM, 90, 180, 2) + [(0.08 * MM, pad_floor, -1, 0)], body)
    base.plate(inset(pad_hole, 0.08 * MM), pad_floor, dark)
    pad = rounded(pad_w, pad_h, 4.3 * MM, (0, pad_y), continuous=False, segments=8)
    base.bow = (0, 0, width / 2, depth / 2, 0.018, -0.075)
    base.loft(pad, slab_profile(pad_floor, base_h - 0.03 * MM, 0, 0.1 * MM, 3), pad_mat, cap_end=True)
    base.bow = None

    # Rubber feet and the thumb scoop at the front edge.
    for fx in (-1, 1):
        for fy in (-1, 1):
            foot = circle(5.2 * MM, (fx * (width / 2 - 23 * MM), fy * (depth / 2 - 20 * MM)), 24)
            base.loft(foot, slab_profile(-0.5 * MM, 0.02 * MM, 0.35 * MM, 0, 3), rubber, cap_start=True)
    scoop = stadium(27 * MM, 1.6 * MM, (0, -depth / 2 + edge + 0.55 * MM))
    base.plate(scoop, base_h + 0.008 * MM, material("Scoop", spec["scoop"], 1.0, 0.45))

    # Ports along the sides.
    port_z = base_h * 0.52
    port_h = min(3.0 * MM, base_h * 0.5)
    for side, ports in ((-1, spec["left_ports"]), (1, spec["right_ports"])):
        for kind, y_mm in ports:
            y = depth / 2 - y_mm * MM
            if kind == "usbc":
                inlay(base, side, side * width / 2, y, port_z, 8.6 * MM, port_h, 0.03 * MM, port_mat, dark)
            elif kind == "magsafe":
                inlay(base, side, side * width / 2, y, port_z, 13 * MM, port_h * 0.8, 0.03 * MM, port_mat, dark)
            elif kind == "jack":
                inlay(base, side, side * width / 2, y, port_z, 3.5 * MM, 3.5 * MM if pro else port_h, 0.03 * MM, port_mat, dark)
            elif kind == "hdmi":
                inlay(base, side, side * width / 2, y, port_z, 14 * MM, 4.4 * MM, 0.03 * MM, port_mat, dark)
            elif kind == "sd":
                inlay(base, side, side * width / 2, y, port_z, 24 * MM, 2.1 * MM, 0.02 * MM, port_mat, dark)
    base_obj = base.object(rig)

    # Keycaps: individual keys with softened tops, printed from the one legends picture.
    keys = Builder("Keys")
    x_low, y_low = -WELL_WIDTH / 2, well_y - WELL_DEPTH / 2
    keys.uv = lambda x, y, z: ((x - x_low) / WELL_WIDTH, (y - y_low) / WELL_DEPTH)
    cap_mat = material("Keycap", 0x0C0C0E, 0.0, 0.42, image=shared["keyboard"])
    touch_mat = material("TouchID", 0x050506, 0.0, 0.12)
    key_top = base_h + 0.32 * MM
    for key in keyboard_layout():
        chosen = touch_mat if key["label"] == "touch" else cap_mat
        shape = rounded(key["w"], key["h"], 2.3 * MM if key["h"] > 8 * MM else 1.2 * MM, (key["x"], well_y + key["y"]), continuous=False, segments=5)
        keys.loft(shape, slab_profile(well_floor, key_top, 0, 0.28 * MM, 3), chosen, cap_end=True)
    keys.object(rig)

    # Speaker grilles beside the keyboard on the Pros.
    if pro:
        grille_mat = material("Grille", spec["color"], 1.0, spec.get("roughness", 0.36), image=grille_texture(os.path.join(shared["folder"], f"grille-{spec['id']}.png"), spec["color"]))
        grilles = Builder("Grilles")
        grille_w, grille_h = spec["grille_w"] * MM, 108 * MM
        for side in (-1, 1):
            cx = side * (WELL_WIDTH / 2 + 2.2 * MM + grille_w / 2)
            x0, y0 = cx - grille_w / 2, well_y - grille_h / 2
            grilles.uv = lambda x, y, z, x0=x0, y0=y0: ((x - x0) / grille_w, (y - y0) / grille_h)
            grilles.plate(rounded(grille_w, grille_h, 0, (cx, well_y)), base_h + 0.01 * MM, grille_mat)
        grilles.object(rig)

    # An invisible sheet over the deck, on which Glide lays the screen's light as it falls on the metal. Its UVs run from
    # the hinge (v = 0) to the front edge (v = 1).
    glow = Builder("ScreenGlow")
    glow_back, glow_front = depth / 2 - 3.5 * MM, -depth / 2 + edge
    glow.uv = lambda x, y, z: ((x + width / 2) / width, (glow_back - y) / (glow_back - glow_front))
    glow.plate(rounded(width - 2 * edge, glow_back - glow_front, (0, 0, corner, corner), (0, (glow_back + glow_front) / 2), segments=22), base_h + 0.03 * MM, material("ScreenGlow", 0x000000, 0.0, 1.0))
    glow.object(rig)

    # The hinge: a dark barrel behind the deck, with the lid hung from it.
    pivot = (0, depth / 2 - 2.9 * MM, base_h + 0.25 * MM)
    hinge = Builder("Hinge")
    hinge_r = 2.5 * MM
    length = width - 2 * corner - 6 * MM
    hinge.matrix = Matrix.Translation((-length / 2, pivot[1], pivot[2])) @ Matrix.Rotation(math.radians(90), 4, 'Y')
    hinge.loft(circle(hinge_r, segments=32), slab_profile(0, length, 0.3 * MM, 0.3 * MM, 3), hinge_mat, cap_start=True, cap_end=True)
    hinge.object(rig)

    # Lid, modelled closed over the base and shorter than it: the hinge takes up the last few millimetres.
    lid_depth = depth - 5.0 * MM
    lid_center = -depth / 2 + lid_depth / 2
    z0 = base_h + gap
    z1 = z0 + lid_t
    shell = Builder("LidShell")
    lid_outline = rounded(width, lid_depth, (2.2 * MM, 2.2 * MM, corner, corner), (0, lid_center), segments=22)
    shell.bow = (0, lid_center, width / 2, lid_depth / 2, 0.02, 0.09)
    shell.loft(lid_outline, slab_profile(z0, z1, 0.8 * MM, (1.0 if pro else 0.8) * MM, 6), body, cap_start=True, cap_end=True)
    shell.bow = None

    # The display glass, set into the shell with a thin metal rim showing around it.
    glass = Builder("DisplayGlass")
    rim = 0.62 * MM
    glass.loft(inset(lid_outline, rim), [(0, z0 + 0.1 * MM, 1, 0)] + arc(0.12 * MM, z0 + 0.1 * MM - 0.03 * MM, 0.12 * MM, 0, -90, 2), bezel, cap_end=False)
    face_z = z0 - 0.05 * MM
    glass.plate(inset(lid_outline, rim + 0.12 * MM), face_z, bezel, up=False)

    screen_w, screen_h = screen_size(spec["diag"], spec["px"])
    top_margin = spec["top_margin"] * MM
    # The closed lid's front edge is the display's top, so the screen's "up" points along -Y here.
    top_y = lid_center - lid_depth / 2 + top_margin
    bottom_y = top_y + screen_h
    screen_center = (0, (top_y + bottom_y) / 2)
    screen_z = face_z - 0.01 * MM
    screen_radius = spec["screen_radius"] * MM
    surface = material("ScreenSurface", 0x000000, 0.0, 0.06)
    screen = Builder("Screen")
    x0_s, x1_s = -screen_w / 2, screen_w / 2
    screen.uv = lambda x, y, z: ((x - x0_s) / (x1_s - x0_s), (y - bottom_y) / (top_y - bottom_y))
    screen.plate(rounded(screen_w, screen_h, (0, 0, screen_radius, screen_radius), screen_center, continuous=False, segments=10), screen_z, surface, up=False)

    # The camera housing cuts down from the top of the display, with small flared corners.
    notch_w, notch_h = screen_w * 0.1, screen_h * 0.0275
    fillet = 0.9 * MM
    corner_r = 1.5 * MM
    half = notch_w / 2
    notch_points = []
    for step in range(7):
        angle = math.radians(90 * step / 6)
        notch_points.append((half + fillet - fillet * math.sin(angle), top_y + fillet - fillet * math.cos(angle)))
    for step in range(7):
        angle = math.radians(90 * step / 6)
        notch_points.append((half - corner_r + corner_r * math.cos(angle), top_y + notch_h - corner_r + corner_r * math.sin(angle)))
    notch_outline = notch_points + [(-x, y) for x, y in reversed(notch_points)]
    glass.plate(notch_outline, screen_z - 0.01 * MM, bezel, up=False)
    glass.plate(circle(1.15 * MM, (0, top_y + notch_h * 0.5), 20), screen_z - 0.02 * MM, lens_glass, up=False)
    glass.plate(circle(0.45 * MM, (0, top_y + notch_h * 0.5), 14), screen_z - 0.03 * MM, material("Sensor", 0x10162A, 0.3, 0.1), up=False)

    lid = bpy.data.objects.new("Lid", None)
    bpy.context.scene.collection.objects.link(lid)
    lid.parent = rig
    lid.location = pivot
    shell.object(lid, pivot)
    glass.object(lid, pivot)
    screen_obj = screen.object(lid, pivot)

    x_rect = (-screen_w / 2 - pivot[0], bottom_y - pivot[1], screen_w / 2 - pivot[0], top_y - pivot[1], screen_z - pivot[2])
    return {"lid": lid, "screen": screen_obj, "screen_rect": x_rect, "screen_size": (screen_w, screen_h), "base": base_obj}


# MARK: iPhones

def lens_texture(path):
    """What you see looking into a phone's camera: dark stepped rings, a coated element with a violet-blue cast, the deep
    pupil at its centre, and the soft window of light that glass always seems to hold."""
    size = 768
    ys, xs = np.mgrid[0:size, 0:size]
    x = (xs + 0.5) / size * 2 - 1
    y = 1 - (ys + 0.5) / size * 2
    r = np.hypot(x, y)

    def band(low, high, soft=0.012):
        return np.clip((r - low) / soft, 0, 1) * np.clip((high - r) / soft, 0, 1)

    color = np.zeros((size, size, 3), dtype=np.float32)
    base = 0.006 + 0.012 * (1 - r)
    for channel in range(3):
        color[..., channel] = base
    # Machined steps of the barrel.
    for low, high, level in ((0.92, 0.94, 0.05), (0.80, 0.82, 0.035), (0.70, 0.715, 0.05)):
        color += band(low, high)[..., None] * level
    # The coated element: a violet-blue glow toward its edge, fading into the pupil.
    glow = np.clip((r - 0.2) / 0.3, 0, 1) * np.clip((0.68 - r) / 0.2, 0, 1)
    color[..., 0] += glow * 0.040
    color[..., 1] += glow * 0.030
    color[..., 2] += glow * 0.095
    color *= np.clip((r - 0.12) / 0.14, 0.08, 1)[..., None]
    # Reflections: a soft curved window high on the left, and a small one low on the right.
    distance = np.hypot(x + 0.26, y - 0.3)
    window = np.clip((0.2 - distance) / 0.12, 0, 1) ** 2 * np.clip((x + 0.5 * y + 0.72) * 3, 0, 1)
    color += window[..., None] * np.array([0.30, 0.31, 0.36], dtype=np.float32)
    spark = np.clip((0.05 - np.hypot(x - 0.24, y + 0.26)) / 0.04, 0, 1) ** 2
    color += spark[..., None] * np.array([0.10, 0.09, 0.16], dtype=np.float32)

    pixels = np.ones((size, size, 4), dtype=np.float32)
    pixels[..., :3] = color
    image = bpy.data.images.new("Lens", size, size, alpha=True)
    image.pixels.foreach_set(pixels[::-1].ravel())
    image.filepath_raw = path
    image.file_format = 'PNG'
    image.save()


def lens_stack(builder, x, y, base, radius, ring_mat, mats, height=1.0 * MM):
    """One camera: a machined ring standing proud, a black barrel inside it, and the glass at the bottom."""
    center = (x, y)
    outer = circle(radius, center, 64)
    lip = 0.22 * MM
    ring_w = radius * 0.095
    top = base + height
    profile = [(0, base - 0.1 * MM, 1, 0)] + arc(lip, top - lip, lip, 0, 90, 5) + [(ring_w, top, 0, 1)] + arc(ring_w, top - 0.1 * MM, 0.1 * MM, 90, 180, 3)
    builder.loft(outer, profile, ring_mat)
    # Down the inside of the ring, to the glass.
    floor = base + 0.02 * MM
    inner_r = radius - ring_w - 0.1 * MM
    inner = inset(outer, ring_w + 0.1 * MM)
    builder.loft(inner, [(0, top - 0.1 * MM, -1, 0), (inner_r * 0.05, floor, -0.92, 0.38)], mats["barrel"])
    face_r = inner_r * 0.95
    keep = builder.uv
    builder.uv = lambda px, py, pz: ((px - x) / (2 * face_r) + 0.5, (py - y) / (2 * face_r) + 0.5)
    builder.plate(circle(face_r, center, 64), floor, mats["glass"])
    builder.uv = keep


def flash_unit(builder, x, y, base, radius, mat, rim_mat):
    outer = circle(radius, (x, y), 36)
    builder.loft(outer, [(0, base - 0.1 * MM, 1, 0)] + arc(0.12 * MM, base + 0.1 * MM, 0.12 * MM, 0, 90, 3), rim_mat)
    builder.loft(inset(outer, 0.12 * MM), [(0, base + 0.22 * MM, 0, 1)], mat, cap_end=True)


def side_button(builder, direction, surface, y, length, across, rise, mat):
    # Local y runs along the phone, local z points out of its side.
    builder.matrix = Matrix.Translation((surface, y, 0)) @ Matrix((Vector((0, 0, -direction)), Vector((0, 1, 0)), Vector((direction, 0, 0)))).transposed().to_4x4()
    builder.loft(stadium(across, length), slab_profile(-0.0003, rise, 0, min(rise * 0.7, 0.2 * MM), 3), mat, cap_end=True)
    builder.matrix = Matrix.Identity(4)


def build_iphone(spec, rig, shared):
    width, height, thickness = spec["w"], spec["hgt"], spec["t"]
    half = thickness / 2
    corner = spec["corner"] * MM
    line = spec["line"]

    frame_mat = material("Frame", spec["color"], 1.0, spec["frame_roughness"])
    back_mat = material("BackGlass", spec["back"], spec.get("back_metal", 0.0), spec["back_roughness"], coat=0.2, coat_roughness=0.3)
    bezel = material("BezelGlass", 0x020203, 0.0, 0.05)
    hole = material("Hole", 0x010101, 0.0, 0.8)
    band = material("AntennaBand", spec["band"], 0.2, 0.42)
    port_mat = material("PortMetal", 0x3A3A3C, 1.0, 0.35)
    ring_mat = material("LensRing", spec["ring"], 1.0, 0.3)
    lens_mats = dict(barrel=material("LensBarrel", 0x050506, 0.0, 0.4), glass=material("LensElement", 0x05060D, 0.0, 0.05, image=shared["lens"]))

    # Everything hangs off a holder turned upright: local +Z is the side facing the viewer, local +Y is up.
    holder = bpy.data.objects.new("Holder", None)
    bpy.context.scene.collection.objects.link(holder)
    holder.parent = rig
    holder.rotation_euler = (math.radians(90), 0, 0)

    # The frame, with its soft edges toward the back and tight ones toward the front.
    outline = rounded(width, height, corner, segments=28)
    frame = Builder("Frame")
    back_edge = spec["back_edge"] * MM
    front_edge = spec["front_edge"] * MM
    belly = spec.get("belly", 7.0)
    profile = arc(back_edge, -half + back_edge, back_edge, -90, -belly, 7) + arc(front_edge, half - front_edge, front_edge, belly, 90, 5)
    frame.bow = None
    frame.loft(outline, profile, frame_mat, cap_start=True, cap_end=True)

    # Antenna lines crossing the sides and the top and bottom.
    side_depth = thickness - back_edge - front_edge
    side_z = (front_edge - back_edge) / 2 * -1
    for side in (-1, 1):
        for y_off in spec["band_y"]:
            for sign in (-1, 1):
                frame.matrix = side_matrix(side, sign * (height / 2 - y_off * MM), side_z, side * width / 2)
                frame.plate(rounded(0.95 * MM, side_depth, 0), 0.006 * MM, band)
    frame.matrix = Matrix.Identity(4)
    for sign in (-1, 1):
        for x_off in spec["band_x"]:
            at = Vector((sign * (width / 2 - x_off * MM), 0, side_z))
            for top in (-1, 1):
                frame.matrix = Matrix.Translation((at.x, top * height / 2, at.z)) @ Matrix((Vector((1, 0, 0)), Vector((0, 0, top)), Vector((0, top, 0)))).transposed().to_4x4()
                frame.plate(rounded(0.95 * MM, side_depth, 0), 0.006 * MM, band)
    frame.matrix = Matrix.Identity(4)
    frame_obj = frame.object(holder)

    # Buttons: action and volume on the left; side button and Camera Control on the right.
    buttons = Builder("Buttons")
    across = min(2.9 * MM, thickness * 0.5)
    rise = 0.38 * MM
    scale = height / (150 * MM)
    left = [(41.5, 7.4)] + ([(26.5, 13.5), (11.0, 13.5)])
    for y_mm, length_mm in left:
        side_button(buttons, -1, -width / 2, y_mm * scale * MM, length_mm * MM, across, rise, frame_mat)
    side_button(buttons, 1, width / 2, 24.5 * scale * MM, 20 * MM, across, rise, frame_mat)
    side_button(buttons, 1, width / 2, -26.0 * scale * MM, 18.5 * MM, across, 0.05 * MM, material("CameraControl", spec["band"], 0.0, 0.08))
    buttons.object(holder)

    # The bottom edge: USB-C and speaker holes.
    bottom = Builder("BottomEdge")
    bottom_matrix = Matrix.Translation((0, -height / 2, side_z)) @ Matrix((Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0)))).transposed().to_4x4()
    bottom.matrix = bottom_matrix
    port = stadium(8.8 * MM, min(3.1 * MM, thickness * 0.5))
    bottom.loft(port, slab_profile(-0.0002, 0.02 * MM, 0, 0, 1), port_mat, cap_end=False)
    bottom.plate(inset(port, 0.35 * MM), 0.025 * MM, hole)
    if spec.get("speaker", True):
        for side in (-1, 1):
            for index in range(6):
                bottom.plate(circle(0.55 * MM, (side * (11.5 + index * 2.05) * MM, 0), 12), 0.008 * MM, hole)
    bottom.matrix = Matrix.Identity(4)
    bottom.object(holder)

    # The front: a sheet of black glass with a softly rolled edge, standing just proud of the frame.
    front = Builder("FrontGlass")
    glass_in = front_edge * 0.82
    glass_outline = inset(outline, glass_in)
    roll = 0.55 * MM
    proud = 0.16 * MM
    front.loft(glass_outline, [(0, half - 0.05 * MM, 1, 0)] + arc(roll, half + proud - roll, roll, 0, 90, 5), bezel, cap_end=True)
    face_z = half + proud
    earpiece = stadium(9.5 * MM, 0.55 * MM, (0, height / 2 - 1.15 * MM))
    front.plate(earpiece, face_z + 0.006 * MM, hole)
    front.object(holder)

    screen_w, screen_h = screen_size(spec["diag"], spec["px"])
    surface = material("ScreenSurface", 0x000000, 0.0, 0.06)
    screen = Builder("Screen")
    x0_s, y0_s = -screen_w / 2, -screen_h / 2
    screen.uv = lambda x, y, z: ((x - x0_s) / screen_w, (y - y0_s) / screen_h)
    screen_z = face_z + 0.008 * MM
    screen_r = screen_w * 0.158
    screen.plate(rounded(screen_w, screen_h, screen_r / 1.5287 * 1.15, (0, 0), segments=24), screen_z, surface)
    screen_obj = screen.object(holder)

    # The Dynamic Island, with the camera just visible through it.
    island = Builder("Island")
    island_w, island_h = screen_w * 0.292, screen_w * 0.0855
    island_y = screen_h / 2 - screen_w * 0.0255 - island_h / 2
    island.plate(stadium(island_w, island_h, (0, island_y), 18), screen_z + 0.008 * MM, material("IslandBlack", 0x000000, 0.0, 0.1))
    island.plate(circle(island_h * 0.22, (island_w * 0.31, island_y), 20), screen_z + 0.012 * MM, material("IslandLens", 0x0A0E1C, 0.2, 0.06))
    island.object(holder)

    # The back. `camera` is modelled looking at the back of the phone: its +X is the viewer's right, its +Z points away.
    camera = Builder("Back")
    flip = Matrix.Rotation(math.radians(180), 4, 'Y') @ Matrix.Translation((0, 0, half))
    camera.matrix = flip
    camera.bow = (0, 0, width / 2, height / 2, 0.05, 0.08)

    if line == "pro":
        # Aluminium unibody: a raised camera plateau across the top, and a matte glass panel set into the back below it.
        plate_h = height * 0.262
        margin = 1.55 * MM
        plate_w = width - 2 * margin
        plate_y = height / 2 - margin - plate_h / 2
        rise = 1.55 * MM
        fillet = 0.75 * MM
        plateau = rounded(plate_w, plate_h, (corner - margin, corner - margin, 3.2 * MM, 3.2 * MM), (0, plate_y), segments=18)
        plateau_mat = material("Plateau", spec["color"], spec.get("plateau_metal", 0.6), spec["frame_roughness"] + 0.12)
        camera.loft(plateau, [(-0.2 * MM, -0.05 * MM, 1, 0)] + arc(fillet, rise - fillet, fillet, 0, 90, 6), plateau_mat, cap_end=True)
        # The unibody's back has the plateau's satin finish, not the mirror polish of the frame's edges.
        camera.plate(inset(outline, back_edge * 0.8), 0.006 * MM, plateau_mat)
        panel_top = plate_y - plate_h / 2 - 5.6 * MM
        panel_bottom = -height / 2 + 1.7 * MM
        panel_h = panel_top - panel_bottom
        panel = rounded(width - 3.4 * MM, panel_h, (5.2 * MM, 5.2 * MM, corner - 1.7 * MM, corner - 1.7 * MM), (0, (panel_top + panel_bottom) / 2), segments=18)
        camera.plate(panel, 0.012 * MM, back_mat)
        unit = width / (71.9 * MM)
        cx, cy = 0, plate_y
        lens_r = 10.0 * MM * unit
        top = rise
        for lx, ly in ((-19.4, 8.6), (-19.4, -10.2), (-0.6, -0.8)):
            lens_stack(camera, cx + lx * MM * unit, cy + ly * MM * unit, top, lens_r, ring_mat, lens_mats, height=1.05 * MM)
        flash_unit(camera, cx + 22.8 * MM * unit, cy + 9.7 * MM * unit, top, 3.1 * MM * unit, material("Flash", 0xDCD8CA, 0.0, 0.28), ring_mat)
        camera.plate(circle(0.55 * MM, (cx + 22.8 * MM * unit, cy - 0.6 * MM * unit), 14), top + 0.01 * MM, hole)
        lidar = circle(3.1 * MM * unit, (cx + 22.8 * MM * unit, cy - 10.8 * MM * unit), 36)
        camera.loft(lidar, [(0, top + 0.01 * MM, 0, 1)], lens_mats["glass"], cap_end=True)
    elif line == "air":
        # A sheet of glass, with a polished plateau across the top, ending in a big round corner.
        panel = inset(outline, back_edge * 0.8)
        camera.plate(panel, 0.012 * MM, back_mat)
        plate_h = height * 0.163
        margin = 0.9 * MM
        plate_w = width - 2 * margin
        plate_y = height / 2 - margin - plate_h / 2
        rise = 1.15 * MM
        fillet = 0.6 * MM
        plateau = rounded(plate_w, plate_h, (corner - margin, corner - margin, plate_h * 0.42, plate_h * 0.42), (0, plate_y), segments=18)
        plateau_mat = material("Plateau", spec["color"], 0.15, 0.24)
        camera.loft(plateau, [(-0.2 * MM, -0.05 * MM, 1, 0)] + arc(fillet, rise - fillet, fillet, 0, 90, 6), plateau_mat, cap_end=True)
        lens_stack(camera, -plate_w / 2 + 12.5 * MM, plate_y, rise, 7.4 * MM, ring_mat, lens_mats, height=0.8 * MM)
        camera.plate(circle(0.5 * MM, (plate_w * 0.1, plate_y), 12), rise + 0.01 * MM, hole)
        flash_unit(camera, plate_w * 0.24, plate_y, rise, 1.9 * MM, material("Flash", 0xF3EFE2, 0.0, 0.32), ring_mat)
    else:
        # A sheet of glass, with two cameras in a raised pill at the top left, and the flash beside it.
        panel = inset(outline, back_edge * 0.8)
        camera.plate(panel, 0.012 * MM, back_mat)
        pill_w, pill_h = 19.6 * MM, 38.0 * MM
        pill_x = -width / 2 + 5.4 * MM + pill_w / 2
        pill_y = height / 2 - 5.4 * MM - pill_h / 2
        rise = 1.1 * MM
        fillet = 0.55 * MM
        pill = stadium(pill_w, pill_h, (pill_x, pill_y), 22)
        camera.loft(pill, [(-0.2 * MM, -0.05 * MM, 1, 0)] + arc(fillet, rise - fillet, fillet, 0, 90, 6), material("PillGlass", spec["back"], 0.1, 0.16), cap_end=True)
        for sign in (-1, 1):
            lens_stack(camera, pill_x, pill_y + sign * 9.3 * MM, rise, 7.9 * MM, ring_mat, lens_mats, height=0.75 * MM)
        flash_unit(camera, pill_x + pill_w / 2 + 5.0 * MM, pill_y + 13.5 * MM, 0.02 * MM, 2.2 * MM, material("Flash", 0xF3EFE2, 0.0, 0.32), ring_mat)
        camera.plate(circle(0.45 * MM, (pill_x + pill_w / 2 + 5.0 * MM, pill_y + 5.0 * MM), 12), 0.03 * MM, hole)

    camera.matrix = Matrix.Identity(4)
    camera.object(holder)

    return {"lid": None, "screen": screen_obj, "screen_rect": (-screen_w / 2, -screen_h / 2, screen_w / 2, screen_h / 2, screen_z), "screen_size": (screen_w, screen_h), "base": frame_obj}


# MARK: Studio

def build_studio(path):
    """The light the devices are shown in: a dark room with soft lights placed for what each surface reflects, as a
    product photographer would. Written as real HDR values, because a metal surface only looks like metal when its
    reflections are far brighter than the room around them.

    Axes are SceneKit's: +X right, +Y up, +Z toward the camera. Both SceneKit and Cycles read such a picture with -Z (the
    way the camera looks) three quarters of the way across it."""
    width, height = 2048, 1024
    longitude = (np.arange(width) + 0.5) / width * 2 * np.pi - np.pi
    latitude = np.pi / 2 - (np.arange(height) + 0.5) / height * np.pi
    lon, lat = np.meshgrid(longitude, latitude)
    d = np.stack((-np.cos(lat) * np.cos(lon), np.sin(lat), -np.cos(lat) * np.sin(lon)), axis=-1)

    def smooth(edge0, edge1, value):
        t = np.clip((value - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)

    elevation = np.degrees(lat)

    # The room: dark, a little lighter toward the ceiling.
    radiance = 0.022 + 0.035 * np.clip(d[..., 1], 0, 1) + 0.008 * np.clip(-d[..., 1], 0, 1)

    # A long graded card behind and above the device. Decks and lids at rest reflect this, so their brightness runs
    # smoothly across them instead of being one flat tone.
    azimuth_ahead = np.degrees(np.abs(np.arctan2(d[..., 0], -d[..., 2])))
    wide = 1 - smooth(70, 112, azimuth_ahead)
    card = smooth(4, 46, elevation) * (1 - 0.72 * smooth(52, 82, elevation))
    radiance = radiance + wide * card * 1.55

    def softbox(direction, half_w, half_h, power, softness=0.22):
        nonlocal radiance
        c = np.array(direction, dtype=np.float64)
        c /= np.linalg.norm(c)
        helper = np.array([0, 1, 0]) if abs(c[1]) < 0.9 else np.array([0, 0, 1])
        u = np.cross(helper, c)
        u /= np.linalg.norm(u)
        v = np.cross(c, u)
        facing = (d * c).sum(-1)
        with np.errstate(divide='ignore', invalid='ignore'):
            pu = (d * u).sum(-1) / facing
            pv = (d * v).sum(-1) / facing
        def edge(value, half):
            return np.nan_to_num(np.clip((half - np.abs(value)) / (half * softness), 0, 1))
        mask = edge(pu, half_w) * edge(pv, half_h)
        mask = mask * mask * (3 - 2 * mask)
        radiance = radiance + np.where(facing > 0, mask, 0) * power

    # Overhead, toward the camera: what a closed lid and a phone tilted back reflect.
    softbox((0, 0.86, 0.5), 1.15, 0.42, 1.7, softness=0.9)
    # Narrow strips just to either side of the device, seen in the sides of a turned phone and along rounded edges.
    softbox((0.56, 0.04, -0.83), 0.055, 1.5, 9.0, softness=0.6)
    softbox((-0.62, 0.06, -0.78), 0.05, 1.3, 7.0, softness=0.6)
    # Broad sources to the far left and right, for the long highlights around curved corners.
    softbox((1, 0.15, 0.25), 0.55, 1.1, 2.6, softness=0.45)
    softbox((-1, 0.2, 0.15), 0.7, 1.1, 2.0, softness=0.45)
    # A low fill behind the camera, for the faces that look down at it. Straight behind the camera stays dark, so that
    # screens don't glare.
    softbox((0, -0.5, 0.86), 1.5, 0.34, 1.2, softness=0.8)

    pixels = np.ones((height, width, 4), dtype=np.float32)
    pixels[..., 0] = radiance
    pixels[..., 1] = radiance
    pixels[..., 2] = radiance * 1.008
    image = bpy.data.images.new("Studio", width, height, alpha=False, float_buffer=True)
    image.colorspace_settings.name = 'Non-Color'
    image.pixels.foreach_set(pixels[::-1].ravel())
    image.filepath_raw = path
    image.file_format = 'HDR'
    image.save()


def add_studio_to_scene(spec, studio_path, bounds):
    """So that the .blend renders as it stands: the same light Glide uses, and a camera on the finished pose."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 128
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1200 if spec["family"] == "macbook" else 1600
    scene.render.film_transparent = True
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    tree = world.node_tree
    environment = tree.nodes.new("ShaderNodeTexEnvironment")
    environment.image = bpy.data.images.load(studio_path, check_existing=True)
    mapping = tree.nodes.new("ShaderNodeMapping")
    coords = tree.nodes.new("ShaderNodeTexCoord")
    tree.links.new(coords.outputs["Generated"], mapping.inputs["Vector"])
    tree.links.new(mapping.outputs["Vector"], environment.inputs["Vector"])
    tree.links.new(environment.outputs["Color"], tree.nodes["Background"].inputs["Color"])
    scene.world = world

    camera = bpy.data.cameras.new("Hero")
    camera.sensor_fit = 'VERTICAL'
    camera.angle_y = math.radians(FIELD_OF_VIEW)
    holder = bpy.data.objects.new("Hero", camera)
    scene.collection.objects.link(holder)
    holder.rotation_euler = (math.radians(90), 0, 0)
    low, high = bounds["min"], bounds["max"]
    aspect = scene.render.resolution_x / scene.render.resolution_y
    span = max((high[2] - low[2]) / 2, (high[0] - low[0]) / 2 / aspect) * 1.12
    holder.location = ((low[0] + high[0]) / 2, low[1] - span / math.tan(math.radians(FIELD_OF_VIEW / 2)), (low[2] + high[2]) / 2)
    scene.camera = holder

    # Cycles lights the deck from the screen by itself.
    glow_sheet = bpy.data.objects.get("ScreenGlow")
    if glow_sheet:
        glow_sheet.hide_render = True
        glow_sheet.hide_viewport = True

    # In Glide the screen shows the video; here it glows with a plain gradient.
    surface = bpy.data.materials.get("ScreenSurface")
    tree = surface.node_tree
    principled = tree.nodes["Principled BSDF"]
    coords = tree.nodes.new("ShaderNodeTexCoord")
    ramp = tree.nodes.new("ShaderNodeMixRGB")
    ramp.inputs["Color1"].default_value = (0.05, 0.08, 0.55, 1)
    ramp.inputs["Color2"].default_value = (0.30, 0.07, 0.62, 1)
    split = tree.nodes.new("ShaderNodeSeparateXYZ")
    tree.links.new(coords.outputs["UV"], split.inputs["Vector"])
    tree.links.new(split.outputs["X"], ramp.inputs["Fac"])
    tree.links.new(ramp.outputs["Color"], principled.inputs["Emission Color"])
    principled.inputs["Emission Strength"].default_value = 1.0

    bpy.ops.file.pack_all()


# MARK: Motions
# Studied from product films and animated mockups, frame by frame. What makes them look filmed:
#   - The device starts in frame or leaves the edge at speed; nothing fades in out of an empty picture.
#   - Each part has its own timing. The lid leads, the turn follows, and they overlap.
#   - Speed contrast: quick moves (a lid opens in under a second, a full turn takes about 1.5 s), long slow settles.
#   - The camera never quite stops: after arriving, the picture keeps a very slow drift.
#   - The display is off while the lid is shut, and wakes as it opens.
# Positions are in widths of the device, turns in degrees, all as offsets from the resting pose.

FIELD_OF_VIEW = 14.0  # Keep in step with MockupStage.fieldOfViewDegrees.
LID_OPEN = 100.0
LAPTOP_REST = (10.0, 0.0, 0.0)
PHONE_REST = (3.0, 3.0, -14.0)
DRIFT_SECONDS = 18.0

# The camera is framed for the open laptop, whose middle is higher than the closed one's, so a closed laptop is lifted
# to sit in the middle of the frame until it opens.
CLOSED_LIFT = 0.3


def bezier(x1, y1, x2, y2):
    """An easing curve, as in a motion designer's graph editor."""
    def value(u):
        if u <= 0:
            return 0.0
        if u >= 1:
            return 1.0
        low, high = 0.0, 1.0
        for _ in range(26):
            mid = (low + high) / 2
            x = 3 * (1 - mid) ** 2 * mid * x1 + 3 * (1 - mid) * mid ** 2 * x2 + mid ** 3
            if x < u:
                low = mid
            else:
                high = mid
        mid = (low + high) / 2
        return 3 * (1 - mid) ** 2 * mid * y1 + 3 * (1 - mid) * mid ** 2 * y2 + mid ** 3
    return value


ARRIVE = bezier(0.12, 0.72, 0.18, 1.0)    # Already moving fast at the start, then a long settle.
WHIP = bezier(0.66, 0.0, 0.2, 1.0)        # Gathers speed, moves quickly, slows down over a longer time.
LID = bezier(0.38, 0.0, 0.14, 1.0)        # A hand-opened lid: quick through the middle, easing to its stop.
GLIDE = bezier(0.3, 0.12, 0.12, 1.0)      # A slow camera move, which takes its time stopping.


def ramp(t, start, end, begin, finish, ease):
    if end <= start:
        return finish
    return begin + (finish - begin) * ease(min(1.0, max(0.0, (t - start) / (end - start))))


def bump(t, start, end, height):
    """Up and back down: a smooth arc between two moments."""
    u = (t - start) / (end - start)
    return height * math.sin(math.pi * u) ** 2 if 0 < u < 1 else 0.0


def laptop_open_from_above(t):
    return dict(lid=ramp(t, 0.25, 2.0, 0, LID_OPEN, LID), rx=ramp(t, 0.0, 2.8, 48, 0, LID), rz=ramp(t, 0.0, 3.2, -10, 0, GLIDE),
                lz=ramp(t, 0.15, 2.6, CLOSED_LIFT, 0, LID), ly=ramp(t, 0.0, 3.2, 0.1, 0, GLIDE))


def laptop_slide_in(t):
    return dict(lx=ramp(t, 0.0, 1.6, 1.3, 0, ARRIVE), rz=ramp(t, 0.0, 2.9, -58, 0, ARRIVE), rx=ramp(t, 0.25, 2.9, 26, 0, GLIDE),
                lz=ramp(t, 0.45, 2.6, CLOSED_LIFT, 0, LID), lid=ramp(t, 0.55, 2.25, 2, LID_OPEN, LID))


def laptop_hero_reveal(t):
    return dict(lid=ramp(t, 0.2, 1.1, 12, LID_OPEN, LID), rz=ramp(t, 0.0, 4.2, -30, 0, GLIDE), rx=ramp(t, 0.0, 4.2, -3, 0, GLIDE),
                ly=ramp(t, 0.0, 4.2, -0.14, 0, GLIDE), lz=ramp(t, 0.1, 1.5, 0.12, 0, LID))


def laptop_whip_turn(t):
    drift = ramp(t, 0.0, 0.55, 20, 15, lambda u: u)
    turn = ramp(t, 0.55, 2.3, 0, -375, WHIP)
    return dict(rz=drift + turn, rx=bump(t, 0.55, 2.3, 9), ly=bump(t, 0.55, 2.3, 0.05))


def laptop_slow_orbit(t):
    return dict(rz=ramp(t, 0.0, 5.2, 34, 0, GLIDE), rx=ramp(t, 0.0, 5.2, 5, 0, GLIDE), ly=ramp(t, 0.0, 5.2, 0.12, 0, GLIDE))


def phone_spin_in(t):
    drift = ramp(t, 0.0, 0.7, 6, 4, lambda u: u)
    turn = ramp(t, 0.7, 2.45, 0, -364, WHIP)
    return dict(rz=drift + turn, ry=ramp(t, 0.3, 3.1, 11, 0, GLIDE), lz=bump(t, 0.7, 2.45, 0.05), ly=bump(t, 0.7, 2.45, 0.1))


def phone_rise(t):
    return dict(lz=ramp(t, 0.0, 1.8, -1.55, 0, ARRIVE), rx=ramp(t, 0.0, 2.4, 34, 0, ARRIVE), rz=ramp(t, 0.0, 2.8, -36, 0, GLIDE),
                ry=ramp(t, 0.0, 2.8, 15, 0, GLIDE))


def phone_slide_in(t):
    return dict(lx=ramp(t, 0.0, 1.7, 1.55, 0, ARRIVE), rz=ramp(t, 0.0, 2.7, -72, 0, ARRIVE), ry=ramp(t, 0.0, 2.8, -12, 0, GLIDE),
                rx=ramp(t, 0.0, 2.2, 8, 0, GLIDE))


def phone_tilt_up(t):
    return dict(rx=ramp(t, 0.0, 2.1, -72, 0, LID), lz=ramp(t, 0.0, 2.1, -0.32, 0, LID), rz=ramp(t, 0.0, 2.9, 24, 0, GLIDE),
                ry=ramp(t, 0.0, 2.9, -10, 0, GLIDE))


def phone_slow_orbit(t):
    return dict(rz=ramp(t, 0.0, 5.4, 40, 0, GLIDE), ry=ramp(t, 0.0, 5.4, 6, 0, GLIDE), rx=ramp(t, 0.0, 5.4, 4, 0, GLIDE),
                ly=ramp(t, 0.0, 5.4, 0.22, 0, GLIDE))


def stay(t):
    return {}


LAPTOP_MOTIONS = [
    dict(id="open-from-above", title="Open from above", subtitle="Seen from above, the lid lifts and the camera comes down", settle=3.2, curve=laptop_open_from_above),
    dict(id="slide-in-open", title="Slide in and open", subtitle="Sweeps in from the side and opens as it slows", settle=2.9, curve=laptop_slide_in),
    dict(id="hero-reveal", title="Hero reveal", subtitle="Low and close: the lid opens while the camera orbits", settle=4.2, curve=laptop_hero_reveal),
    dict(id="whip-turn", title="Whip turn", subtitle="A quick full turn that settles facing you", settle=2.3, curve=laptop_whip_turn),
    dict(id="slow-orbit", title="Slow orbit", subtitle="A long, slow camera move around the open laptop", settle=5.2, curve=laptop_slow_orbit),
    dict(id="idle", title="Idle", subtitle="Already in place, with a slow camera drift", settle=0.0, curve=stay),
]

PHONE_MOTIONS = [
    dict(id="spin-in", title="Spin reveal", subtitle="A quick full turn, showing its back on the way", settle=3.1, curve=phone_spin_in),
    dict(id="rise", title="Rise", subtitle="Rises into frame, straightening as it slows", settle=2.8, curve=phone_rise),
    dict(id="slide-in", title="Slide in", subtitle="Sweeps in from the side, turning to face you", settle=2.8, curve=phone_slide_in),
    dict(id="tilt-up", title="Stand up", subtitle="Stands up from lying flat", settle=2.9, curve=phone_tilt_up),
    dict(id="slow-orbit", title="Slow orbit", subtitle="A long, slow camera move around the phone", settle=5.4, curve=phone_slow_orbit),
    dict(id="idle", title="Idle", subtitle="Already in place, with a slow camera drift", settle=0.0, curve=stay),
]


def drift(tau, family):
    """After arriving, the picture never quite stops. Each channel starts from zero at rest with no speed, so it picks up
    seamlessly from the settle, and it comes back to the same point every DRIFT_SECONDS."""
    swing = (1 - math.cos(2 * math.pi * tau / DRIFT_SECONDS)) / 2
    second = (1 - math.cos(4 * math.pi * tau / DRIFT_SECONDS)) / 2
    if family == "macbook":
        return dict(rz=-3.2 * swing, rx=0.9 * second, ly=-0.012 * swing)
    return dict(rz=4.2 * swing, rx=1.2 * second, ry=-0.9 * swing, ly=-0.02 * swing)


def motion_state(motion, t, family, lid_rest):
    """Every channel of a motion at a moment: its arrival, then the drift that carries on after it."""
    state = dict(lx=0.0, ly=0.0, lz=0.0, rx=0.0, ry=0.0, rz=0.0, lid=lid_rest)
    state.update(motion["curve"](t))
    if t > motion["settle"]:
        for name, value in drift(t - motion["settle"], family).items():
            state[name] += value
    return state


def display_level(lid_degrees, family):
    """A laptop's display is off while the lid is shut, and wakes as it opens."""
    if family != "macbook":
        return 1.0
    u = min(1.0, max(0.0, (lid_degrees - 30) / 50))
    return u * u * (3 - 2 * u)


def clear_animation(obj):
    if obj.animation_data:
        obj.animation_data.action = None


def set_rest(rig, lid, rest, lid_rest):
    clear_animation(rig)
    rig.location = (0, 0, 0)
    rig.rotation_mode = 'XYZ'
    rig.rotation_euler = tuple(math.radians(value) for value in rest)
    if lid:
        clear_animation(lid)
        lid.rotation_mode = 'XYZ'
        lid.rotation_euler = (math.radians(-lid_rest), 0, 0)
    bpy.context.view_layer.update()


def apply_state(rig, lid, state, rest, width):
    rig.location = (state["lx"] * width, state["ly"] * width, state["lz"] * width)
    rig.rotation_euler = (math.radians(rest[0] + state["rx"]), math.radians(rest[1] + state["ry"]), math.radians(rest[2] + state["rz"]))
    if lid:
        lid.rotation_euler = (math.radians(-state["lid"]), 0, 0)


def key_motion(motion, rig, lid, rest, lid_rest, width, family):
    """Keeps the motion in the .blend as editable actions: closely spaced keys through the arrival, sparse ones in the drift."""
    clear_animation(rig)
    if lid:
        clear_animation(lid)
    settle = motion["settle"]
    moments = [i / 20 for i in range(int(settle * 20) + 1)] + [settle + i / 2 for i in range(1, int(DRIFT_SECONDS * 2) + 1)]
    for moment in moments:
        frame = 1 + moment * FPS
        apply_state(rig, lid, motion_state(motion, moment, family, lid_rest), rest, width)
        rig.keyframe_insert("location", frame=frame)
        rig.keyframe_insert("rotation_euler", frame=frame)
        if lid:
            lid.keyframe_insert("rotation_euler", index=0, frame=frame)
    return rig.animation_data.action if rig.animation_data else None, (lid.animation_data.action if lid and lid.animation_data else None)


def bake_motion(motion, rest, lid_rest, width, family):
    """Every channel 60 times a second, as Glide plays it back. It loops from the end of the arrival."""
    duration = motion["settle"] + DRIFT_SECONDS
    positions, rotations, lids, display = [], [], [], []
    for index in range(round(duration * FPS) + 1):
        state = motion_state(motion, index / FPS, family, lid_rest)
        q = Euler((math.radians(rest[0] + state["rx"]), math.radians(rest[1] + state["ry"]), math.radians(rest[2] + state["rz"])), 'XYZ').to_quaternion()
        positions.append([round(state["lx"] * width, 5), round(state["ly"] * width, 5), round(state["lz"] * width, 5)])
        rotations.append([round(q.w, 6), round(q.x, 6), round(q.y, 6), round(q.z, 6)])
        lids.append(round(math.radians(-state["lid"]), 5))
        display.append(round(display_level(state["lid"], family), 4))
    return dict(id=motion["id"], title=motion["title"], subtitle=motion["subtitle"], settle=motion["settle"], duration=duration,
                positions=positions, rotations=rotations, lid=lids, display=display)


def world_bounds(rig):
    corners = []
    stack = [rig]
    while stack:
        obj = stack.pop()
        stack.extend(obj.children)
        if obj.type == 'MESH':
            for corner in obj.bound_box:
                corners.append(obj.matrix_world @ Vector(corner))
    low = [min(c[i] for c in corners) for i in range(3)]
    high = [max(c[i] for c in corners) for i in range(3)]
    return dict(min=[round(v, 6) for v in low], max=[round(v, 6) for v in high])


def build_device(spec, out_root, keyboard_path, lens_path, studio_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS

    rig = bpy.data.objects.new("Rig", None)
    scene.collection.objects.link(rig)
    rig.rotation_mode = 'XYZ'

    folder = os.path.join(out_root, spec["id"])
    os.makedirs(folder, exist_ok=True)
    shared = dict(keyboard=keyboard_path, lens=lens_path, folder=folder)

    family = spec["family"]
    parts = build_macbook(spec, rig, shared) if family == "macbook" else build_iphone(spec, rig, shared)
    lid = parts["lid"]
    if lid:
        lid.rotation_mode = 'XYZ'
    rest = LAPTOP_REST if family == "macbook" else PHONE_REST
    lid_rest = LID_OPEN if family == "macbook" else 0.0
    motions = LAPTOP_MOTIONS if family == "macbook" else PHONE_MOTIONS

    # Everything at rest: where the screen and the whole device are in the finished pose.
    set_rest(rig, lid, rest, lid_rest)
    x0, y0, x1, y1, z = parts["screen_rect"]
    matrix = parts["screen"].matrix_world
    # (u, v) of 0...1 maps to these four corners: bottom left, bottom right, top left, top right.
    corners = [matrix @ Vector((x0, y0, z)), matrix @ Vector((x1, y0, z)), matrix @ Vector((x0, y1, z)), matrix @ Vector((x1, y1, z))]
    bounds = world_bounds(rig)

    # Export with the rig unposed and the lid closed: Glide sets both from the baked motion.
    rig.location = (0, 0, 0)
    rig.rotation_euler = (0, 0, 0)
    if lid:
        lid.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    usdz = os.path.join(folder, "model.usdz")
    bpy.ops.wm.usd_export(filepath=usdz, selected_objects_only=False, export_animation=False, export_materials=True,
                          generate_preview_surface=True, export_lights=False, export_cameras=False, triangulate_meshes=True,
                          convert_orientation=False, evaluation_mode='RENDER', export_textures_mode='NEW', overwrite_textures=True)

    baked = []
    width = spec["w"]
    for motion in motions:
        set_rest(rig, lid, rest, lid_rest)
        rig_action, lid_action = key_motion(motion, rig, lid, rest, lid_rest, width, family)
        if rig_action:
            rig_action.name = f"{motion['id']} (device)"
            rig_action.use_fake_user = True
        if lid_action:
            lid_action.name = f"{motion['id']} (lid)"
            lid_action.use_fake_user = True
        baked.append(bake_motion(motion, rest, lid_rest, width, family))

    # Leave the file at rest, with each motion kept as a named action, in the same light Glide uses.
    set_rest(rig, lid, rest, lid_rest)
    add_studio_to_scene(spec, studio_path, bounds)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(folder, "model.blend"), compress=True, relative_remap=False)

    description = dict(
        id=spec["id"], name=spec["name"], family=family, finish=spec["finish"],
        screen=dict(width=round(parts["screen_size"][0], 5), height=round(parts["screen_size"][1], 5),
                    corners=[[round(c.x, 6), round(c.y, 6), round(c.z, 6)] for c in corners]),
        bounds=bounds, exposure=spec["exposure"], glow=spec.get("glow", 0), rest=dict(position=[0, 0, 0], rotationDegrees=list(rest), lidDegrees=lid_rest), motions=baked)
    with open(os.path.join(folder, "device.json"), "w") as f:
        json.dump(description, f, separators=(",", ":"))
    return dict(id=spec["id"], name=spec["name"], family=family, finish=spec["finish"])


# Outer dimensions and displays are from Apple's published specifications; finer proportions were measured from its
# product photographs.
PRO_LEFT = (("magsafe", 28), ("usbc", 53), ("usbc", 69), ("jack", 112))
PRO_RIGHT = (("sd", 62), ("usbc", 98), ("hdmi", 118))
AIR_LEFT = (("magsafe", 32), ("usbc", 52), ("usbc", 68))
AIR_RIGHT = (("jack", 44),)

DEVICES = [
    dict(id="macbook-air-13", exposure=0.62, glow=0.16, name="MacBook Air 13", family="macbook", line="air", finish="Midnight", w=0.3041, d=0.215, h=0.0113, diag=13.6,
         px=(2560, 1664), color=0x2B3038, trackpad=0x30353E, scoop=0x20242B, corner=7.2, pad=(134, 82), top_margin=5.0, screen_radius=3.4,
         left_ports=AIR_LEFT, right_ports=AIR_RIGHT, roughness=0.38),
    dict(id="macbook-air-15", exposure=0.6, glow=0.34, name="MacBook Air 15", family="macbook", line="air", finish="Starlight", w=0.3404, d=0.2376, h=0.0115, diag=15.3,
         px=(2880, 1864), color=0xE3D9C8, trackpad=0xE9DFCF, scoop=0xC9BFAE, corner=7.8, pad=(137, 86), top_margin=5.2, screen_radius=3.6,
         left_ports=AIR_LEFT, right_ports=AIR_RIGHT, roughness=0.38),
    dict(id="macbook-pro-14", exposure=0.62, glow=0.14, name="MacBook Pro 14", family="macbook", line="pro", finish="Space Black", w=0.3126, d=0.2212, h=0.0155, diag=14.2,
         px=(3024, 1964), color=0x2F2F31, trackpad=0x343436, scoop=0x232325, corner=8.0, pad=(130, 81), top_margin=4.4, screen_radius=3.6,
         left_ports=PRO_LEFT, right_ports=PRO_RIGHT, grille_w=13.0, roughness=0.4),
    dict(id="macbook-pro-16", exposure=0.56, glow=0.34, name="MacBook Pro 16", family="macbook", line="pro", finish="Silver", w=0.3557, d=0.2481, h=0.0168, diag=16.2,
         px=(3456, 2234), color=0xD9DADC, trackpad=0xE0E1E3, scoop=0xB9BABC, corner=8.6, pad=(135, 86), top_margin=4.6, screen_radius=3.8,
         left_ports=PRO_LEFT, right_ports=PRO_RIGHT, grille_w=30.0, roughness=0.36),
    dict(id="iphone-17", exposure=0.9, name="iPhone 17", family="iphone", line="base", finish="Lavender", w=0.0715, hgt=0.1496, t=0.00795, diag=6.3,
         px=(1206, 2622), color=0xC6BBDA, back=0xDDD5EC, ring=0xB9ACD2, band=0xA79BBF, corner=11.6, frame_roughness=0.3, back_roughness=0.42,
         back_edge=1.0, front_edge=0.75, band_y=(19.0,), band_x=(13.0,)),
    dict(id="iphone-air", exposure=0.95, name="iPhone Air", family="iphone", line="air", finish="Sky Blue", w=0.0747, hgt=0.1562, t=0.00564, diag=6.5,
         px=(1260, 2736), color=0xD6E2EE, back=0xC2DBF2, ring=0xB4C6D8, band=0xA9BBCC, corner=12.2, frame_roughness=0.26, back_roughness=0.38,
         back_edge=0.8, front_edge=0.6, band_y=(20.0,), band_x=(14.0,), speaker=False),
    dict(id="iphone-18-pro", exposure=1.1, name="iPhone 18 Pro", family="iphone", line="pro", finish="Burgundy", w=0.0719, hgt=0.150, t=0.00875, diag=6.3,
         px=(1206, 2622), color=0x4B1A26, back=0x451823, ring=0x5C2230, band=0x37121B, corner=11.8, frame_roughness=0.34, back_roughness=0.58, back_metal=0.25,
         back_edge=1.25, front_edge=0.7, band_y=(19.0,), band_x=(13.5,)),
    dict(id="iphone-18-pro-max", exposure=0.9, name="iPhone 18 Pro Max", family="iphone", line="pro", finish="Silver", w=0.078, hgt=0.1634, t=0.00875, diag=6.9,
         px=(1320, 2868), color=0xD8D9DB, back=0xE6E7E9, ring=0xBFC0C3, band=0xB6B7BA, corner=12.6, frame_roughness=0.32, back_roughness=0.55, back_metal=0.1, plateau_metal=0.35,
         back_edge=1.25, front_edge=0.7, band_y=(20.0,), band_x=(14.0,)),
]


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_root = os.path.abspath(args[0] if args else "Mockups")
    only = set(args[1:])
    os.makedirs(out_root, exist_ok=True)

    studio_path = os.path.join(out_root, "studio.hdr")
    build_studio(studio_path)
    keyboard_path = os.path.join(out_root, "keyboard.png")
    if not os.path.exists(keyboard_path) or "--keyboard" in only:
        render_keyboard_texture(keyboard_path)
    only.discard("--keyboard")
    lens_path = os.path.join(out_root, "lens.png")
    lens_texture(lens_path)

    index = []
    for spec in DEVICES:
        if only and spec["id"] not in only:
            index.append(dict(id=spec["id"], name=spec["name"], family=spec["family"], finish=spec["finish"]))
            continue
        index.append(build_device(spec, out_root, keyboard_path, lens_path, studio_path))
        print("BUILT", spec["id"])
    with open(os.path.join(out_root, "index.json"), "w") as f:
        json.dump(dict(version=1, devices=index), f, indent=1)


main()
