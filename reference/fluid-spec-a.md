# Fluid Functionalism → SwiftUI: spec A (base theme + 10 components)

Source: `reference/fluid-registry/src/*` (registry copy of github.com/mickadesign/fluid-functionalism, MIT) and the live site CSS `https://www.fluidfunctionalism.com/_next/static/css/23e7fde9ff622b5b.css` (fetched 2026-10-19).

Conventions used below:

- **px = pt.** SwiftUI on macOS uses points, and 1 CSS px maps to 1 pt.
- **Tailwind v4 spacing:** 1 unit = 4px. So `p-1.5` = 6px, `gap-2.5` = 10px, `h-9` = 36px, `size-7` = 28×28px, `w-80` = 320px, `rounded-lg` = 8px, `rounded-xl` = 12px, `rounded-full` = capsule.
- **Spring names** are the tokens you already have:
  - `fast` = spring 0.08s, bounce 0. Exit = 0.06s tween.
  - `moderate` = spring 0.16s, bounce 0. Exit = 0.12s.
  - `slow` = spring 0.24s, bounce 0.12. Exit = 0.16s.
- **Default CSS transition easing** (Tailwind v4 `--default-transition-timing-function`) is `cubic-bezier(.4,0,.2,1)`. Every `duration-80` color, stroke or weight transition below uses that curve over 80ms unless stated otherwise.
- **Weights** are `fontVariationSettings` on Inter Variable: normal = `'wght' 400,'opsz' 14`, semibold = `'wght' 550,'opsz' 18`, bold = `'wght' 700,'opsz' 25`. Text with no explicit weight inherits 400 with auto optical size.
- **Shape** = "rounded" throughout: item, button and input radius 8, container radius 12.
- **Icons** default to Lucide (`x`, `info`, `chevron-right`, `dot`, `arrow-right`) at stroke 1.5 unless stated.

---

## 1. Base theme colors (from the live site CSS)

The site defines every token with `light-dark(<light>, <dark>)` in one block on `.dark,.light,:root`, with `:root{color-scheme:light dark}`:

- `.light` forces `color-scheme: light` and `.dark` forces `color-scheme: dark`.
- Otherwise it follows `prefers-color-scheme`.
- Shadows `--shadow-1..8` switch between `--shadow-light-N` and `--shadow-dark-N` through the same classes or media query.

The base tokens are plain hex values, not oklch.

### 1.1 Exact values

| Token | Light | Dark | Notes |
|---|---|---|---|
| `--background` | `var(--surface-1)` = **#FAFAFA** | `var(--surface-1)` = **#171717** | page background |
| `--foreground` | **#171717** | **#F5F5F5** | "ink"; also the primary button fill |
| `--card` | `var(--surface-3)` = **#FFFFFF** | `var(--surface-3)` = **#252525** | |
| `--card-foreground` | #171717 | #F5F5F5 | |
| `--muted` | #F4F4F5 | #1E1E1E | |
| `--muted-foreground` | **#737373** | **#A3A3A3** | |
| `--accent` | **#E5E5E5** | **#525252** | neutral fill (gray badge, switch-off track) |
| `--accent-foreground` | #171717 | #F5F5F5 | |
| `--selected` | #D4D4D4 | #525252 | |
| `--border` | `color-mix(in oklab, var(--foreground) 12%, transparent)` = **rgba(23,23,23,0.12)** | = **rgba(245,245,245,0.12)** | Fallback without color-mix is `var(--foreground)` |
| `--ring` | #E5E5E5 | #404040 | defined but **unused** by any registry component |
| `--input` | #E5E5E5 | #404040 | defined but **unused** by any registry component |
| `--destructive` | **#EF4444** | **#FCA5A5** | Banner error tone |
| `--destructive-light` | #FEF2F2 | #450A0A | |
| `--info` | #3B82F6 | #93C5FD | Banner (ships with the component) |
| `--success` | #22C55E | #86EFAC | Banner |
| `--warning` | #F59E0B | #FCD34D | Banner |
| `--focus-ring` | **#6B97FF** | **#6B97FF** | same in both themes |
| `--hover` | `#0000000a` = rgba(0,0,0,0.04) | `#ffffff0f` = rgba(255,255,255,0.06) | |
| `--active` | `#00000012` = rgba(0,0,0,0.07) | `#ffffff1a` = rgba(255,255,255,0.10) | |
| `--tint` | `#00000014` = rgba(0,0,0,0.08) | `#ffffff40` = rgba(255,255,255,0.25) | secondary button |
| `--tint-hover` | `#0001` = rgba(0,0,0,0.067) | `#fff3` = rgba(255,255,255,0.20) | secondary button hover |
| `--overlay` | `0 0 0` (black, as an RGB triplet) | `255 255 255` (white) | used as `rgb(var(--overlay))` |
| `--shadow-color` | `#0000000f` = rgba(0,0,0,0.06) | (dark shadows use the `--dm-*` vars) | |
| `--checker-a` / `--checker-b` | #BBBBBB / #FFFFFF | #1F1F1F / #2A2A2A | color-picker only |

The site's Tailwind theme also maps `--color-accent: var(--accent)`, `--color-foreground`, `--color-hover` and others to these tokens. Font: `"Inter", system-ui, sans-serif`, loaded from `/fonts/InterVariable.ttf` with weight range 100–900.

### 1.2 Tokens the site does **not** define

The site CSS never defines these:

- `--primary`, `--primary-foreground`
- `--secondary`, `--secondary-foreground`
- `--popover`, `--popover-foreground`
- `--radius`
- `--chart-*`, `--sidebar-*`

Generic shadcn utility classes for them (`.bg-primary`, `.bg-popover`, `.bg-secondary`) appear in the compiled CSS, but they resolve to undefined values. I grepped every file in `fluid-registry/src`: **no registry component reads `primary`, `secondary`, `popover`, `radius`, `ring` or `input`.**

What the components use instead:

- **"Primary" means ink:** `bg-foreground text-background`.
- **"Secondary"** means `--tint` or `--accent`.
- **Popovers** are `surface-N` with `shadow-N`.
- **Radius** comes from the shape context: 8 for items and buttons, 12 for containers.

If Glide needs shadcn names, the faithful aliases are:

| Alias | Maps to |
|---|---|
| primary | foreground |
| primary-foreground | background |
| secondary | tint |
| secondary-foreground | foreground |
| popover | surface-N for that popup |
| radius | 8 |

These aliases are my suggestion, not values from the site.

### 1.3 oklch in the CSS

Only the Tailwind palette entries the site itself uses are oklch. They are not component tokens:

| Name | oklch | Approx. hex |
|---|---|---|
| emerald-500 | oklch(69.6% .17 162.48) | #00BC7D |
| blue-500 | oklch(62.3% .214 259.815) | #2B7FFF |
| violet-500 | oklch(60.6% .25 292.717) | #8E51FF |
| rose-500 | oklch(64.5% .246 16.439) | #FF2056 |
| neutral-400 | oklch(70.8% 0 0) | #A1A1A1 |
| neutral-500 | oklch(55.6% 0 0) | #737373 |
| neutral-900 | oklch(20.5% 0 0) | #171717 |

The four chromatic colors are slightly outside sRGB and were gamut-clipped.

### 1.4 Derived colors (computed; use these if you want opaque equivalents)

"over bg" means composited over `--background` (surface-1). "over s3" means over surface-3, a typical card or popover surface. Mixes use the CSS color space each class names (oklab or srgb).

| Derived value | Light | Dark |
|---|---|---|
| Primary btn hover `mix(oklab, fg 90%, bg)` | #292929 | #DCDCDC |
| Primary btn pressed `mix(oklab, fg 80%, bg)` | #3D3D3D | #C3C3C3 |
| Switch-off hover `mix(oklab, accent, overlay 10%)` | #C7C7C7 | #626262 |
| border (fg@12%) over bg / over s3 | #DFDFDF / #E3E3E3 | #323232 / #3E3E3E |
| border/60 (fg@7.2%) over bg | #EAEAEA | #272727 |
| hover over bg / s3 | #F0F0F0 / #F5F5F5 | #252525 / #323232 |
| active over bg / s3 | #E8E8E8 / #EDEDED | #2E2E2E / #3B3B3B |
| tint over bg / s3 | #E6E6E6 / #EBEBEB | #515151 / #5C5C5C |
| tint-hover over bg / s3 | #E9E9E9 / #EEEEEE | #454545 / #515151 |
| fg@15% (dots track) / fg@40% (dots fill) | #D8D8D8 / #9F9F9F | #383838 / #707070 |
| muted-fg@60% | #A9A9A9 | #6B6B6B |
| Slider (compact) fill: light `selected@50%`, dark `accent@40%` | #E7E7E7 | #2F2F2F |
| Slider hover preview `accent@40%` | #F2F2F2 | #2F2F2F |
| fg@25% / fg@50% (slider handle line) | #C1C1C1 / #888888 | #4E4E4E / #868686 |
| Banner high wash: default (fg@8%) | #E8E8E8 | #292929 |
| Banner high: info / success / warning / error (tone@12%) | #E3ECFA / #E0F4E7 / #F9EFDD / #F9E4E4 | #262C33 / #243129 / #322E1D / #322828 |

Badge solid tints: `color-mix(in srgb, <hue> 15%, var(--background))`. Each cell is light / dark.

| red | orange | amber | yellow |
|---|---|---|---|
| #F8DFDF / #371E1E | #FAE6D8 / #392517 | #F9ECD6 / #382B15 | #F8EFD6 / #372E15 |

| lime | green | emerald | teal |
|---|---|---|---|
| #E8F3D8 / #273217 | #DAF2E3 / #193122 | #D7F0E8 / #162F27 | #D7F0ED / #172F2C |

| cyan | blue | indigo | violet |
|---|---|---|---|
| #D5F0F4 / #142F33 | #DDE8F9 / #1C2738 | #E3E4F9 / #222338 | #E9E2F9 / #282138 |

| purple | fuchsia | pink | rose | gray |
|---|---|---|---|---|
| #EEE1FA / #2D2039 | #F5DFF8 / #341E37 | #F8DFEB / #371E2A | #F9DEE3 / #381D22 | `--accent`: #E5E5E5 / #525252 |

The badge mix is always against `--background` (surface-1), even when the badge sits on a raised surface.

Translucent tokens (`hover`, `active`, `tint`, `border`, banner washes) should stay translucent in SwiftUI, for example `Color.black.opacity(0.04)`. They are designed to take on whatever surface they sit on.

---

## 2. Shared mechanics these components rely on

- **Focus ring.** Interactive elements set `outline-none` and use `focus-visible:ring-1 focus-visible:ring-[color:var(--focus-ring,#6B97FF)]`.
  - This draws a 1px #6B97FF box-shadow ring hugging the outside of the element's own rounded rect. On an 8px rect the ring's outer radius is ~9px.
  - It shows only for keyboard focus (`:focus-visible`), never after a click.
  - The global fallback is `:focus-visible { outline: 1px solid var(--focus-ring); outline-offset: 2px; border-radius: var(--shape-input-radius, 8px) }`.
- **Disabled.** `opacity-50 pointer-events-none` (and `disabled:` variants of the same). Opacity 0.5, no hover, no press.
- **Optical centering.** `[text-box:trim-both_cap_alphabetic]` on labels trims the line box to cap height → baseline, so text sits optically centered in a fixed-height box. The box height is always fixed, so layout does not change.
  - SwiftUI: center the Text in a fixed frame, then nudge it by `(ascender − capHeight − |descender|)/2`. For Inter at 13px that is roughly +0.5 to +1pt.
- **Ghost-span weight animation.** An invisible copy of the label at the heaviest weight sits in the same grid cell, so animating 400→550 never changes width. The opsz pairing keeps the advance width within ±0.4px anyway.
- **Color transitions.** `transition-colors duration-80` = 80ms `cubic-bezier(.4,0,.2,1)` on color, background-color, border-color, fill and stroke.
- **Shape switch.** The `html.transitioning` cross-fade is 180ms ease-in-out on radius and colors. It only matters if you implement live pill⇄rounded switching.

---

## 3. Button (`button__button.tsx`; `base_button__button.tsx`)

### 3.1 Variants and sizes

- **variant:** `primary` (default) | `secondary` | `tertiary` | `ghost`.
- **size:** `default` | `compact` | `icon` | `icon-compact`.
  - Legacy aliases: `sm`→compact, `md`/`lg`→default, `icon-sm`→icon-compact, `icon-lg`→icon.
  - With no `size`, the button follows the surrounding SizeProvider (compact provider → compact, otherwise default).
- **Props:** `loading`, `leadingIcon`, `trailingIcon`, `active` (forces the pressed look, e.g. while its menu is open), `disabled`, `asChild` / `render` (render as a link).

### 3.2 Dimensions

| Size | Height | Horizontal padding | Gap | Text | Icon |
|---|---|---|---|---|---|
| default | 36 (`h-9`) | 16 (`px-4`); 12 (`pl-3`/`pr-3`) on the side with an icon | 6 (`gap-1.5`) | body 13/20 | 16 |
| compact | 28 (`h-7`) | 12 (`px-3`); 8 (`pl-2`/`pr-2`) on the icon side | 4 (`gap-1`) | body-compact 12/18 | 14 |
| icon | 36×36 (`h-9 w-9 p-0`) | 0 | — | — | 16 (`[&_svg]:h-4 [&_svg]:w-4`) |
| icon-compact | 28×28 | 0 | — | — | 14 |

Rule: an icon sits 4px closer to its edge than text does.

- Radius: 8 (`shape.button` = `rounded-lg`).
- The label never wraps (`whitespace-nowrap`).
- Width hugs content.

### 3.3 Layer structure (the press effect)

```
root  : "group relative isolate inline-flex items-center justify-center outline-none cursor-pointer select-none whitespace-nowrap transition-colors duration-80 disabled:opacity-50 disabled:pointer-events-none focus-visible:ring-1 focus-visible:ring-[color:var(--focus-ring,#6B97FF)]"
bg    : "absolute inset-px rounded-[inherit] transition-[box-shadow,background-color] [transition-duration:180ms,80ms] [transition-timing-function:cubic-bezier(0.23,1,0.32,1),ease] group-active:[transition-duration:80ms,80ms]"
label : "relative inline-flex items-center justify-center gap-[inherit]" > span "[text-box:trim-both_cap_alphabetic]"
```

The surface layer is inset **1px** on every side (`inset-px`, radius 8). A same-color `box-shadow: 0 0 0 1px` spread fills it back out to the full bounds, so the visible outer corner radius is ~9px.

On press, the spread animates 1px → 0px, so the surface shrinks by **exactly 1px per side** at any width. There is no scale transform, so wide buttons do not warp.

Timing:

| What | Into pressed | On release | Curve |
|---|---|---|---|
| Geometry (box-shadow) | 80ms | 180ms | `cubic-bezier(0.23,1,0.32,1)` both ways |
| Background color | 80ms | 80ms | `ease` |
| Text color (root) | 80ms | 80ms | default curve |

### 3.4 Colors per state

`bgVariants` (normal) and `activeBgVariants` (when the `active` prop is set):

| Variant | Text | Rest | Hover | Pressed | `active` prop |
|---|---|---|---|---|---|
| primary | `background` (#FAFAFA / #171717) | fill `foreground` + 1px spread of the same | fill `mix(oklab, fg 90%, bg)` (#292929 / #DCDCDC) | fill `mix(fg 80%, bg)` (#3D3D3D / #C3C3C3), spread → 0 | 80% fill at full size; press still collapses |
| secondary | `foreground` | fill `--tint` + 1px spread | fill `--tint-hover` (lighter: 0.065 vs 0.08 alpha in light; 0.20 vs 0.25 in dark) | fill back to `--tint`, spread → 0 | `--tint` at full size |
| tertiary | `foreground` | transparent fill; ring `0 0 0 1px var(--border)` outside the inset surface, so it occupies the outer 1px of the bounds | fill `bg-hover` (inside the ring) | fill `bg-active`; outer ring → 0 and `inset 0 0 0 1px var(--border)` → 1px, so the ring moves inward with the surface | `bg-active`, ring outside |
| ghost | `muted-foreground` → `foreground` on hover | transparent, `0 0 0 1px transparent` | fill `bg-hover` + 1px `--hover` spread (full bounds) | fill `bg-active`, spread 0 (shrinks 1px) | `bg-active` + 1px `--active` spread |

Class strings:

```
primary  : "[--btn-bg:var(--foreground)] group-hover:[--btn-bg:color-mix(in_oklab,var(--foreground)_90%,var(--background))] group-active:[--btn-bg:color-mix(in_oklab,var(--foreground)_80%,var(--background))] bg-[var(--btn-bg)] shadow-[0_0_0_1px_var(--btn-bg)] group-active:shadow-[0_0_0_0px_var(--btn-bg)]"
secondary: "[--btn-bg:var(--tint)] group-hover:[--btn-bg:var(--tint-hover)] group-active:[--btn-bg:var(--tint)] ... shadow-[0_0_0_1px_var(--btn-bg)] group-active:shadow-[0_0_0_0px_var(--btn-bg)]"
tertiary : "bg-transparent shadow-[0_0_0_1px_var(--border),inset_0_0_0_0px_var(--border)] group-hover:bg-hover group-active:bg-active group-active:shadow-[0_0_0_0px_var(--border),inset_0_0_0_1px_var(--border)]"
ghost    : "bg-transparent shadow-[0_0_0_1px_transparent] group-hover:bg-hover group-hover:shadow-[0_0_0_1px_var(--hover)] group-active:bg-active group-active:shadow-[0_0_0_0px_var(--active)]"
variant text: primary "text-background", secondary/tertiary "text-foreground", ghost "text-muted-foreground hover:text-foreground"
```

Other states:

- **Focused:** 1px #6B97FF ring on the root (radius 8, outside the bounds).
- **Disabled or loading:** opacity 0.5, no pointer events. `disabled={disabled || loading}`.

### 3.5 Typography

- Body role: 13/20 at default, 12/18 at compact.
- Weight inherits normal (400). No weight change on any state.

### 3.6 Icons

- Leading and trailing icons are 16 (default) or 14 (compact).
- Stroke is 1.5 at rest and **2 on hover**: `transition-[stroke-width] duration-80 group-hover:stroke-[2]`.
- Icon-only buttons apply the same rule to the child svg: `[&_svg]:stroke-[1.5] ... group-hover:[&_svg]:stroke-[2]`.

### 3.7 Loading

- The label and icons stay in the layout at `opacity-0`, so the width is preserved.
- A spinner is centered over them: a square box the height of the button (36×36 or 28×28), drawing an infinity-sign path in a 24×24 viewBox.
  - Path: `M 12 12 C 14 8.5 19 8.5 19 12 C 19 15.5 14 15.5 12 12 C 10 8.5 5 8.5 5 12 C 5 15.5 10 15.5 12 12 Z`.
  - Stroke `currentColor`, width 1.125 viewBox units (≈1.69px at 36, ≈1.31px at 28), round caps.
  - `pathLength=100`.
- Two concurrent CSS animations:
  - `spinner-move 2s linear infinite`: `stroke-dashoffset` 0 → −100.
  - `spinner-dash 4s ease-in-out infinite`: `stroke-dasharray` 15 85 (0%, 100%) → 40 60 (50%).
- Net effect: a dash 15% → 40% → 15% of the loop long, chasing around the ∞.

### 3.8 Accessibility

- Native `<button>`; Space and Enter activate it.
- With `asChild` (a link), the `disabled` attribute is dropped.
- **Base UI vs Radix:** `base_button` renders through `@base-ui/react/button`, and `asChild`/`render` clones the element directly (so a link does not get role="button"). Visuals, classes and behavior are otherwise **identical** to `button__button.tsx`.

### 3.9 SwiftUI translation notes

Implement a `ButtonStyle`:

- **Surface:** `ZStack { RoundedRectangle(cornerRadius: pressed ? 8 : 9).fill(fill).padding(pressed ? 1 : 0) ; label }`.
  - Animate the geometry with `.animation(isPressed ? .timingCurve(0.23,1,0.32,1,duration:0.08) : .timingCurve(0.23,1,0.32,1,duration:0.18), value: isPressed)`.
  - Animate the fill color separately with `.easeInOut(duration:0.08)`.
- **Tertiary:** use `.strokeBorder(border, lineWidth:1)` on the shrinking rect, which reproduces the outer→inset ring hand-off.
- **Hover:** `.onHover`.
- **Focus ring:** `.focusable()` + `@FocusState`, then `.focusEffectDisabled()` and an overlay `RoundedRectangle(cornerRadius: 9).stroke(Color(hex:0x6B97FF), lineWidth: 1).padding(-1)` shown only for keyboard focus. In AppKit-hosted SwiftUI, check `NSApp.currentEvent?.type == .keyDown`, or track whether the last interaction was a keyboard event.
- **Icon stroke 1.5→2:** use Lucide icons as SwiftUI `Shape`s and animate `lineWidth`. With SF Symbols, approximate by switching `.fontWeight(.regular)` → `.semibold`.
- **Spinner:** an `InfinityShape` path with `.trim(from: phase, to: phase + dash)`. Drive it from a `TimelineView(.animation)`: `phase = t/2 mod 1` (linear) and `dash = 0.15 + 0.25·easeInOut(triangle(t/4))`. Handle wrap-around by drawing two trims.
- **Loading:** keep the label rendered with `.opacity(0)`.

---

## 4. Badge (`badge__badge.tsx`)

### 4.1 Variants and sizes

- **variant:** `solid` (default) | `dot`.
- **size:** `default` | `compact` (legacy `sm`→compact, `md`/`lg`→default). Follows the SizeProvider when omitted.
- **color:** gray (default), red, orange, amber, yellow, lime, green, emerald, teal, cyan, blue, indigo, violet, purple, fuchsia, pink, rose.
  - Hex values are the Tailwind 500 step (gray uses #A3A3A3): red #EF4444, orange #F97316, amber #F59E0B, yellow #EAB308, lime #84CC16, green #22C55E, emerald #10B981, teal #14B8A6, cyan #06B6D4, blue #3B82F6, indigo #6366F1, violet #8B5CF6, purple #A855F7, fuchsia #D946EF, pink #EC4899, rose #F43F5E.

### 4.2 Dimensions and typography

```
base   : "inline-flex items-center whitespace-nowrap"  + shape.item (rounded-lg = 8px)
default: "h-6 px-2.5 text-[length:var(--fs-caption,12px)] leading-[var(--lh-caption,16px)] gap-1.5"
compact: "h-5 px-2 text-[length:var(--fs-caption-compact,11px)] leading-[var(--lh-caption-compact,14px)] gap-1"
dot    : "border border-border text-foreground"
```

| Size | Height | Padding | Gap | Text | Dot |
|---|---|---|---|---|---|
| default | 24 | 10 | 6 | caption 12/16 | 7×7 |
| compact | 20 | 8 | 4 | caption-compact 11/14 | 6×6 |

- Radius 8.
- Weight inherits 400.
- The label is cap-trimmed (`[text-box:trim-both_cap_alphabetic]`) inside the fixed height.

### 4.3 Colors

| Variant | Background | Text | Border | Dot |
|---|---|---|---|---|
| solid, gray | `--accent` (#E5E5E5 / #525252) | `foreground` | none | — |
| solid, hue | `color-mix(in srgb, <hex> 15%, var(--background))` (see table §1.4) | `foreground` (never the hue) | none | — |
| dot | none (transparent) | `foreground` | 1px `--border` | full-strength hex; gray dot = `--muted-foreground` |

### 4.4 Behavior

- No states, no animation.
- A plain `<span>`, not focusable.

### 4.5 SwiftUI translation notes

- `HStack(spacing: 6/4) { if dot { Circle().fill(dotColor).frame(width:7,height:7) }; Text(label).font(caption) }`
- Then `.padding(.horizontal, 10/8)`, `.frame(height: 24/20)`, and `.background(RoundedRectangle(cornerRadius: 8).fill(tint))`. For the dot variant use `.overlay(RoundedRectangle(cornerRadius:8).strokeBorder(border, lineWidth:1))`.
- Compute the tint as an sRGB linear interpolation of hue and surface-1: `bg + 0.15·(hue − bg)` per channel in gamma space.
- Use `.lineLimit(1).fixedSize()`.

---

## 5. Banner (`banner__banner.tsx`, `banner__theme.json`)

### 5.1 Parts and props

- **Parts:** `Banner` (owns status color, icon, dismiss), `BannerTitle`, `BannerDescription`, `BannerActions`, `BannerAction`.
- **status:** `default` | `info` | `success` | `warning` | `error`.
- **contrast:** `low` (default) | `high`.
- **variant:** `inline` (default) | `fixed`.
- **Other props:**
  - `icon`: overrides the glyph.
  - `dismissible`, `onDismiss`, `dismissLabel` ("Dismiss").
  - `open`: controlled. When uncontrolled, the banner hides itself on dismiss.
  - `size`: default | compact.
  - `motion`: config override.

### 5.2 Color logic

The tone is `--banner-tone`:

| Status | Tone |
|---|---|
| default | foreground |
| info | `--info` |
| success | `--success` |
| warning | `--warning` |
| error | `--destructive` |

The fill (`--banner-fill`) is painted as `background-image: linear-gradient(fill, fill)`:

| Contrast | Fill | Opaque equivalent |
|---|---|---|
| low | `var(--hover)` (neutral 4% / 6% overlay) | — |
| high, colored status | `color-mix(in oklab, tone 12%, transparent)` = tone @ 12% alpha | §1.4 |
| high, default status | tone @ 8% alpha | §1.4 |

Rules:

- **Text is always `foreground`.** The description is also foreground (not muted), for contrast on the fills.
- **The icon takes the tone color.**
- **`fixed` variant:** opaque `background-color: var(--background)` with the translucent fill layered on top.
- **`inline` variant:** fully translucent, so it blends with the surface below.

### 5.3 Layout and dimensions

```
root: "group/banner @container/banner relative grid w-full grid-cols-[auto_minmax(0,1fr)_auto_auto] items-center text-foreground has-data-[slot=banner-description]:items-start"
      + (compact ? "p-3" : "p-4") + (!fixed && shape.container /* rounded-xl 12px */)
```

| Element | Default | Compact |
|---|---|---|
| Padding (all sides) | 16 | 12 |
| Radius (inline only; fixed is square, edge to edge, no border) | 12 | 12 |
| Icon box (col 1): height (one title line), right margin | 20 (`h-5`), 12 (`mr-3`) | 18 (`h-[18px]`), 10 (`mr-2.5`) |
| Icon size | 20 | 16 |
| Title (col 2, row 1): `subtitle` role, **semibold 550**, foreground | 14/20 | 13/18 |
| Description (col 2, row 2): `subtitle` role, normal weight, foreground, `mt-0.5` = 2 | 14/20 | 13/18 |
| Actions (col 3, row 1): gap / vertical bleed / left margin | `gap-2` 8 / `-my-1` −4 / `ml-3` 12 | 8 / `-my-[5px]` −5 / `ml-2.5` 10 |
| Actions under the text (description present OR container narrower than 24rem = 384px): position, top margin | col 2, row 3, `ml-0 my-0`, `mt-2` 8 | `mt-1.5` 6 |
| Dismiss ✕ (col 4, row 1): size, X icon size | 28×28 (`size-7`), 15 | 28×28, 13 |
| Dismiss ✕ margins | `-my-1 -mr-1.5 ml-2` (−4 / −6 / +8) | `-my-[5px] -mr-1.5 ml-1.5` (−5 / −6 / +6) |
| Minimum height (title only) | 52 | 42 |

Dismiss ✕ details: `text-muted-foreground`, hover `bg-hover text-foreground`, 80ms, radius 8, X stroke 1.5. The negative margins pull it into the padding so the glyph sits on the title line and the inset edge.

- With a description, the grid uses `items-start`, so the icon and ✕ align to the title line instead of the block center.
- **Narrow layout:** `@container banner not (min-width:24rem)`.

### 5.4 Status glyphs

Status glyphs are custom filled SVGs in a 24 viewBox, colored with the tone:

- **info, success, error:** `<circle cx=12 cy=12 r=10.5 fill=currentColor>`.
- **warning:** triangle `m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z`, filled and stroked 1.5 with round joins.
- **The mark** is cut out in `--background`, stroke 2.25 viewBox units, round caps and joins:
  - success ✓ `m8.5 12.25 2.5 2.5 4.5-5`
  - info `M12 16.5v-5M12 7.5h.01`
  - error `M12 7.5v5M12 16.5h.01`
  - warning `M12 9.5v3.5M12 17h.01`
- **default status:** the icon set's outline `info` at stroke 1.5, foreground color. A custom `icon` prop also renders as an outline at 1.5.

### 5.5 BannerAction

- It is the library Button at **compact** size (28px). Variant `secondary` by default; `primary` and `ghost` are also available.
- **Ghost** gets `text-foreground` instead of muted. (The code comment says 70%, but the code uses full foreground.)
- **Secondary's** translucent `--tint` darkens (light mode) or lightens (dark mode) the banner fill beneath it.
- **Order is by variant, not markup:**
  - Trailing the title: ghost(1), secondary(2), primary(3), so the strongest action sits at the edge.
  - Under the text: primary(1), secondary(2), ghost(3).
  - Tab order follows the markup.
- `href` renders a link.

### 5.6 Motion

`bannerMotion` defaults:

- **Appear:**
  - Row: `spring 0.32s bounce 0` (2× moderate).
  - Banner: `spring 0.24s bounce 0.12` (the slow tier), **delay 0.08s** (one fast tier).
  - Starting scale: `fromScale 0.4`.
- **Dismiss:**
  - Row: tween **0.24s easeInOut** (2× the moderate exit).
  - `shrinkTo 0.6`.

Structure:

- An outer `display:grid` wrapper animates `grid-template-rows: <row>fr`, from 0fr to 1fr. This is a height animation that needs no measurement.
- In a flex column with a `gap`, the wrapper also animates `margin-bottom = (row − 1) × gap`, so siblings never jump by the gap.

**Inline appear:**

1. The row opens 0 → 1 over 0.32s.
2. After 0.08s, the banner fades 0 → 1 and scales 0.4 → 1 (`transformOrigin: top`) on the slow spring.
3. The bounce may overshoot 1.0. The row has `overflow: visible` during appear, so the overshoot is not clipped.

**Inline dismiss:**

1. The row closes 1 → 0 over 0.24s easeInOut with `overflow: hidden`.
2. The banner rides it:
   - `opacity = shownFrom × clamp((row − 0.6)/(rowFrom − 0.6), 0, 1)`
   - `scale = min(scaleFrom, max(row, 0.6))` from the top edge
3. So the banner is fully gone when the row is 60% open, and its visible height always equals the row's height. The last 60% of the collapse happens empty.

**Fixed variant:**

- The bar is `sticky top-0 z-40`.
- It slides with its row: `y = (row − 1) × 100%`, with opacity = row on appear and opacity following the row linearly to 0 on dismiss.
- No scaling.

**Other rules:**

- `pointer-events: none` while opacity ≤ 0.5.
- A dismiss in the middle of the appear starts from the current values, with no jump.
- A banner that is open on first render appears with no animation (`AnimatePresence initial={false}`).
- **Reduced motion:** the row snaps (duration 0). The banner fades in on `spring.fast` and fades out with a 0.06s tween, then unmounts (the row disappears instantly).

### 5.7 Accessibility

- `role="alert"` for error and warning; `role="status"` for the others.
- If focus is inside the banner when it closes, focus moves to the next focusable element after it (or the last one before it), with `preventScroll`.
- The ✕ has `aria-label = dismissLabel`.

### 5.8 SwiftUI translation notes

- **Layout:** `HStack(alignment: hasDescription ? .top : .center)` with `[icon box][VStack title/description/actions][actions trailing][✕]`. Use `ViewThatFits`, or a width read, to move the actions under the text when a description exists or the width is under 384.
- **Height animation:** wrap the banner in a container with `.frame(height: measured × row, alignment: .top)` and clip only during the dismiss. Measure with `onGeometryChange`.
- **Content:** apply `.scaleEffect(scale, anchor: .top).opacity(shown)`.
- **Driving the dismiss:** one `@State var row: CGFloat` animated `withAnimation(.easeInOut(duration: 0.24))`, with shown and scale derived from row.
  - The cleanest option is a custom `Animatable` modifier whose `animatableData` is `row` and which computes opacity, scale and height each frame.
- **Appear:** run two animations: `.spring(duration:0.32,bounce:0)` on row, and `.spring(duration:0.24,bounce:0.12).delay(0.08)` on shown and scale.
- **Glyphs:** draw them as `Shape`s and render the mark with `.blendMode(.destinationOut)` inside `.compositingGroup()`, or stroke the mark in the background color.
- **Accessibility:** post `NSAccessibility` announcements for alert or status. Use `.accessibilityAddTraits(.updatesFrequently)` sparingly.

---

## 6. Card (`card__card.tsx`)

### 6.1 Parts

- `CardGroup` (layout and fluid hover)
- `Card`
- `CardHeader`, `CardTitle`, `CardDescription`, `CardAction`, `CardContent`, `CardFooter`
- Additions: `CardMedia`, `CardImage`, `CardFeature`, `CardButton`, `CardEyebrow` (deprecated)

Default surface: **transparent and borderless.** Cards inherit their parent's surface and rely on hairline dividers and the fluid-hover highlight instead of a drawn frame.

### 6.2 CardGroup

**Props:**

- `orientation`: `card` (stacked, default) | `inline` (horizontal row).
- `columns` (default 1). Above 1, the group is a grid and fluid hover runs on both axes.
- `border`: `none` | `outlined`.
- `separated` (gap between tiles, default false).
- `fluidHover` (default true).

```
"relative grid" + (outlined && !separated && "border border-border/60 overflow-hidden rounded-xl") + (separated ? "gap-2" : "gap-0")
gridTemplateColumns: repeat(columns, minmax(0,1fr))
```

- **Outlined shared frame:** 1px border at fg@7.2% (`border/60`), radius 12, clipped.
- **Separated:** gap 8.
- **Fluid hover highlight:** `bg-hover`, radius **12** (`shape.container`), `z-0`.
  - Position moves on `spring.fast`; opacity fades in over 0.08s and out over 0.06s.
  - It follows the nearest card on both axes when columns > 1.
  - It jumps onto **only clickable cards** (those with `href` or `onClick`).
  - A click in a gap is routed to the highlighted card only within 16px (`gapClick.maxDistance: 16`).

### 6.3 Card root

```
"group/card relative z-10 min-w-0 min-h-[60px]"
stacked : "flex flex-col" + (compact ? "pb-3" : "pb-4")
inline  : "flex flex-row items-center" + (compact ? "gap-2.5 pl-3" : "gap-3 pl-4")
standalone clickable: "transition-colors duration-80 hover:bg-hover"
standalone tile: "rounded-xl overflow-hidden"; separated+outlined tile: "rounded-xl overflow-hidden border border-border/60"
disabled: "opacity-50 pointer-events-none" (+ aria-disabled)
```

- Minimum height 60.
- Stacked bottom padding: 16 (12 compact).
- Inline: gap 12 and left padding 16 (10 and 12 compact).

### 6.4 Parts: padding and type

| Part | Default | Compact | Notes |
|---|---|---|---|
| CardHeader (stacked) | `px-4 pt-4` (16/16) | `px-3 pt-3` | `grid auto-rows-min items-start gap-1` (4); with a CardAction it becomes `grid-cols-[1fr_auto]` |
| CardHeader (inline) | `min-w-0 flex-1 py-3.5` (14) | `py-2.5` (10) | |
| CardTitle | subtitle 14/20 | 13/18 | foreground; weight normal → **semibold when `selected`**, 80ms; ghost semibold copy reserves width; inline rows are cap-trimmed; supports `truncate` |
| CardDescription | subtitle 14/20 | 13/18 | `text-muted-foreground` |
| CardAction | — | — | `relative z-30 col-start-2 row-span-2 row-start-1 self-start justify-self-end` |
| CardContent (stacked) | `px-4 pt-3` (16/12) | `px-3 pt-2.5` (12/10) | inline: no padding |
| CardFooter (stacked) | `px-4 pt-3`, `flex-wrap` | `px-3 pt-2.5` | always `relative z-30 flex items-center gap-1` (4) |
| CardFooter (inline) | `shrink-0 ml-auto pr-4` | `pr-3` | trailing |
| CardMedia icon tile | 32×32 (`size-8`), `bg-hover`, radius 8, icon 18 | icon 16 | icon muted-foreground stroke 1.5; stacked adds `mb-2` (8), so the gap under it reads 12 |
| CardMedia logo | 22×22 (prop `size`), radius 8, inset 1px outline black/10 (white/10 dark) | same | a pair shows a connector `w-2 h-px bg-border` (8×1) between, `gap-1.5` |
| CardImage stacked | `w-full aspect-[16/9]` | | radius **2px**, `outline-1 -outline-offset-1 outline-black/10 dark:outline-white/10` |
| CardImage inline | 160×160 (`size-40`), flush left | | text column: `flex-1 flex-col justify-center gap-2 py-3.5 pr-4` (compact `py-2.5 pr-3`) |
| CardFeature | icon 16/14 muted, `mt-0.5`; `gap-2`/`gap-1` | | title body semibold foreground (cap-trimmed); description caption muted; column `gap-0.5` |

### 6.5 States and colors

**Hover:**

- Inside a group: the shared fluid highlight (`bg-hover`, radius 12).
- Standalone clickable card: `hover:bg-hover`, 80ms.
- **The title does not bold on hover.** Only `selected` bolds it.

**Selected:**

- An absolute `inset-0 -z-10 bg-active rounded-xl` fill.
- The title goes semibold.
- The stretched button gets `aria-pressed`.

**Dividers** (borderless groups, not separated):

- A 1px `bg-border/60` hairline at the bottom (toward the card below) and the right (toward the neighbor).
- Hairlines touching the **hovered or selected** card are **removed** (conditionally rendered, so the change is instant, not animated).
- Where hairlines cross, the vertical one stops 1px short (`bottom-px`).

```
bottom: "absolute inset-x-0 bottom-0 h-px bg-border/60 pointer-events-none -z-10"
right : "absolute top-0 right-0 w-px bg-border/60 pointer-events-none -z-10" + (showBottom ? "bottom-px" : "bottom-0")
```

**Disabled:** opacity 0.5. The stretched overlay is removed, so the card cannot be tabbed to.

**Focus:** the stretched overlay `<button>` or `<a>` (`absolute inset-0 z-20 rounded-[inherit]`) shows the 1px focus ring on the card's rounded rect.

### 6.6 Dismiss ✕

```
"absolute right-2 top-2 z-30 flex h-7 w-7 items-center justify-center text-muted-foreground hover:text-foreground cursor-pointer outline-none transition-colors duration-80 focus-visible:ring-1 ... rounded-lg"
over image: "bg-card/70 backdrop-blur-sm hover:bg-card"   else: "hover:bg-hover"
dismissOnHover (default true): "pointer-events-none opacity-0 transition-opacity duration-80 group-hover/card:pointer-events-auto group-hover/card:opacity-100 group-focus-within/card:... focus-visible:opacity-100"
```

- 28×28, 8px from the top-right corner.
- X icon 15 (13 compact), stroke 1.5.
- Over an image it uses a frosted chip: surface-3 at 70% with an 8px backdrop blur.
- It fades in over 80ms on card hover or focus-within.
- In inline cards the header gains `pr-10` (40) only while the ✕ is revealed. This change is instant.

### 6.7 CardButton (self-contained footer button)

```
"group/action relative z-30 inline-flex items-center justify-center gap-1.5 h-7 px-2.5 cursor-pointer outline-none" + caption type + "transition-colors duration-80 focus-visible:ring-1 ... disabled:opacity-50 disabled:pointer-events-none rounded-lg"
primary  : "bg-foreground text-background hover:bg-foreground/90 active:bg-foreground/80"
secondary: "bg-accent text-foreground hover:bg-accent/80 active:bg-accent"
ghost    : "text-muted-foreground hover:text-foreground hover:bg-hover active:bg-active"   (default)
link     : "text-foreground underline-offset-4 hover:underline !px-0 !h-auto"
```

- 28 tall, 10 horizontal padding, gap 6.
- Caption type: 12/16 (11/14 compact), weight 400.
- `/90` and `/80` are **alpha** mixes with transparent, not mixes with the background.
- Icon 14 (12 compact), stroke 1.5 → 2 on hover.
- The external arrow is 13, rotated −45°.

### 6.8 Accessibility

- Clickable cards use a stretched overlay button or link with `aria-label={label}`.
- Inner actions (z-30) stay separately focusable and clickable.

### 6.9 SwiftUI translation notes

- **Group:** a `LazyVGrid` or `VStack` inside a `ZStack`. Draw one highlight `RoundedRectangle(cornerRadius:12).fill(hover)` whose frame comes from the hovered card's anchor (`anchorPreference(key:value:.bounds)`).
  - Animate its frame with `.spring(duration:0.08,bounce:0)` and its opacity with `.linear(0.08)`.
  - Use `.onContinuousHover` on the container and compute the nearest card rect, which reproduces "nearest item".
- **Dividers:** overlays drawn per card. Hide them when `hoveredIndex` is this card or the next one.
- **Selected fill:** `RoundedRectangle(cornerRadius:12).fill(active)` behind the content.
- **Title weight:** `Text` with a weight-animatable Inter modifier, plus a hidden semibold copy in a `ZStack` to fix the width.
- **Whole-card click:** the card is a `Button` with `.buttonStyle(.plain)`, and footer buttons sit above it. SwiftUI hit-testing gives the inner Buttons priority.
- **Dismiss:** `.opacity(hovering || focused ? 1 : 0)` + `.allowsHitTesting(...)`, with `.animation(.easeInOut(duration:0.08))`. Over images use `.background(.ultraThinMaterial)` (or surface-3 at 0.7 plus blur).

---

## 7. Tooltip (`tooltip__tooltip.tsx`; `base_tooltip__tooltip.tsx`)

### 7.1 Props

- `content`
- `side`: `top` (default) | `right` | `bottom` | `left`
- `sideOffset` (default **8**)
- `delayDuration` (default **200ms**)
- `forceOpen`
- `followCursor`: `"x"` | `"y"` (tracks the pointer along one axis; the other stays anchored)
- `className`, `contentClassName` (z-index, default `z-50`)

`TooltipProvider` groups tooltips: `delayDuration` 200ms, `skipDelayDuration` 300ms. Once one tooltip has closed, moving to an adjacent trigger within 300ms opens it instantly.

### 7.2 Visual

```
"bg-foreground text-background text-[length:var(--fs-caption,12px)] leading-[var(--lh-caption,16px)] px-2 py-1 [text-box:trim-both_cap_alphabetic] supports-[text-box:trim-both]:py-2" + shape.bg (rounded-lg = 8px)
style: fontVariationSettings normal (400)
```

- **Colors:** light = #171717 background, #FAFAFA text. Dark = #F5F5F5 background, #171717 text.
- **Size:** caption 12/16. Padding 8 horizontal × 4 vertical (8 vertical when text-trim is supported), about 24px tall in both cases.
- No border, shadow or arrow.
- No max-width set.

### 7.3 Motion

- **Enter:**
  - From `opacity 0` plus a 4px offset toward the trigger: top `y:+4`, bottom `y:−4`, left `x:+4`, right `x:−4`.
  - To `opacity 1, x 0, y 0` on `spring.fast` (0.08s, bounce 0).
  - The tooltip drifts 4px away from the trigger as it fades in.
- **Exit (Radix version, `tooltip__tooltip.tsx`):** opacity → 0 with a 0.06s tween. Position stays at 0, with no slide.
- **Exit (Base UI version, `base_tooltip__tooltip.tsx`):** opacity → 0 **and** slides back to the 4px offset, 0.06s tween. This is the only visual difference between the two files.
- **Unmount:** the tooltip stays mounted until the exit finishes. A fallback timer unmounts it after 160ms.
- **Reduced motion:** no special handling in the component.

### 7.4 Accessibility

- Opens on hover after the delay, and on keyboard focus.
- Closes on pointer leave, blur or Escape.
- The trigger gets `aria-describedby` (Radix or Base UI wiring).

### 7.5 SwiftUI translation notes

- `.help()` cannot be styled. Build a custom overlay instead: a borderless, non-activating `NSPanel` child window (so it can escape clipping), or an `.overlay` anchored above the trigger with `.offset(y: −(height + 8))`.
- **Content:** `Text(content).font(caption).padding(.horizontal,8).padding(.vertical,4).background(RoundedRectangle(cornerRadius:8).fill(foreground)).foregroundStyle(background)`.
- **Hover delay:** a shared `@Observable TooltipCenter` stores `lastClosedAt`. On hover, wait 200ms (`Task.sleep`), or 0ms if `now − lastClosedAt < 300ms`.
- **Animation:** `.transition(.asymmetric(insertion: .opacity.combined(with:.offset(y:4)).animation(.spring(duration:0.08,bounce:0)), removal: .opacity.animation(.easeOut(duration:0.06))))`.
- **followCursor:** use `.onContinuousHover` to set the x (or y) offset.

---

## 8. Switch (`switch__switch.tsx`; `base_switch__switch.tsx`)

### 8.1 Model

- The whole labeled **row** is the control: a click anywhere on it, label included, toggles.
- The thumb can be dragged.
- Props: `label` (required), `checked` (always controlled by the parent), `onToggle()`, `disabled`, `thumbTransition` (default `spring.moderate`), `size` (default | compact).

### 8.2 Geometry (`METRICS`)

| | default | compact |
|---|---|---|
| Track W×H (capsule) | **34×20** | **28×16** |
| Thumb (circle) | 16 | 12 |
| Inset (thumb to track edge) | 2 | 2 |
| Travel (off x → on x) | 2 → 16 (14px) | 2 → 14 (12px) |
| Hover: thumb width | +2 → 18 | +2 → 14 |
| Press: thumb width / height | +4 → 20 / −4 → 12 | +3 → 15 / −3 → 9 |
| Press: thumb y | 2 + 2 = 4 (squashes toward its own center line) | 2 + 1.5 = 3.5 |
| Row | `gap-2 px-3 py-2` (8/12/8): 36 tall | `gap-1 px-2.5 py-1` (4/10/4): 24 tall |

When checked, the extra hover or press width grows **leftward** (x = 2 + travel − extraWidth), so the outer edge stays 2px from the track end.

```
row   : "relative z-10 flex items-center cursor-pointer select-none touch-none" + gap + px + (compact ? "py-1" : "py-2") + (disabled && "opacity-50 pointer-events-none")
track : "relative shrink-0 rounded-full outline-none cursor-pointer transition-colors duration-80 focus-visible:ring-1 focus-visible:ring-[color:var(--focus-ring,#6B97FF)] focus-visible:ring-offset-2 focus-visible:ring-offset-background"
thumb : "absolute top-0 left-0 block rounded-full bg-white shadow-sm"
label : "[text-box:trim-both_cap_alphabetic] transition-[color] duration-80" + body type + (checked ? "text-foreground" : "text-muted-foreground")
```

### 8.3 Colors

| State | Track |
|---|---|
| Off, rest | `--accent` (#E5E5E5 / #525252) |
| Off, hover | `color-mix(in oklab, var(--accent), rgb(var(--overlay)) 10%)` = #C7C7C7 / #626262 |
| On, rest | **#6B97FF** (hard-coded, both themes) |
| On, hover | **#5C89F2** |

- Color changes cross-fade over 80ms.
- **Thumb:** always white, with `shadow-sm` = `0 1px 3px 0 rgba(0,0,0,.1), 0 1px 2px -1px rgba(0,0,0,.1)`.
- **Label:** body 13/20 (12/18 compact), weight 400. `muted-foreground` when off, `foreground` when on, 80ms.
- **Focus (keyboard only):** a 2px gap filled with `--background`, then a 1px #6B97FF ring around the capsule, 3px out in total.
- **Disabled:** the whole row at opacity 0.5.

### 8.4 Motion and interaction

- **Thumb animation:** x is a motion value animated with `spring.moderate`. y, width and height use the same spring.
- **First render:** no animation; the thumb starts at its resting spot.
- **Hover** (mouse only, `pointerType === "mouse"`): the thumb stretches into an 18px pill. Touch never sees the hover shape.
- **Press:** on pointer down, the thumb goes wider and shorter (20×12) and squashes toward its center line. Press wins over hover.
- **Drag:**
  1. Pointer capture is on the row.
  2. 2px dead zone (`DRAG_DEAD_ZONE`). Below it the gesture is a click.
  3. Past it, the thumb follows the pointer 1:1 from wherever it was (even in the middle of a spring).
  4. Clamp to `[2, trackW − 2 − pressedThumbW]` = [2, 12] default, [2, 11] compact.
- **Release after a drag:** if x is past the midpoint of that range (7 default, 6.5 compact), the switch should be on.
  - Side changed → `onToggle()`, and the thumb springs to the new spot from where it was released.
  - Same side → the thumb springs home.
  - The click event from the same release is swallowed for one frame (`didDrag`).
- **pointercancel:** the thumb springs back without toggling.

### 8.5 Accessibility

- A Radix `Switch.Root` (button role="switch") with `aria-labelledby` pointing to the label, `tabIndex 0`.
- Space and Enter toggle.
- **Base UI version:** same visuals and behavior; only the thumb wiring differs (render prop instead of asChild).

### 8.6 SwiftUI translation notes

- **Structure:** `HStack(spacing: 8) { track; Text(label) }.padding(.horizontal,12).padding(.vertical,8).contentShape(Rectangle())`.
- **Track:** `ZStack(alignment:.topLeading) { Capsule().fill(trackColor).frame(width:34,height:20); Capsule().fill(.white).shadow(...).frame(width: thumbW, height: thumbH).offset(x: thumbX, y: thumbY) }`.
- **Hover:** `onHover`.
- **Gesture:** `DragGesture(minimumDistance: 0)`.
  - `onChanged`: set `pressed = true`. Once |dx| ≥ 2, set dragging and `thumbX = clamp(origin + dx)` inside a `Transaction(animation: nil)`.
  - `onEnded`: if not dragging → toggle. Otherwise toggle by midpoint, or spring home.
- **Animation:** everything else uses `.animation(.spring(duration:0.16,bounce:0), value: ...)`.
- **Track color:** `.animation(.easeInOut(duration:0.08))`.
- **Keyboard:** `.focusable()`, `.onKeyPress(.space)` and `.onKeyPress(.return)` toggle. Draw the focus ring as `Capsule().stroke(focusRing,lineWidth:1).padding(-3)` over a `Capsule().stroke(background, lineWidth:2).padding(-1)`.
- **Accessibility:** `.accessibilityRepresentation { Toggle(label, isOn: binding) }`.

---

## 9. Slider (`slider__slider.tsx`; `base_slider__slider.tsx`)

### 9.1 Two engines

Public `<Slider>` props: `value`, `onChange`, `min` 0, `max` 100, `step` 1, `label`, `formatValue`, `disabled`, `variant` (`pips` | `scrubber`, default `pips`), `size`.

Engine selection:

- **Default ladder step → `ComfortableSlider`**, a 32px bordered row.
- **Compact step → `CompactSlider`**, a thumb on a pill.
- The compact engine is also forced whenever `value` is a range `[a,b]` or any compact-only prop is present: `steps`, `showSteps`, `showValue`, `valuePosition`, `trackClassName`, `trackStyle`, `fillClassName`, `fillStyle`, `hideFill`, `thumbColor`, `thumbBorderColor`.

Both engines lay an **invisible** Radix (or Base UI) slider underneath for ARIA and arrow keys. Pointer input is handled by custom code, so presses can spring.

Keyboard (from the primitive): arrows ±step; Home/End = min/max; PageUp/PageDown and Shift+arrows = ±10 steps (Radix defaults).

### 9.2 ComfortableSlider (default step)

**Row:**

```
"relative w-full h-8 select-none touch-none border border-border overflow-hidden outline-offset-2" + "cursor-ew-resize" + rounded-lg (8px)
scrubber adds "flex items-center gap-3 px-4"
```

- 32 tall, full width, 1px `--border`, radius 8, clipped.
- An invisible hit area extends **8px beyond each side** (`left:-8,right:-8`). Presses there clamp to min or max.
- **Keyboard focus:** an `outline: 1px solid #6B97FF` 2px outside the row. It is animated between transparent and the ring color on `spring.fast`.

**Label and value:**

- Body 13/20, weight 400.
- Color `muted-foreground` → `foreground` while hovered **or** keyboard-focused (`isActive`), animated on `spring.fast`.
- **Pips:** the label is 16px from the left inner edge (`px-2` container + `px-2` span) and the value 16px from the right.
- **Scrubber:** `px-4`, with label and value in the flex row (`gap-3` = 12).
- **Value:** `tabular-nums`, right-aligned, `minWidth = formatValue(max).length` in ch.

**Pips variant** (z-order bottom → top):

1. **Pip dots** (z1): a layer `absolute inset-0 flex justify-between items-center px-3` with one 5×5 circle per step.
   - Color: `muted-foreground` at opacity 0.3.
   - The pip equal to the value is `foreground` at opacity 1 (animated on `spring.fast`). It is only visible at min; elsewhere the mask hides it.
   - Masked by `linear-gradient(to right, transparent calc(p·100% + off), black calc(p·100% + off + 2px))` with `off = 20 − 20p − zo·2.5`. Pips under the fill are hidden with a 2px feather.
2. **Text occluders** (z2): transparent-text copies of the label and value on `bg-background`, so pips never cross the words.
3. **Fill** (z3): `var(--active)` from the left. Width `calc(p·100% + (20 − 20p − zo·2.5)px)`.
   - `zo` (zero offset) animates on `spring.fast` to **8** when the value equals min, otherwise 0. At min the fill width is 0.
4. **Handle line** (z3): 2px wide, capsule.
   - Inset 8 top and bottom (16 tall) at rest; **7 (18 tall) while active**.
   - Color: `fg 25%` rest, `fg 50%` hover, `fg 100%` keyboard focus.
   - Position `left = calc(p·100% + (11 − 24p)px)`. Inset follows the pips row's 12px padding, so the line stays visible at both ends.
   - All changes on `spring.fast`.
5. **Text** (z4).

**Scrubber variant:**

- **Fill:** `var(--active)`, width `p·100%`, no offsets.
- **Line:** same sizes and colors as pips. `left = calc(p·100% − 9px + zo)`, with `zo` = **17** at min, which places it at 8px.
- **Grab strip:** an 8px-wide strip (`w-2`, z-20) at `left = calc(p·100% − 8px + zo)`.
  - Grabbing it sets the fill directly from the first event (no spring).
  - `stopPropagation` keeps the row's press handler from also firing.

**Hover preview** (both variants):

- A bar from the current handle x to the snapped hover x. It extends to the row edge when the snapped value is min or max.
- Fill: `color-mix(in srgb, var(--color-accent) 40%, transparent)`, unrounded. At min or max, the row's clip rounds the outer end.
- Opacity fades over **0.15s**. Hidden while pressed.

**Hover value tooltip:**

- Appears **100ms** into a hover (the bar appears on the first move; only the tooltip waits).
- Placed at the snapped x, `top: -30px`, centered (`-translate-x-1/2`).
- Bubble: `bg-foreground text-background` caption 12/16, `tabular-nums`, `px-2 py-1`, radius 8.
- Enter: `opacity 0, y 4` → `1, 0` on `spring.fast`. Exit: `opacity 0, y 4` over 0.06s.
- Hidden while pressed.

**Pointer:**

- **Press:** jumps to the snapped value (`onChange`). The fill animates on `spring.fast`.
- **Drag:**
  - Scrubber: `fillPercent.set()` directly, so the fill is glued to the cursor.
  - Pips: `animate(fillPercent, …, spring.fast)` per snap, so each pip jump eases.
- No settle step on release.
- **Mapping:** pips use `index = round(x/w·(n−1))` over the full row width. The scrubber uses `round(raw/step)·step`.
- **Keyboard:** changes animate the fill on `spring.fast`.

### 9.3 CompactSlider (compact step, or forced)

**Constants:**

- `THUMB_SIZE` 20 (layout box).
- `THUMB_SIZE_REST` 16 (visible knob).
- `TRACK_BG_HEIGHT` 18.
- `TRACK_INSET` 1.
- `DOT_SIZE` 4.

**Track element:**

- `relative w-full cursor-ew-resize py-2`, height 36. The press target is 36 tall.
- Plus an extended hit area 8px beyond each side.
- Hidden (`opacity 0`) until the first measurement, so the thumbs never visibly slide in from 0.

**Pill:**

```
"absolute border border-border overflow-hidden rounded-full"  left:1 right:1 top:9 height:18, background transparent
```

- 18 tall, 1px `--border`, transparent, capsule, clipped.
- Its ends are concentric with the thumb centers at min and max.

**Fill:**

```
"absolute h-full bg-selected/50 dark:bg-accent/40"
```

- Light: #D4D4D4 at 50%. Dark: #525252 at 40%.
- Single value: from the pill start to the thumb center. Range: from center to center.
- Glued to the thumbs' motion values.

**Thumb:**

- A 20×20 box at `top:50%`, `marginTop:-10`, x = motion value.
- Knob: a 16×16 circle, `white` (or `thumbColor`), `boxShadow: 0 1px 2px rgba(0,0,0,0.1)`, optional `1px solid thumbBorderColor`.
- **No size change on hover or press** in this engine.
- **Focus ring:** a 24×24 circle with a `1px #6B97FF` border, i.e. 4px outside the knob. Opacity 0 ↔ 1 on `spring.fast`, keyboard focus only.

**Step dots** (`showSteps`):

- 4px circles, `muted-foreground` at opacity 0.3.
- Grow to **5px while the slider is hovered** (`spring.moderate`).
- Centered under thumb centers: `left = calc(10px + percent·(100% − 20px))`.
- Masked with a 2px feather so the dots on the filled side (or between range thumbs) are hidden.

**Hover preview bar:**

- `accent@40%`, from the nearer thumb's center to the snapped hover value.
- Rounded only at the leading end: `0 9999 9999 0` when it extends right, mirrored when it extends left.
- Opacity fades over 0.15s. Hidden while pressed.

**Hover tooltip:**

- Same as the comfortable engine, but `top: -20px`.
- Disabled when `valuePosition = "tooltip"`.

**Motion:**

- **Press:** the nearer thumb is chosen (ties go to the first) and springs (`spring.moderate`) to the snapped value. The value is emitted immediately.
- **Drag:** the snapped position is set directly. The thumb steps along the grid, which reads as continuous when steps are fine.
- **Release:** settles to the snapped position on `spring.moderate`.
- **Keyboard, programmatic change and resize:** `spring.moderate`.
- **Range:** each thumb stops 10px (half a thumb) short of the other, so they never cross.

**valuePosition:** `left` (default) | `right` | `top` | `bottom` | `tooltip`.

- **left / right:** the root becomes `flex-row items-center gap-2 mb-2` and the track area is 36 tall.
- **top / bottom:** stacked layout.
- **tooltip:** the track area gets a 16px top padding and shows a value bubble above each thumb while hovered or pressed.
  - Bubble at `top:-16`. Its x follows the thumb center frame by frame.
  - Enter on `spring.fast` from `y:4`; exit over 0.06s.

**Value label** (`ValueDisplay`):

- 13px, `leading-none`, `muted-foreground`, `tabular-nums`.
- Weight **normal → semibold over 100ms while hovered or pressed** (`transition-[font-variation-settings] duration-100`). Weight, not color, signals interaction.
- A ghost copy of the widest string (`"Label: " + formatValue(max)`, or `"… — …"` for a range) at semibold reserves the width.
- Range separator: `—` with `mx-1` (4px).

**Click-to-edit:**

- Clicking the number swaps in a `type=number` input, 5ch wide, centered, `border-b border-border`, text 16px on touch.
- The input auto-selects its contents.
- Enter or blur commits (clamped, then snapped to the step grid or the `steps` list). Escape cancels. Unparseable input cancels.

**`steps` list:**

- Non-uniform allowed values. min and max are the list's ends.
- The primitive runs on indices, so arrow keys walk the list.
- `aria-valuetext` = the formatted value.

**Accessibility:**

- Each thumb has its own `aria-label` (`label`, or `"<label> minimum"` / `"<label> maximum"`).

**Base UI vs Radix:** only the primitive wiring differs (`Control`, `Indicator`, `index`, `getAriaValueText`). Visuals are identical.

### 9.4 SwiftUI translation notes

- Build both engines as custom views. The system `Slider` cannot reproduce this.
- **Shared setup:**
  - A `GeometryReader` gives the width.
  - `@State var fill: CGFloat` (or the thumb x).
  - `DragGesture(minimumDistance: 0, coordinateSpace: .local)`.
  - Press: `withAnimation(.spring(duration:0.08 /*comfortable*/ or 0.16 /*compact*/, bounce:0))`.
  - Scrubber and compact drags: write the state inside `withTransaction(Transaction(animation: nil))`.
- **Masks:** `.mask(LinearGradient(stops: [.init(color:.clear, location: edge/w), .init(color:.black, location:(edge+2)/w)], startPoint:.leading, endPoint:.trailing))`.
- **Hover:** `.onContinuousHover`. Start a 100ms `Task` before showing the tooltip.
- **Keyboard:** `.focusable()` + `.onKeyPress(.leftArrow/.rightArrow/.home/.end/.pageUp/.pageDown)`. Expose `.accessibilityValue` and `.accessibilityAdjustableAction`.
- **Weight shift:** animate the Inter `wght` via an `Animatable` font modifier, with a hidden semibold ghost for the width.
- **Focus outline (comfortable):** `RoundedRectangle(cornerRadius: 10).stroke(focused ? ring : .clear, lineWidth: 1).padding(-3)` (radius 8 + 2px offset ≈ 10–11).

---

## 10. CarouselDots (`carousel-dots__carousel-dots.tsx`)

### 10.1 Props

- `count`, `value` (current index), `onValueChange(i)`, `getLabel` (default `"Go to slide N"`).
- `autoplay`: `true` | `{ duration=3000ms, paused=false, loop=true }`.
- `progress`: number or MotionValue 0–1. External clock; takes precedence over autoplay.

### 10.2 Dimensions

```
root  : "relative flex w-fit items-center"  role="group" aria-label="Slides"
button: "relative z-10 flex items-center rounded-full p-1.5 outline-none focus-visible:ring-1 focus-visible:ring-[color:var(--focus-ring,#6B97FF)]"
dot   : "relative block overflow-hidden rounded-full"  height 6, width 6 | 24 (current)
fill  : "absolute inset-0 rounded-full"
```

| Element | Size |
|---|---|
| Dot | 6×6 |
| Current dot (pill) | 24×6 |
| Button (padding 6 all round) | 18×18 (capsule hit area); 36×18 around the pill |
| Space between dots | 12 visually (6 + 6 padding, no gap, so the highlight never drops out between dots) |

### 10.3 Colors

| Part | Value | Opaque equivalent |
|---|---|---|
| Track (every dot) | `color-mix(in oklab, var(--foreground), transparent 85%)` = fg @ 15% | #D8D8D8 / #383838 |
| Current-pill fill | fg @ 40% | #9F9F9F / #707070 |
| Hover | one fluid highlight (`bg-hover`, `rounded-full`) springing (`spring.fast`) between the 18px button capsules along x | — |
| Focus | 1px ring on the button capsule | — |

### 10.4 Motion

- **Width 6 ↔ 24:** `spring.moderate`. Merge/split feel: the old pill shrinks while the new one grows simultaneously.
- **Fill:** a full-width pill slid in from the left, **never scaled** (scaling would squash the round end).
  - `transform: translateX(calc((p − 1) × (100% − 6px)))`.
  - At p = 0 a perfect 6px circle shows at the left end; at p = 1 it covers the pill.
- **Static (no autoplay or progress):** p = 1, so the current pill is solid fg@40%.
- **Autoplay:**
  - A `requestAnimationFrame` clock advances p by `dt/duration` and holds while `paused`.
  - Frames over 100ms are ignored, so background tabs do not jump.
  - At p = 1 it calls `onValueChange((value + 1) % count)` once. Without `loop` it stops at the last slide.
  - p resets to 0 whenever `value` changes, from any source.
- **Reduced motion:** the width change is instant (duration 0) and **autoplay is disabled**.

### 10.5 Accessibility

- Each dot is a `<button>` with `aria-label` and `aria-current="true"` on the current one.
- No roving tabindex or arrow-key handling: each dot is its own Tab stop.

### 10.6 SwiftUI translation notes

- **Structure:** `HStack(spacing: 0) { ForEach(0..<count) { i in Button { … } label: { dot(i) }.padding(6).contentShape(Capsule()) } }`.
- **Dot:** `Capsule().fill(track).frame(width: current ? 24 : 6, height: 6).overlay(alignment:.leading) { if current { Capsule().fill(fill).offset(x: (p - 1) * (w - 6)) } }.clipShape(Capsule())`.
- **Width animation:** `.animation(reduceMotion ? nil : .spring(duration:0.16,bounce:0), value: value)`.
- **Autoplay:** `TimelineView(.animation(paused: paused || reduceMotion))` integrating `dt`, or a `CADisplayLink`/`Timer`. Skip `dt > 0.1`.
- **Hover:** the same shared fluid-highlight capsule used elsewhere, keyed to the button frames.

---

## 11. ThinkingIndicator (`thinking-indicator__thinking-indicator.tsx`, `thinking-indicator__theme.json`)

### 11.1 Props

- `showIcon` (default true)
- `size` (default | compact)

### 11.2 Layout

```
root : "flex items-center gap-2 px-3 py-2"  role="status"  (+ sr-only "Thinking…")
glyph: 20×20 (compact 18×18) svg, viewBox 24, stroke currentColor 1.5, round caps/joins, "text-muted-foreground shrink-0"
words: "inline-grid overflow-hidden" + body type (13/20, compact 12/18), weight normal (400)
```

Gap 8, padding 12 horizontal × 8 vertical, so the row is 36 tall at default.

### 11.3 Glyph morph

- One path animates `d` through `[circleA, infinity, circleB, infinity, circleA]` with `times [0, .25, .5, .75, 1]`, **6s, easeInOut, repeat forever**. That is 4 equal 1.5s quarters.
- All three shapes share the same command structure (M + 4 C + Z), so the morph interpolates point by point.
- circleA and circleB trace the same circle in opposite directions, so each pass through ∞ keeps flowing one way.
  - circleA: `M 12 8 C 14.21 8 16 9.79 16 12 C 16 14.21 14.21 16 12 16 C 9.79 16 8 14.21 8 12 C 8 9.79 9.79 8 12 8 Z`
  - infinity: `M 12 12 C 14 8.5 19 8.5 19 12 C 19 15.5 14 15.5 12 12 C 10 8.5 5 8.5 5 12 C 5 15.5 10 15.5 12 12 Z`
  - circleB: `M 12 16 C 14.21 16 16 14.21 16 12 C 16 9.79 14.21 8 12 8 C 9.79 8 8 9.79 8 12 C 8 14.21 9.79 16 12 16 Z`

### 11.4 Word cycle

- Words `["Thinking", "Moonwalking", "Planning", "Refining"]`, advancing every **4000ms**.
- All words share one grid cell, with `overflow-hidden` acting as a slot-machine clip.
- An invisible copy of the longest word ("Moonwalking") reserves the width.
- `AnimatePresence mode="popLayout" initial={false}`:
  - **Enter:** `y 80% → 0`, `opacity 0 → 1`, **0.24s** `cubic-bezier(0.4,0,0.2,1)`.
  - **Exit:** `y 0 → −80%`, `opacity → 0`, **0.16s** same curve.
  - Both overlap: the old word rolls up and out as the new one rolls up from below.

### 11.5 Shimmer text

The site's actual CSS, which is theme-aware:

```css
.shimmer-text{color:transparent;
  background:linear-gradient(90deg, light-dark(#a3a3a3,#525252) 0 35%, light-dark(#525252,#a3a3a3) 50%, light-dark(#a3a3a3,#525252) 65% 100%) 0 0/300% 100%;
  background-clip:text; animation: shimmer 1.5s ease-in-out infinite }
@keyframes shimmer { 0% {background-position:0% 0} 100% {background-position:100% 0} }
```

- **Light:** base #A3A3A3 with a darker #525252 band. **Dark:** base #525252 with a lighter #A3A3A3 band.
- The registry `theme.json` hard-codes only the light pair.
- The gradient is 3× the text width. Animating `background-position` 0% → 100% moves the band center from x = 1.5W to x = −0.5W, so the band **sweeps right to left**. It is visible while p is between 0.25 and 0.75 of each 1.5s ease-in-out cycle, then jumps back.

### 11.6 Reduced motion and accessibility

- **Reduced motion:**
  - The glyph is the static ∞ path.
  - The word is a static "Thinking" with no cycling.
  - The CSS shimmer **still runs**; the component does not gate it. Consider gating it in the port.
- **Accessibility:** `role="status"` with a static sr-only "Thinking…". The cycling words are `aria-hidden`.

### 11.7 SwiftUI translation notes

- **Glyph:** `struct MorphShape: Shape, Animatable` holding 13 control points (`[CGPoint]`), with `animatableData` as a custom `VectorArithmetic` array. Drive it with `keyframeAnimator` (macOS 14) over 6s, repeating, `.easeInOut` per quarter, or interpolate manually in a `TimelineView`. Stroke 1.5, round caps, scaled from 24 to 20.
- **Words:** `ZStack { Text(longest).hidden(); Text(word).id(word).transition(.asymmetric(insertion: .offset(y: 0.8*h).combined(with:.opacity), removal: .offset(y:-0.8*h).combined(with:.opacity))) }.clipped()`.
  - Insertion: `.timingCurve(0.4,0,0.2,1,duration:0.24)`. Removal: same curve, 0.16s.
  - Advance with a 4s `Timer`.
- **Shimmer:** `Text(...).foregroundStyle(LinearGradient(stops: [...], startPoint: UnitPoint(x: s, y:0), endPoint: UnitPoint(x: s+3, y:0)))` with s animated from 0 to −2 over 1.5s easeInOut, repeating. Alternatively mask an animated gradient rectangle with the text.
- Gate all of it on `@Environment(\.accessibilityReduceMotion)`.

---

## 12. ThinkingSteps (`thinking-steps__thinking-steps.tsx`; `base_thinking-steps__thinking-steps.tsx`; theme = shimmer CSS as §11)

### 12.1 Parts

- `ThinkingSteps`: collapsible root, `defaultOpen` **true**, controlled `open` / `onOpenChange`, `size`.
- `ThinkingStepsHeader`: label, default "Thinking".
- `ThinkingStepsContent`
- `ThinkingStep`: icon, `showIcon`, label, description, status, delay, `isLast`.
- `ThinkingStepDetails`: a nested collapsible with summary and details, `defaultOpen` false.
- `ThinkingStepSources` / `ThinkingStepSource`: badge chips.
- `ThinkingStepImage`

Root: `"w-80 max-w-full"`, 320px wide.

### 12.2 Header (`TriggerRow`)

```
wrapper : "relative w-fit"   (hover tracked here)
hover bg: "absolute inset-0 rounded-lg bg-hover pointer-events-none"  fade in 0.08s, out 0.06s
trigger : "relative z-10 flex items-center gap-2.5 rounded-lg px-3 py-2 cursor-pointer outline-none select-none focus-visible:ring-1 focus-visible:ring-[color:var(--focus-ring,#6B97FF)] focus-visible:ring-offset-0"
          compact: "px-2.5 py-1.5"
label   : "inline-grid text-left" + body type; ghost semibold copy + visible copy "transition-[color,font-variation-settings] duration-80"
```

- **Size:** gap 10; padding 12×8 (36 tall); compact 10×6 (30 tall). Radius 8.
- **Hover background:** hugs the trigger (`w-fit`).
- **Label:** body 13/20 (12/18 compact).
  - Color: `muted-foreground` when closed and not hovered. `foreground` when **open or hovered** (`highlighted`).
  - Weight: **normal → semibold only when open** (80ms). A ghost reserves the width.
- **Chevron:** `chevron-right` at 16 (14 compact).
  - Rotates **0° → 90° when open** on `spring.fast`.
  - Stroke 1.5 → **2** and color muted → foreground when highlighted (80ms).
  - Placed after the label.

### 12.3 Panel (`CollapsePanel`)

- The height animates to a **measured layout height** with `spring.moderate` (0.16s, bounce 0), for both open and close. This avoids `auto`.
- A panel that is open at mount snaps (no animation).
- After the close finishes, the panel gets `hidden` (display none) but stays mounted, so the ARIA link is kept.
- Content: `"px-3 pb-3 pt-1 text-muted-foreground"` + body type, i.e. padding 12 horizontal, 12 bottom, 4 top.
- Step list: `flex flex-col`.

### 12.4 ThinkingStep

**Status:**

- `pending` → not rendered.
- `active` → the label gets `shimmer-text` and a trailing "…".
- `complete` (default) → plain.

**Enter animation:**

- Outer `overflow-hidden` height 0 → measured, on **`spring.slow`** (0.24s, **bounce 0.12**). There is slight overshoot room as each step opens.
- Inner opacity 0 → 1, **0.24s easeOut, delay `delay`** (default 0.08s). The content fades in after the space starts opening.

**Row:**

```
"flex gap-2.5 px-2 py-1.5 rounded-lg"
```

Gap 10, padding 8×6.

**Icon column** (`flex flex-col items-center shrink-0 w-[14px]`):

- The icon is inside a `pt-0.5` (2px) wrapper.
- Icon: default `dot`, 14 (12 compact), `text-muted-foreground`, stroke 1.5.
- `showIcon=false` → a 6×6 circle `bg-muted-foreground/60` centered in a 14×14 box.
- **Connector line** (not on the last step): `flex-1 w-px bg-border/60 mt-1`. A 1px vertical hairline at fg@7.2%, starting 4px below the icon and running to the bottom of the step, so consecutive steps form one continuous rail.

**Text column** (`flex-1 flex flex-col gap-1 min-w-0`, gap 4):

- Label: body 13/20, **semibold 550**, foreground (shimmer when active).
- Description: body 13/20, normal weight, `muted-foreground`.
- Then children.

### 12.5 ThinkingStepDetails

- Root `"mt-1 -ml-3"` (4 top, −12 left, which aligns the trigger's text with the step text).
- `TriggerRow` with `className="py-1 px-3 gap-1.5"`: padding 12×4, gap 6, same hover, weight, chevron and color behavior.
- Panel content `"flex flex-col gap-0.5 pt-0.5"`; each detail is caption 12/16 (11/14 compact) in `muted-foreground`.
- The panel itself still has the `px-3 pb-3 pt-1` wrapper.

### 12.6 ThinkingStepSources and ThinkingStepSource

- **Sources container:** `"flex flex-wrap gap-1.5 mt-1"` (gap 6, top 4).
- **Each source:**
  - A Badge, `solid`, size `sm` → compact: 20 tall, 8 horizontal padding, 11/14 text. Color default gray (`--accent` background).
  - Enter: `opacity 0, scale 0.85, blur 4px` → `1, 1, 0` on `spring.moderate`, with per-item `delay`. The blur resolves over 0.12s with the same delay.

### 12.7 ThinkingStepImage

- `mt-1.5` (6).
- Image: `w-full max-w-[200px] object-cover`, radius **12**, inset 1px outline black/10 (white/10 dark).
- Enter: opacity 0.2s easeOut + blur 4 → 0 over 0.15s, after `delay`.
- Caption: caption role, `muted-foreground`, `mt-1` (4).

### 12.8 Accessibility

- The header is a Collapsible trigger: `<button>` with `aria-expanded` and `aria-controls`. Enter and Space toggle.
- Focus ring: 1px, offset 0, radius 8.
- **Base UI vs Radix:** identical visuals. Base UI uses `Collapsible.Panel keepMounted` with a render prop and strips its premature `hidden`.

### 12.9 SwiftUI translation notes

- Do not use `DisclosureGroup`, which is system-styled.
- **Header:** a `Button` with `.buttonStyle(.plain)`.
  - Label: `ZStack { Text(t).fontWeight(semibold).hidden(); Text(t).interFont(weight: open ? 550 : 400).foregroundStyle(highlighted ? fg : muted) }`.
  - Chevron: `Image(systemName:"chevron.right").rotationEffect(.degrees(open ? 90 : 0)).animation(.spring(duration:0.08,bounce:0), value: open)`.
  - Hover: a `RoundedRectangle(cornerRadius: 8).fill(hover)` background with opacity animated 0.08 in / 0.06 out.
- **Panel:** `content.fixedSize(horizontal:false, vertical:true).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h = $0 }`, then `.frame(height: open ? h : 0, alignment: .top).clipped()` with `.animation(.spring(duration:0.16,bounce:0), value: open)`.
- **Steps:** insert each with a custom transition. Animate the height from 0 → h with `.spring(duration:0.24,bounce:0.12)` (a `GeometryReader`-measured `frame(height:)`), and the content opacity with `.easeOut(duration:0.24).delay(delay)`.
  - Rail: `Rectangle().fill(border.opacity(0.6)).frame(width:1)` in a `VStack` under the icon, with `.frame(maxHeight:.infinity)`.
- **Sources:** `.transition(.scale(0.85).combined(with:.opacity))` plus `.blur(radius: appeared ? 0 : 4)`, with `.spring(duration:0.16,bounce:0).delay(d)`.
- **Shimmer:** as in §11.
- **Accessibility:** set `.accessibilityAddTraits(.isButton)` and `.accessibilityValue(open ? "expanded" : "collapsed")` on the header.
