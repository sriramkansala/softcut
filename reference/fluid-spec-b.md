# Fluid Functionalism → SwiftUI: Spec B

Covers: fluid hover hook and highlight, merge/split selection backgrounds, Tabs, TabsSubtle, Select, Dropdown (menu item, sub-menu, search), Combobox, CommandMenu, ScrollArea, Sidebar (core and menu).

Source: `reference/fluid-registry/src/` (Radix flavor, `<item>__<file>`). The `base_*` (Base UI) copies have the same visuals. `menu-item`, `dropdown-sub`, `sidebar-core` and `sidebar-menu` are byte-identical between the two flavors. Where the spec says "on page", it means substrate surface 1. All px values assume the default 16px rem.

Foundations (surface ladder, springs, type scale, size ladder, shape) are assumed known and are only referenced here. The shorthand used below:

| Shorthand | Meaning |
|---|---|
| `fast` / `fast.exit` | spring 0.08s bounce 0 / tween 0.06s |
| `moderate` / `moderate.exit` | spring 0.16s bounce 0 / tween 0.12s |
| `slow` / `slow.exit` | spring 0.24s bounce 0.12 / tween 0.16s |
| `fade80` | opacity tween 0.08s (Motion `{ duration: 0.08 }`) |
| `css80` | CSS transition 80ms, Tailwind default ease `cubic-bezier(0.4, 0, 0.2, 1)` (`duration-80`) |
| D / C | default size step / compact size step |
| `focus-ring` | `var(--focus-ring, #6B97FF)` |
| `overlay` | `rgb(var(--overlay))`, which is `0 0 0` in light mode and `255 255 255` in dark mode |

Token values the specs rely on (`tokens__theme.json`):

| Token | Light | Dark |
|---|---|---|
| `hover` | `rgb(0 0 0 / 0.04)` | `rgb(255 255 255 / 0.06)` |
| `active` | `rgb(0 0 0 / 0.07)` | `rgb(255 255 255 / 0.10)` |
| `selected` | `#D4D4D4` | `#525252` |
| `focus-ring` | `#6B97FF` | (same) |

`muted`, `card`, `background`, `border`, `foreground`, `muted-foreground` and `destructive` are shadcn base tokens. None of them is defined in the registry theme files, so take them from your app palette.

Motion tween easing: an exit or fade with only a `duration` given uses Motion's default tween ease. Port it as `.easeInOut(duration:)`; at 60–160ms the curve is not perceptible.

---

## 0. Shared popup anatomy (Select, Dropdown, Combobox)

All three popups share `popup.ts`, `Elevated` and the same overlay stack. The per-component sections below only list differences from this.

### 0.1 Shell

```
Portal > Content(positioner) > motion.div[popupMotionClass] > Elevated(offset 2, shadowLevel 3)
  > ScrollArea(popupScrollAreaClass, viewport popupViewportClass + "scroll-fade")
    > div.relative.flex.flex-col.p-1   ← "list": rows' offsetParent; overlays live here and scroll with rows
       [selected bg] [hover bg] [focus ring] rows…
```

| Property | Value |
|---|---|
| Surface | `bg-surface-{substrate+2}` (surface-3 on page; surface-7 inside a dialog at 5), clamp 8 |
| Shadow | `shadow-surface-3`, fixed whatever the nesting (`shadowLevel={3}`) |
| Radius | `rounded-xl` = **12px**. The popup always uses the "rounded" shape, even in pill mode (`shapeMap.rounded`). Reason given in source: pill corners break the concentric fit of the rows. |
| Clip | `overflow-hidden` on the surface |
| List padding | `p-1` = **4px** on all sides. Row radius is 8px, and 8 + 4 = 12, so the rows are concentric with the container. |
| Row gap | none (rows abut) |
| Offset from trigger | `sideOffset={6}` = **6px** gap. `align="start"` (left edges aligned). Default side is `bottom`; the popup flips on collision. |
| Min width | trigger width (`min-w-[var(--radix-…-trigger-width)]`) |
| Scroll | inside ScrollArea (section 9). Viewport inherits max-height and has `--scroll-fade-size:32px` (32px edge fade masks). |

### 0.2 Open/close animation (`popupMotionClass`)

| | Value |
|---|---|
| Enter from | `{ opacity: 0, y: var(--popup-enter-y), scaleY: 0.96 }` to `{ opacity: 1, y: 0, scaleY: 1 }`, using `fast` |
| Exit to | the same initial values, using `fast.exit` (0.06s tween) |
| Origin and slide follow the **resolved** side (after flipping) | bottom: `origin-top`, `--popup-enter-y: -4px` (slides down 4px into place) · top: `origin-bottom`, `+4px` · left: `origin-right`, `0px` · right: `origin-left`, `0px` |
| Scale axis | Y only (no X scale) |
| Unmount | after exit finishes (`onAnimationComplete`). Fallback timer: exit duration + 100ms = **160ms**. |

Class string:
`"origin-top [--popup-enter-y:-4px] data-[side=top]:origin-bottom data-[side=top]:[--popup-enter-y:4px] … data-[side=left]:origin-right data-[side=left]:[--popup-enter-y:0px] … data-[side=right]:origin-left data-[side=right]:[--popup-enter-y:0px]"`

### 0.3 Rows (shared metrics)

| | D | C |
|---|---|---|
| Height (`size.control`) | `h-9` **36px** | `h-7` **28px** |
| Horizontal padding (`itemPx`) | `px-2` **8px** | `px-1.5` **6px** |
| Icon to label gap (`gap`) | `gap-2` **8px** | `gap-1` **4px** |
| Text | body 13/20 | body 12/18 |
| Icon | 16px | 14px |
| Radius | `rounded-lg` **8px** | 8px |

Rows are `relative z-10 … shrink-0 items-center cursor-pointer outline-none select-none`, so they sit above the overlays. Text is vertically trimmed (`[text-box:trim-both_cap_alphabetic]`), which centers the cap height optically rather than the line box.

Row states:

| State | Text | Icon stroke | Background |
|---|---|---|---|
| Rest | `muted-foreground` | 1.5 | none |
| Highlighted (pointer or keyboard) | `foreground` | 2 | fluid hover highlight `bg-hover` |
| Checked | `foreground` | 2 | `bg-active` marker |
| Highlighted + checked | `foreground` | 2 | `bg-active` + `bg-hover` stacked (both translucent) |
| Disabled | `opacity-50 pointer-events-none` | n/a | never highlighted (hook skips it, `isDisabledRow` reads `aria-disabled="true"` / `data-disabled`) |

Color and stroke changes use `css80` (`transition-[color,stroke-width] duration-80`).

### 0.4 Overlay stack (bottom to top), all `absolute pointer-events-none` inside the list

1. **Selected background**: `absolute rounded-lg bg-active`. Animates `top/left/width/height` with `moderate` and opacity with `fade80`. `initial={false}`: the first appearance snaps in with no animation; a later change of checked row springs from the old row to the new one. Exit: opacity to 0 over `moderate.exit` (0.12s).
2. **Hover highlight**: `FluidHoverHighlight` (section 1.3), `bg-hover`, radius 8px.
3. **Focus ring** (Select only; Dropdown and Combobox popups draw no ring): `absolute rounded-[10px] z-20 border border-[color:var(--focus-ring,#6B97FF)]` at `rect` expanded by 2px on every side (`left-2, top-2, width+4, height+4`). 1px stroke, radius 10px (8 + 2, concentric). Travels with `fast`, exits with `fast.exit`.

All three are **torn down at the start of close** rather than exit-animated (`open &&` wrapper, and the indices reset in the render that closes). Otherwise a reopened popup would reuse the old overlay and slide it from the previous row. The popup's own 0.06s fade hides the teardown. Overlays also wait for `isMeasured` (section 1.1), so they never mount against stale rects.

### 0.5 Checkmark (Select, Combobox, Dropdown MenuItem)

- SVG 24×24 viewBox, drawn at icon size (16 / 14). Path `M4 12L9 17L20 6`, `stroke-width 2`, round caps and joins, `text-foreground`.
- Enter: `pathLength` 0 → 1 over **0.08s easeOut**. Exit: `pathLength` 1 → 0 over **0.04s easeIn**. The check draws in and undraws; there is no opacity fade.
- `AnimatePresence initial={false}`: a row that is already checked when the popup mounts shows the finished check (no draw on page load or on open).
- Select and Combobox reserve a fixed trailing slot that is always rendered: `w-4 h-4` (16px) D / `w-3.5 h-3.5` (14px) C. This stops the popup width from changing when a check appears. Dropdown MenuItem renders the check inline at the trailing end with no reserved slot, which is fine because Dropdown has a fixed `w-72`.

### 0.6 Label / separator / empty

| Part | Class | px |
|---|---|---|
| Group label | `"px-2 py-1.5 shrink-0 text-muted-foreground"` + caption | 8px horizontal, 6px vertical; caption 12/16 (C 11/14). Height 28px (C 26px). |
| Separator | `"my-1 -mx-1 h-px shrink-0 bg-border/60"` | 1px line, 4px above and below. Bleeds across the 4px list padding to touch both popup edges. `border` at 60% alpha. Adds 9px. |

### 0.7 Popup height math

Content height = 4 + Σrows + 4. N plain rows give `36N + 8` (D) or `28N + 8` (C). The cap is per component (Select/Combobox 300px, Dropdown 480px, each `min()`-ed with the available viewport height); past the cap the list scrolls.

---

## 1. Fluid hover: `useFluidHover` + `FluidHoverHighlight`

### 1.1 What the hook tracks

- **Registry**: `Map<index, element>`. Items register by index via ref. Indices may be sparse.
- **Rects**: each item's **layout** rect relative to the container. It uses `offsetTop/Left/Width/Height`, accumulating positioned ancestors inside the container. These values ignore CSS transforms, so a popup's in-progress `scaleY` does not distort them. Rects are only published when every item has a layout box; the measurement pass retries for up to 3 frames before giving up. Remeasure triggers are coalesced into one rAF: item register/unregister, any item's ResizeObserver, the container's ResizeObserver, and an explicit `remeasure()` (popups call it on every open).
- **`isMeasured`**: false from `remeasure()` until the coalesced pass succeeds. Overlays gate on it, because a highlight mounted against a later-corrected rect would visibly slide in from the wrong row.
- **`activeIndex`**: the highlighted item, or `null`.
- **`session`**: a counter. See 1.2.

### 1.2 The selection rule (`pickNearest`). Run at most once per animation frame (each mousemove cancels and reschedules a rAF)

```
for each registered, non-disabled item i (index order):
    map its layout rect into viewport space:
        start = containerRect.origin + (border + rect.origin − scroll) × scale
        (scale = containerRect.size / container.offsetSize, which factors out an ancestor transform)
    if pointer is inside the item along the axis (inclusive edges)  → containing = i   (later items overwrite)
    distance = |pointer − item center| along the axis
    if distance < best (strict)  → nearest = i      (ties keep the FIRST item)
return containing ?? nearest
```

- **Axis**: `"y"` (default, vertical lists) compares top/height only. `"x"` (Tabs, TabsSubtle) compares left/width only. `"xy"` uses an inside test on both axes, with nearest by Euclidean distance to the center.
- Effect: as long as the pointer is anywhere inside the container, something is always highlighted. That includes the container padding, the gaps between rows, the space past the last row, and section headings. The highlight never flickers off between rows.
- Disabled items (`isItemDisabled(el)`) are skipped for both containment and nearest.
- **Enter**: sets `sessionPending = true`. **Move**: the first pick that differs from the current `activeIndex` while pending increments `session` and clears pending, in the same update. **Leave**: cancels the pending rAF and sets `activeIndex = null`.
- **Gap click** (`gapClick`, on by default): a click inside the container that lands on no item and on no control (`input, textarea, select, button, a, summary, [contenteditable], [role=textbox|searchbox|button]`) and is not from a portal is redirected as a real `.click()` on the highlighted item. If the item is a wrapper, the click goes to its first interactive descendant. Optional `{ maxDistance }` restricts this to clicks within N px of the item's edge. The rule is "what is lit is what a click hits".
- If the highlighted item unregisters, the highlight is set to `null`, unless another row re-registered under the same index in the same commit.
- DOM mirrors: `data-fluid-hover-active` on the item, `data-fluid-hover-active-index` on the container.

### 1.3 The highlight (`FluidHoverHighlight`)

A single absolutely positioned div: `pointer-events-none absolute left-0 top-0 bg-hover` plus the radius class (8px in every list). It sits at `x = rect.left, y = rect.top` (as a transform) and `width/height = rect`.

| Event | What you see |
|---|---|
| Pointer moves to another row in the same session | The same element **slides and resizes** to the new row: x/y/width/height on `fast` (0.08s critically damped). Fast sweeps re-target each frame, so it chases smoothly. |
| Pointer leaves the container | `rect = null`. It fades out **in place** over `fast.exit` (0.06s). No slide. |
| Pointer re-enters (new session) | The highlight is re-keyed on `session`, so a **new** element mounts. Its initial state is `{ opacity: 0, at: from ?? rect }`, and it animates to `{ opacity: 1, at: rect }`. With no `from`, it simply fades in at the hovered row (`fade80`). With a `from` rect, it starts at `from` and glides to the hovered row while fading in. Any previous element still fading out finishes its own 0.06s exit separately. A new session never slides over from wherever the highlight last was (an old keyboard row, for example). |
| Keyboard or focus sets `activeIndex` | No session change. If a highlight is visible it slides (`fast`). If none is visible, one mounts and fades in at `from ?? rect`. |
| `hidden` prop (closed popup) | Same as `rect = null`: fade out. |
| `transition={false}` | Position snaps (duration 0) and the fade still runs. Used when rows move under a stationary highlight, such as a filter reflow or a sibling collapsing. |
| Reduced motion | Position snaps and the opacity fade is kept. |

Where components pass `from`:

| Component | `from` |
|---|---|
| Dropdown inline panel | the checked row's rect, always |
| Dropdown popup | the checked row, **only if the pointer lit the session** (`litBy === "pointer"`). Rows lit by the open or by the keyboard fade in where they are. |
| Select, Combobox, CommandMenu, Sidebar menu | none (fade in at the row) |

The result in a Dropdown with a checked item: when the pointer enters the menu, the hover fill rises out of the checked row and travels to the cursor.

### 1.4 SwiftUI translation notes (fluid hover)

- **Frames**: give the list a named coordinate space (`.coordinateSpace(.named("list"))`) placed **inside** the ScrollView content, so frames and the highlight scroll together. Collect each row's frame with `onGeometryChange(for: CGRect.self) { $0.frame(in: .named("list")) }` (macOS 15+) or a `PreferenceKey` (macOS 13/14). Keep `[Int: CGRect]`. Set `isMeasured = true` only once every registered row has a non-zero frame, and gate the overlays on it.
- **Pointer**: attach `.onContinuousHover(coordinateSpace: .named("list"))` to the list container, which must have `.contentShape(Rectangle())` so padding and gaps receive hover. `.active(p)`: run `pickNearest` on the stored frames (no rAF throttle needed; SwiftUI coalesces). Treat a transition from `.ended` to `.active` as "enter", which sets `pendingSession`. `.ended`: set `activeIndex = nil`. If the open animation scales the panel, apply the scale **outside** the named space. Locations and frames are then both in unscaled local space and no scale compensation is needed.
- **Highlight**: one `RoundedRectangle(cornerRadius: 8).fill(hover)` with `.frame(width:height:)` and `.offset(x:y:)`, inside a `ZStack(alignment: .topLeading)` behind the rows. Animate the frame with `.spring(duration: 0.08, bounce: 0)` and opacity with `.linear(duration: 0.08)`. For sessions, render `ForEach(liveHighlights, id: \.session)`. On a new session, append an entry whose frame is first set to `from ?? target` with animations disabled (`Transaction(disablesAnimations: true)`), then animate it to `target` and opacity 1 on the next run-loop turn. The previous entry fades to 0 over 0.06s and is then removed. Driving this imperatively is more predictable than `.transition` with geometry.
- **Gap click**: put `.onTapGesture` on the container's background layer that calls the highlighted row's action. Row buttons win gesture priority on their own taps, which matches the web rule that "a click inside an item is the item's".
- `matchedGeometryEffect` is **not** a good fit here. The design needs "born at another rect", "different exit paths" and "snap vs. glide" control. Explicit frames make all of that trivial.

---

## 2. Merge/split selected backgrounds (`use-merge-split`)

Used for multiple selection in the Dropdown (`checkedIndices`) and the Combobox (`multiple`). It is also the CheckboxGroup visual.

### 2.1 Runs

Checked indices are sorted and grouped into contiguous **runs** (`{start, end, id}`). Each run gets **one** `bg-active` block covering first-row top to last-row bottom: `left = min(lefts)`, `width = max(widths)`, all four corners R = **8px**. Rows abut (no gap), so a run of three checked rows reads as one 108px-tall rounded rectangle, not three pills.

Stable ids: a run reuses the id of its first row that belonged to a run last render, unless an earlier run has already claimed that id. After a split the **upper** run keeps the id and the lower run gets a new one. Because the id is the motion key, growing or shrinking a run at either end **morphs** the existing block (top/height spring on `moderate`) instead of replacing it.

Block motion (`SelectionBackgrounds`):

| | |
|---|---|
| Animated props | `top, left, width, height`, four individual corner radii, `opacity` |
| Transition | `moderate` for geometry and radii, `fade80` for opacity. `instant` blocks use duration 0. |
| Mount | `initial={false}`: a brand-new isolated block **appears instantly** (no grow, no fade), unless it has `enterFrom`, in which case it springs from that geometry. |
| Exit | opacity to 0 over `moderate.exit` (0.12s), or instantly when `exitInstant`. |

### 2.2 Ordinary edits (no special choreography)

| Action | Visual |
|---|---|
| Check a row adjacent to a run | The run's block extends its edge over the row (`moderate`). |
| Uncheck an end row of a run | The block retracts that edge (`moderate`). |
| Check an isolated row | A new block pops in at full opacity, instantly. The check draws in over 0.08s. |
| Uncheck a single-row run | The block fades out over 0.12s. |

### 2.3 Merge: checking the one unchecked row that bridges two runs

Detection happens in a layout effect before paint: one current run contains exactly two previous runs separated by exactly one row (`lo.start === up.end + 2`). Only single-row bridges get this choreography.

1. **Converge** (from the first frame). Let `midY` be the bridge row's vertical center.
   - **Survivor** (the merged run's id, normally the upper run's): drawn as the **top half**, from its top down to `midY`, radii `[R, R, 0, 0]`. Its bottom edge springs down to `midY`.
   - **Absorbed run** (the old lower block, same key): drawn as the **bottom half**, from `midY` to the run's bottom, radii `[0, 0, R, R]`. Its top edge springs up to `midY`.
   - Both edges travel on `moderate` (critically damped, so they meet exactly with no overlap or overshoot).
   - The **inner corners straighten to sharp after a delay**, so the facing corners stay rounded until the halves almost touch. Delay = `min(0.10, max(0.07, 0.07 + (midY / bridgeRowHeight) × 0.002))` s. That is 70ms baseline, plus about 2ms per row further down, capped at 100ms. The corner spring itself is `moderate`.
2. **Commit** at `convergeMs = (0.16 + 0.07) × 1000 + 80 = 310ms` (a timer, not `onAnimationComplete`, because Motion skips that callback when the target equals the current value). The survivor jumps **instantly** to the full union rect with four R corners; nothing visibly moves, since the two halves already covered it. The absorbed half is kept for one render at opacity 0 (instant) so there is no one-frame overlap flash.
3. **Drop**: on the next rAF the ghost is removed with no exit fade.

What you see: two separate pills glide toward each other, their facing corners square off just as they meet, and they become one block.

### 2.4 Split: unchecking a middle row of a run

1. **SplitIn** (first frame, pinned synchronously during render so the lower half can never mount at its final rect and snap). Both halves are drawn exactly as the single block: upper from top to `midY` with `[R, R, 0, 0]`, lower from `midY` to bottom with `[0, 0, R, R]`, both instant. The lower block mounts with `enterFrom` equal to that seam geometry.
2. **Diverge** (next rAF): the overrides are removed. The upper block's bottom edge retracts up to the end of the upper run, and the lower block's top edge moves down to the start of the lower run. Both use `moderate`, and the corners re-round on `moderate` with **no** delay.
3. The boundary is dropped at `splitMs = 160 + 80 = 240ms`.

What you see: the block parts at the deselected row's midline, and the two halves pull apart while their new inner corners round off.

### 2.5 Robustness rules worth keeping

- Boundaries are revalidated on every selection change. If the bridge row is toggled again mid-flight, the boundary and its timer are discarded. Geometry is recomputed from the live runs on every render, so rapid toggles redirect the animation instead of freezing it.
- Geometry comes only from measured rects. If a popup is closed the blocks get `[]` and nothing renders.
- In the Combobox, when filtering changes the visible row set, all blocks become `instant` until the new rects land, so they snap rather than smear.

### 2.6 SwiftUI translation notes (merge/split)

- Model the blocks as `[SelBlock]` (id, `CGRect`, four corner radii, opacity, instant flag), computed in a view model from `runs + rowFrames + boundaries`. Render with `ForEach(blocks, id: \.key)`, using `UnevenRoundedRectangle(cornerRadii:)` (macOS 14+) so each corner animates independently. Animatable radii come for free.
- Apply `.animation(.spring(duration: 0.16, bounce: 0), value: block.rect)`, plus a separate `.animation(.spring(duration: 0.16, bounce: 0).delay(cornerDelay), value: block.radii)` for merge halves. For instant blocks use `withTransaction(Transaction(disablesAnimations: true))`.
- Drive the phases with `Task { try await Task.sleep(for: .milliseconds(310)) }` (merge commit) and `240` (split drop). Cancel a task when its boundary becomes invalid. Use one run-loop hop (`DispatchQueue.main.async`) for the splitIn → diverge "next frame" step.
- Stable run ids: port `assignRunIds` directly. It is about 20 lines of pure logic.

---

## 3. Tabs (segmented control): `tabs__tabs.tsx`

Built on Radix Tabs. The muted track holds three traveling layers measured with `useFluidHover(axis: "x")`: a raised **selected pill**, a faint **hover pill**, and a shared **focus ring**. The tab buttons themselves are transparent.

### 3.1 Sizes

| | D | C |
|---|---|---|
| Track padding (`segmentPad`) | `p-1` **4px** | `p-0.5` **2px** |
| Tab height (`segmentItem`) | `h-7` **28px** | `h-6` **24px** |
| Outer height | **36px** (28 + 2×4) | **28px** (24 + 2×2) |
| Tab horizontal padding | `px-3` **12px** (both steps) | 12px |
| Icon gap | 8px | 4px |
| Text | body 13/20 | 12/18 |
| Icon | 16 | 14 |
| Track radius | `rounded-xl` **12px** (shape.container; pill mode 24px) | same |
| Pill radius | `rounded-lg` **8px** (shape.bg; pill mode 20px) | same |

Track class: `"relative inline-flex items-center select-none bg-muted" + segmentPad + rounded-xl`. There is no gap between tabs. Tab width = 12 + [icon 16 + gap 8] + label width at **semibold** + 12.

Tab class: `"relative z-10 flex items-center px-3 cursor-pointer bg-transparent border-none outline-none" + h-7|h-6 + gap`.

### 3.2 Colors per state

| Element | Rest | Hover (not selected) | Selected | Focus-visible |
|---|---|---|---|---|
| Track | `bg-muted` | n/a | n/a | n/a |
| Label / icon color | `muted-foreground` | `foreground` | `foreground` | (follows hover; focus also sets the hover index) |
| Icon stroke | 1.5 | 2 | 2 | n/a |
| Label weight | 400 (`'wght' 400, 'opsz' 14`) | 400 (hover never thickens) | **550** (`'wght' 550, 'opsz' 18`) | n/a |
| Selected pill | `bg-surface-{substrate+3} shadow-surface-{same}` = **surface-4 / shadow-surface-4** on page, surface-8 in a dialog | dims to **opacity 0.85** while another tab is hovered | opacity 1 | n/a |
| Hover pill | n/a | `bg-hover` at **opacity 0.4** | not shown when hovering the selected tab | n/a |
| Focus ring | n/a | n/a | n/a | 1px `focus-ring` border, 2px outset, radius 10px, `z-20` above the tabs |

Color, stroke and weight change on `css80` (`transition-[color,font-variation-settings] duration-80`).

**No layout shift on selection.** Each label is an `inline-grid` holding two stacked spans in the same cell: an invisible semibold copy (sets the width) and the visible label. The tab is always as wide as its bold label, so the pills never jump. The font's opsz is paired with weight to keep the advance width nearly constant on its own (the source documents semibold within ±0.4px).

### 3.3 Indicator choreography

| Layer | Behavior |
|---|---|
| Selected pill | `initial={false}`. Animates `left/top/width/height` on **`moderate`** (lands without overshoot) and opacity (0.85 ↔ 1 dim) on `fade80`. Moves **optimistically** on click (`setOptimisticIdx` in the Trigger's onClick), before controlled state round-trips. |
| Hover pill, appear | **Born at the selected pill's rect with opacity 0**, then slides to the hovered tab on **`fast`** while fading to 0.4 (`fade80`). Reads as "leaving the current choice". Only exists if a selected pill exists. |
| Hover pill, between tabs | The same element slides on `fast`. |
| Hover pill, exit, pointer **left the list** | Slides **back into the selected pill** on `moderate` while fading out over 0.06s. |
| Hover pill, exit, pointer **moved onto the selected tab** | Fades in place over `fast.exit` (0.06s). |
| Focus ring | `initial={false}`, travels on `fast`, exits with `fast.exit`. Shown only when the focused tab matches `:focus-visible` (a mouse click shows no ring). Focus also sets the hover index, so the keyboard and the mouse share one hover pill. Blur out of the list clears the ring; the hover pill stays if the mouse is still inside. |

Layer order: selected pill → hover pill → focus ring (`z-20`) → tabs (`z-10`). The ring is above the tabs; the pills are below.

### 3.4 Keyboard

Radix Tabs with `activationMode="automatic"`: ←/→ move focus **and select** in one step, so the pill follows the keyboard the way it follows a click. Home/End jump to the first/last tab. Roving tabindex: only the selected tab is a Tab stop. TabPanel is `outline-none` with no animation.

### 3.5 Clever details

- The hover pill is not `FluidHoverHighlight`: it has its own exit logic that depends on where the pointer went.
- The pill surface tracks the substrate (`substrate + 3`), so inside a dialog the pill still lifts off the track instead of melting into it.
- `axis "x"`: the track's padding always resolves to the nearest tab, so the hover pill never drops out while the pointer is inside the track.
- There is **no underline variant** in this library. TabsSubtle is the alternative style.

### 3.6 SwiftUI translation notes

`HStack(spacing: 0)` of tab buttons inside `.padding(4)` and `.background(RoundedRectangle(cornerRadius: 12).fill(muted))`. Collect tab frames in a named space on the track. Draw the pills in a `ZStack(alignment: .topLeading)` behind the HStack as explicit-frame `RoundedRectangle(cornerRadius: 8)`s.

- The selected pill animates on `.spring(duration: 0.16, bounce: 0)`.
- The hover pill needs custom insertion and removal (start from the selected frame; exit either to the selected frame or in place). Use a small state machine (`hoverFrame`, `hoverOpacity`, `exitMode`) rather than `.transition`.
- `matchedGeometryEffect` would work for the selected pill alone, but explicit frames keep all three layers consistent.
- Use `.onContinuousHover` on the track with x-nearest picking, and `@FocusState` with `.focusable()` and `.onKeyPress(.leftArrow/.rightArrow)` to move and select.
- Weight: use a ZStack holding a `.hidden()` semibold copy (it sets the width) under the visible Text, with `.fontWeight(selected ? .semibold : .regular)` and `.contentTransition(.interpolate)`. For a true 550 weight, use SF Pro or Inter variable through `NSFontDescriptor` with a `kCTFontVariationAttribute` wght axis.
- The focus ring is a 1px `strokeBorder` on a rect inset by -2px, radius 10, shown only when keyboard-focused. SwiftUI's own focus ring should be suppressed with `.focusEffectDisabled()`.

---

## 4. TabsSubtle: `tabs-subtle__tabs-subtle.tsx`

A trackless tab strip: standalone pills that sit directly on the page. It has the same choreography as Tabs, but the tabs are full control height and both pills are `bg-active`. CommandMenu uses it (compact) for its filter tabs.

### 4.1 Sizes

| | D | C |
|---|---|---|
| Tab height (`size.control`) | `h-9` **36px** | `h-7` **28px** |
| Tab horizontal padding (`size.px`) | `px-3` **12px** | `px-2.5` **10px** |
| Icon gap | 8px | 4px |
| Text / icon | body 13/20, 16 | 12/18, 14 |
| Pill radius | 8px (`rounded-lg`, also set on the button) | 8px |

List class:
`"relative flex items-center select-none overflow-x-auto max-w-[calc(100%_+_8px)] scrollbar-hide -mx-1 px-1 -my-1 py-1"`

The list scrolls horizontally with a hidden scrollbar. The −4px margin and +4px padding give the 2px-outset focus ring room so the scroll clip does not crop it. `max-w` adds back the 8px so the first and last rings are not clipped either. There is no track background and no gap between tabs.

### 4.2 States

| Element | Rest | Hover other | Selected |
|---|---|---|---|
| Selected pill | `bg-active` | dims to **0.8** | 1.0 |
| Hover pill | n/a | **`bg-active` at 0.4** (Tabs uses `bg-hover` at 0.4) | n/a |
| Label / icon | `muted-foreground`, stroke 1.5, 400 | `foreground`, stroke 2, 400 | `foreground`, stroke 2, **550** |
| Focus ring | same as Tabs (2px outset, 1px `focus-ring`, radius 10px, `z-20`) | | |

The pill timings and the born-at-selected and exit rules are identical to Tabs section 3.3.

### 4.3 `activeLabel` mode (icon tabs where only the selected tab shows its label)

- Unselected tabs show only the icon and get `aria-label`. The selected tab expands its label.
- The label wrapper animates `width` from 0 to the **measured** label width, opacity 0 → 1, and `marginLeft` 0 → **8px** (C **6px**; deliberately not the 4px gap). It uses `fast` for width and margin and **0.06s** for opacity. The exit is the reverse.
- The button drops its `gap` in this mode (the margin replaces it). A ResizeObserver on each tab remeasures the rects while labels expand, so the pills track the changing widths.

### 4.4 Keyboard

`activationMode="manual"`: ←/→ move focus (and the hover pill follows focus), and **Enter/Space selects**. Home/End are supported. Selection is index-based (`selectedIndex` / `onSelect(index)`). Panels (`TabsSubtlePanel`) are plain `role=tabpanel`, linked by `idPrefix`, and render their children only while selected.

### 4.5 SwiftUI translation notes

Same build as Tabs minus the track: `ScrollView(.horizontal, showsIndicators: false)` with 4px of padding for the ring. For `activeLabel`, wrap the label in `.frame(width: selected ? measuredWidth : 0, alignment: .leading).clipped()` with `.padding(.leading, selected ? 8 : 0)`, animated with `.spring(duration: 0.08, bounce: 0)` and opacity over 0.06s. Measure the label once with a hidden copy. Manual activation: arrow keys change only a `focusedIndex` (which drives the hover pill), and Return/Space commits.

---

## 5. Select: `select__select.tsx`

Radix Select (positioning, typeahead while open and closed, native `<select>` for forms). It is **modal-ish**: it locks page scroll and blocks outside pointer events while open.

### 5.1 Trigger

| | D | C |
|---|---|---|
| Height | 36px | 28px |
| Horizontal padding (`size.px`) | `px-3` 12px | `px-2.5` 10px |
| Gap | 8px | 4px |
| Min width | `min-w-[160px]` | `min-w-[128px]` |
| Radius | `shape.input` = 8px (follows global shape; pill mode 20px) | same |
| Text | body 13/20 | 12/18 |
| Icons | 16 | 14 |

Base class:
`"group inline-flex items-center justify-between outline-none cursor-pointer transition-all duration-80 disabled:opacity-50 disabled:pointer-events-none focus-visible:ring-1 focus-visible:ring-[color:var(--focus-ring,#6B97FF)]"`

| Variant | Rest | Hover | Focus-visible | Disabled | Error |
|---|---|---|---|---|---|
| `bordered` (default) | `border border-border bg-transparent text-foreground` | `bg-hover` | 1px ring `focus-ring` (box-shadow ring, outside the border) | `opacity-50` | `border-destructive/50` (hover too) |
| `borderless` | `border border-transparent bg-transparent` | `bg-hover` | same | same | same |

Contents, left to right:
- Optional leading icon: `muted-foreground`, stroke 1.5. On trigger hover (group-hover) it becomes `foreground`, stroke 2.
- Value text: `flex-1 truncate`, `text-left`.
- Placeholder: `"Select…"` in `muted-foreground` (via `group-data-[placeholder]:text-muted-foreground`).
- Trailing chevron-down: path `M6 9l6 6 6-6`, stroke 2, icon size. `muted-foreground` → `foreground` on hover, color-only `css80`. The **chevron does not rotate** on open.
- Error message (optional): below the trigger, gap 4px (`flex flex-col gap-1`), caption 12/16, `text-destructive`, `pl-3` (12px).

### 5.2 Popup

Section 0 applies with: `position="popper" side="bottom" align="start" sideOffset={6}`. Max height: `max-h-[min(300px,var(--radix-select-content-available-height))]`. Min width = trigger width. Width otherwise sizes to the widest row (the check slot is reserved, so the width is stable).

- **Selected marker**: section 0.4 #1 (`bg-active`). The checked row is detected two rAFs after open or after a value change.
- **Hover**: `FluidHoverHighlight`, no `from` (fades in at the row).
- **Focus ring**: section 0.4 #3, drawn **only when keyboard navigation earned it**. `useKeyboardNavGate` is seeded at open from whether the trigger was `:focus-visible` (opened by keyboard), then set by any nav key inside the popup (`ArrowUp/Down/Left/Right, Home, End, PageUp, PageDown, Tab`). A pointer-opened Select never shows a ring on its auto-focused row.
- Row text: **color change only**. There is **no weight change** on the checked row (unlike Dropdown). The check uses the reserved slot (section 0.5).
- Pointer entering the popup clears the focus ring. Blur out of the popup clears hover and ring.

### 5.3 Selection acknowledgment (the clever bit)

Picking a row **holds the popup open for 300ms** (`selectionAckMs`) before closing. During that time:
1. The `bg-active` marker springs from the old row to the picked row (`moderate`, about 2 frames after the click).
2. The old row's check undraws (0.04s) and the new one draws in (0.08s).
3. Then the popup exits (0.06s).

Escape, an outside press and a trigger toggle close **immediately** and cancel any pending acknowledgment. A close that arrives within 100ms of `onValueChange` is treated as selection-driven. Re-picking restarts the 300ms.

### 5.4 Keyboard

Radix Select: Space/Enter/↓/↑ on the trigger opens the popup with focus on the selected item. While open, ↑/↓ move (the highlight and gated ring follow focus), Home/End and typeahead work, Enter/Space selects, and Escape closes. Typeahead on the **closed** trigger changes the value directly.

### 5.5 SwiftUI translation notes

- The trigger is a `Button` with a custom `ButtonStyle`: an HStack of icon, `Text(value ?? placeholder)` with truncation, a Spacer and a chevron, at a fixed height of 36/28 and min width 160/128. Background `hover` on `onHover`; a 1px `strokeBorder(border)` for the bordered variant.
- Do **not** use `Picker`/`NSPopUpButton`: their menus can't take this styling. Present the list in a borderless, non-activating `NSPanel` child window (`styleMask: [.borderless, .nonactivatingPanel]`, `level = .popUpMenu`, `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`, drawing the `shadow-surface-3` layers yourself in SwiftUI).
  - Position it 6px below the trigger's screen rect, left-aligned. Flip above if `visibleFrame` lacks space, and switch the scale anchor to `.bottom` and the slide to +4.
  - A panel avoids clipping by the parent window and NSScrollView bounds.
  - Close on outside click with `NSEvent.addLocalMonitorForEvents(.leftMouseDown)` plus a global monitor, and on Escape.
  - To mimic Radix Select's modality, swallow scroll-wheel events outside the panel while it is open.
- Open animation: `.scaleEffect(x: 1, y: shown ? 1 : 0.96, anchor: .top)`, `.offset(y: shown ? 0 : -4)` and `.opacity`, with `.spring(duration: 0.08, bounce: 0)` in and `.easeInOut(duration: 0.06)` out. Order the window out after the exit completes (`withAnimation(…) { } completion: { panel.orderOut(nil) }`, macOS 14+).
- Ack delay: on pick, update the value immediately (the marker springs), then `Task.sleep(300ms)` and close. Cancel that task on Escape or an outside click.
- Keyboard: make the panel's content focusable and handle `.onKeyPress` for ↑/↓/Home/End/Return/Escape. Implement typeahead with a 500ms buffer.

---

## 6. Dropdown: `dropdown__dropdown.tsx`, `menu-item.tsx`, `dropdown-sub.tsx`, `dropdown-search.tsx`

Two forms: an always-rendered **inline panel** (`Dropdown`, `role=group`) and a **popup menu** (`DropdownMenu` / `DropdownTrigger` / `DropdownContent`, Radix DropdownMenu, `modal={false}` so the page keeps scrolling and the popup tracks its anchor). Both render the same surface. Both support single (`checkedIndex`, radio items) and multiple (`checkedIndices`, checkbox items, merge/split) selection.

### 6.1 Surface

| | Popup (`DropdownContent`) | Submenu (`DropdownSubContent`) | Inline (`Dropdown`) |
|---|---|---|---|
| Width | `w-72` **288px**, `min-w-[trigger width]`, `max-w-full` | `w-56` **224px** | `w-72 max-w-full` |
| Max height | `max-h-[min(480px,var(--radix-dropdown-menu-content-available-height))]` | same | none |
| Surface / shadow / radius | section 0.1 (surface substrate+2, shadow-surface-3, 12px) | same (nested: substrate is now the parent popup's level, so +2 again) | same |
| Padding | list `p-1` | same | `p-1` on the panel itself |
| Placement | `side="bottom" align="start" sideOffset={6} alignOffset={0}` (all overridable) | Radix SubContent: reading-direction end (right), `sideOffset=6` (`SUBMENU_SIDE_OFFSET`), `alignOffset=-4` (`SUBMENU_ALIGN_OFFSET`) | static |
| Animation | section 0.2 | section 0.2 (side=right: `origin-left`, no y slide; only scaleY 0.96 and opacity) | none |

Submenu geometry: the trigger row sits inside the parent's 4px padding, and the submenu measures 6px from the row. That leaves a **2px gap between the two popup surfaces**. The −4px align offset pulls the submenu up by its own padding, so **its first row lines up exactly with the trigger row**.

### 6.2 MenuItem

Class: `"relative z-10 flex h-9|h-7 shrink-0 items-center gap-2|gap-1 rounded-lg px-2|px-1.5 cursor-pointer outline-none"`, metrics per section 0.3.

Contents, left to right:
1. **Icon** (optional; with no icon there is no reserved column). An `inline-grid` with an invisible stroke-2 copy under the visible icon. Visible icon stroke 1.5 → 2 and color `muted-foreground` → `foreground` when highlighted **or** checked.
2. **Label** (`inline-grid flex-1`, body text): an invisible semibold sizer plus the visible label.
   - Color: `muted-foreground` → `foreground` when highlighted or checked.
   - Weight: **semibold (550) when checked**, 400 otherwise. Highlight never changes weight.
   - Transitions: `css80` on color and font-variation-settings.
3. **Check** (radio or checkbox items with `checked === true`): trailing, section 0.5. In a popup with a fixed 288px width, no slot is reserved.

| Prop | Meaning |
|---|---|
| `checked: boolean` | radio item (`menuitemradio`), or checkbox item (`menuitemcheckbox`) inside a multiple dropdown |
| `checked: undefined` | plain action (`menuitem`) |
| `closeOnClick` | default `true` for single, `false` for multiple (toggling keeps the menu open) |
| `disabled` | `opacity-50 pointer-events-none`. Skipped by hover and keyboard. |

Single-select pick in a **popup** closes immediately (Radix close-on-select; there is **no** acknowledgment delay like Select). The marker spring is therefore cut short by the 0.06s exit. Multiple selection stays open, so merge/split (section 2) plays in full.

### 6.3 Overlays and highlight in the popup

- Single selection: the section 0.4 #1 marker. Multiple selection: `SelectionBackgrounds` blocks (section 2).
- Hover: `FluidHoverHighlight` with `from = litBy === "pointer" ? checkedRect : null`. `litBy` is one of:
  - `"open"`: reset on every open.
  - `"pointer"`: set by mouseenter/mousemove.
  - `"keyboard"`: set by keydown.
- **On open, the first enabled row is focused**, two rAFs after open (not for submenus, and not when a search field is mounted). Focus moves the highlight, so **a freshly opened menu shows the hover fill on its first row**, faded in where it is (`litBy = open`, so no `from`).
- When the pointer enters and picks a different row, a new session starts: the highlight fades in **at the checked row and glides to the cursor**. With no checked row it fades in at the cursor's row.
- **No focus ring in the popup**: the highlight is the focus indicator. Keyboard focus moves the hover fill, and arrowing slides it on `fast`.
- The inline panel **does** draw the focus ring (section 0.4 #3) on `:focus-visible`, and its highlight always uses `from = checkedRect`.
- Pointer-leave clears the highlight (fade 0.06s), except while a submenu is open (section 6.4).

### 6.4 Sub-menus

`DropdownSub` > `DropdownSubTrigger` (a MenuItem indexed among the parent's rows) + `DropdownSubContent` (its rows index from 0).

- Trigger row: same as a MenuItem plus a trailing **chevron-right**, icon size (16/14), in `inline-grid shrink-0` (mirrored in RTL with `rtl:-scale-x-100`). Its stroke and color follow the row's lit state: 1.5 / `muted-foreground` → 2 / `foreground` (`css80`).
- Hover-to-open, the diagonal **safe area**, → to open, ← and Escape to close: all from Radix.
- **Highlight pinning** (`useSubmenuHost`): while a submenu is open, the parent's highlight **stays on the trigger row** no matter which rows the pointer crosses on its way into the submenu. Parent mouse moves, enters and leaves are ignored, and a blur into the submenu keeps the row lit. When the submenu closes, the highlight is handed back:
  1. to the focused row (where the primitive moved focus, or the trigger after ←);
  2. else to the row under the last known pointer position (tracked by a capture-phase document `pointermove` while the submenu is open);
  3. else to nothing.

  If the whole menu is closing, the highlight is left to fade out with it.
- The parent ignores events bubbling from the portalled submenu (`isOwnEvent`), so the submenu's row 0 never lights the parent's row 0.

### 6.5 DropdownSearch (search field pinned in the popup)

Class: `"group/search sticky top-0 z-20 -mx-1 -mt-1 mb-0.5 flex shrink-0 items-center border-b border-border/60" + bg-surface-{popup level} + h-9|h-7 + gap-2|gap-1 + px-3|px-2.5`

| | D | C |
|---|---|---|
| Height | 36px (border-box, includes the 1px bottom divider) | 28px |
| Horizontal padding | 12px | 10px |
| Gap | 8px | 4px |
| Search icon | 16, stroke 1.5, `muted-foreground` → `foreground` stroke 2 on focus-within | 14 |
| Input | body text, line box `leading-6` 24px (keeps the caret proportionate) | `leading-5` 20px |

- **Sticky** at the top of the scroller. The negative margins cancel the list's 4px padding, so the field and its `border/60` divider run edge to edge. Rows scroll **underneath** it, and it paints the popup's own surface color so it hides them.
- `mb-0.5`: the first row sits **2px** below the divider. (A source comment says 4px; there is no list gap in this build.)
- While the search is mounted, the viewport's top scroll-fade is turned off.
- Placeholder `"Search…"`. Input is `rounded-none bg-transparent outline-none`, `role=searchbox`, with autocorrect and spellcheck off.
- Empty state (`DropdownEmpty`): `"px-2 py-6 text-center text-muted-foreground"` + body, `role=status aria-live=polite`.

Keyboard model (worth reproducing exactly):
- On open the query is reset (`clearOnClose`, default true) and the **field takes focus** two rAFs after open (`autoFocus`, default true). The row the primitive autofocused one frame earlier stays unlit.
- The field counts as one stop in the ring of rows. While it has focus **no row is highlighted**.
- In the field: ↓ goes to the first row, ↑ to the last row. Enter does nothing (no row to pick, and form submission is prevented). Escape closes the menu. Tab is left to the menu. Every other key stops propagation, so menu typeahead never steals it.
- On a focused row: any printable character (except Space) **refocuses the field and appends** the character. Backspace refocuses and deletes. Space still activates the row.
- Arrowing past the first or last row returns to the field, and coming back from the bottom also **scrolls the list to the top**.
- Consumers filter their own MenuItems against `value`. The list is re-indexed freely, because hover keys on the indices of whatever is mounted.

### 6.6 Keyboard (popup and inline)

- **Popup** (Radix): ↑/↓ move between enabled rows (Radix default: no wrap), Home/End, typeahead on labels, Enter/Space activate, Escape closes, → opens and ← closes a submenu.
- **Inline panel** (custom): ↑/← and ↓/→ move with **wrap**, Home/End. Roving tabindex: the tab stop is the checked row, else the first checked index, else row 0.
- Gap clicks (padding, between rows) activate the highlighted row (section 1.2).

### 6.7 SwiftUI translation notes

- Use the same `NSPanel` popup host as Select (section 5.5) with fixed width 288 and max height 480. Submenus are a **second child panel** positioned at `triggerRowScreenRect.maxX + 6`, `y = triggerRow.minY - 4` (flipped to the left edge if there is no room).
- The safe area is not built into SwiftUI. Implement it as a triangle from the pointer's last position to the submenu's near corners. While the pointer is inside that triangle and moving toward the submenu, don't switch highlight or close the submenu. Pin the parent highlight to the trigger row while the submenu is open (mirror `useSubmenuHost`).
- MenuItem: HStack of `[icon] Text(label).frame(maxWidth: .infinity, alignment: .leading) [check]` at fixed height 36/28, `.padding(.horizontal, 8)`, with `.contentShape(Rectangle())`. Weight: ZStack with a `.hidden()` semibold copy, plus `.contentTransition(.interpolate)`.
- Keyboard: route ↑/↓/Home/End/Return/Escape/→/← through `.onKeyPress` on the panel's root focusable view. For search, use a `TextField` with an `NSTextFieldDelegate`-backed representable. In `control(_:textView:doCommandBy:)`, map `moveDown:`/`moveUp:` to "focus first/last row" and `insertNewline:` to a no-op. Typing redirect: when a row has focus and `onKeyPress` receives a character, move focus to the field and append the character.
- The search header is a non-scrolling view above the ScrollView (simpler than sticky), with a 1px `border.opacity(0.6)` divider. Turn the top fade off when it is present.
- The first-row highlight on open: set `activeIndex = firstEnabled` when the panel appears (no `from`). On the first pointer pick, start a new session with `from = checkedFrame`.

---

## 7. Combobox: `combobox__combobox.tsx`

A text field that filters a list. It is built on Radix **Popover** (no combobox primitive) with its own listbox. **DOM focus never leaves the input**; rows are driven through `aria-activedescendant`. The popup visuals are the same as Select (section 0). It supports single and multiple selection (chips) and an optional "Create …" row.

### 7.1 Field (`ComboboxInput`)

| | D | C |
|---|---|---|
| Height | 36px | 28px |
| Horizontal padding | `px-2.5` **10px** | `px-2` **8px** |
| Gap | 8px | 4px |
| Min width | 160px | 128px |
| Radius | `shape.input` 8px | same |
| Input text | body; line box `leading-6` 24px | 12px, `leading-5` 20px |

Base class: `"group flex items-center ring-1 cursor-text transition-all duration-80 data-[disabled]:opacity-50 data-[disabled]:pointer-events-none"`

| Variant | Rest | Hover | Focus-within | Error |
|---|---|---|---|---|
| `bordered` (default) | `ring-border bg-transparent` | `bg-muted/50` | `bg-card` | `ring-destructive/50` on all states |
| `borderless` | `ring-transparent bg-transparent` | `bg-muted/50 ring-border` | `bg-card ring-border` | same |

`ring-1` is a 1px box-shadow ring outside the box; it is not a border and takes no layout.

Contents, left to right:
- Leading icon (optional): `muted-foreground` stroke 1.5, `foreground` stroke 2 on focus-within.
- Input: `flex-1`, placeholder `"Search…"` in `muted-foreground`.
- **Clear ✕** (`clearable`): `size-6` 24px (C `size-5` 20px), `rounded-md` 6px. `muted-foreground` → hover `foreground` + `bg-hover`, active `bg-active`. X icon at icon size, stroke 1.5. It is **hidden with `visibility` (invisible) but keeps its slot** when there is nothing to clear, so the field width never changes.
- **Chevron button**: same size, no fill (`hover:text-foreground` only), path `M6 9l6 6 6-6` stroke 2, `tabIndex -1`. Click focuses the input and toggles the list.
- A mousedown on the icon or padding focuses the input without moving the caret.
- Error text: caption, destructive, `pl-3`, 4px below.

### 7.2 Chips field (`ComboboxChips`, multiple selection)

- Frame: `!items-start`, D `min-h-9 py-1.5` (36px min height, 6px vertical padding), C `min-h-7 py-1`. One 24px (C 20px) row is vertically centered. The icon and controls sit on the first line inside a row-height box (`h-6`/`h-5`).
- **The frame height springs** (`fast`) to the measured chip-stack height plus vertical padding (12 / 8) as chips wrap and unwrap. The first measure just pins the height; later changes animate.
- Chip row: `flex flex-wrap items-center gap-1` (4px). If there is no icon and at least one chip, it gets `-ml-1` so the first chip sits an equal distance from every edge.
- **Chip**: `"inline-flex max-w-full shrink-0 items-center gap-0.5 bg-hover pl-2 pr-0.5 text-foreground"`. `rounded-md` 6px (pill mode: full). Height `h-6` 24px (C 20px). Caption type 12/16 (C 11/14). Left padding 8px, right padding 2px, gap 2px.
  - Remove ✕: `size-5` 20px (C 16px), `rounded` 4px, `hover:bg-active` + `foreground`. X glyph 12px (C 10px), stroke 2.
- Chip motion: enter `{opacity 0, scale 0.9}` → `{1, 1}` on `fast`, with **origin-x 0** (grows from its left edge, where the typed text was). Exit `{opacity 0, scale 0.9}` over `fast.exit` and becomes inert. `layout` + `mode="popLayout"`: siblings slide to their new slots immediately while the exiting chip fades out of flow.
- The typing input sizes to its content (`size = len + 1`, `min-w-6`, `flex-auto`) and **never animates**.
- Backspace in an empty input removes the last chip. Removing a chip refocuses the input.

### 7.3 Popup

Section 0 applies with: `side="bottom" align="start" sideOffset={6}`, anchored to the **whole field frame** (so the list spans from the icon to the chevron). Min width = field width. Max height `min(300px, available)`.

- Focus stays in the input (`onOpenAutoFocus` / `onCloseAutoFocus` are prevented). Pointer-down on rows is `preventDefault`, so the input never blurs. Presses on the field are not treated as "outside".
- Listbox: `"relative flex flex-col p-1 outline-none data-[empty]:p-0"`. With no matching items the padding collapses and `ComboboxEmpty` shows (`"px-3 text-center text-muted-foreground [&:not(:empty)]:py-6"` + body).
- **Highlight model**: `highlight = { index, keyboard: bool }`.
  - The **first row is highlighted the moment the list opens**, whatever opened it (click, chevron or typing), so Enter always has a target.
  - Typing sets the highlight to row 0.
  - A pointer move over a row sets a pointer highlight. Leaving the list drops a pointer highlight but **keeps** a keyboard highlight.
  - A keyboard highlight drives the hover fill (the **only** indicator; no ring) and scrolls its row into view (`block: nearest`).
- Selected: single selection uses the section 0.4 marker; multiple selection uses merge/split blocks.
- **Filter reflow snap**: when the visible row set changes (detected by the row values, not array identity), the marker, the blocks and the hover highlight **snap** (duration 0) until rects from the new row set land, then one more frame. Overlays never smear across rows on each keystroke.
- **Create row**: when `onCreate` is set and the trimmed query matches no label exactly, a last row `Create "query"` is appended (plus icon, `ComboboxItem`). Enter and the arrows reach it like any other row.
- Rows are identical to Select rows: color change, check slot, no weight change.

### 7.4 Keyboard (APG combobox)

| Key | Closed | Open |
|---|---|---|
| ↓ | open, highlight first | next row. Past the last row the highlight **clears** (the input is the stop); the next ↓ wraps to the first row. |
| ↑ | open, highlight last | previous row. Before the first row the highlight clears; the next ↑ wraps to the last row. |
| Enter | n/a | pick the highlighted row (`preventDefault`) |
| Escape | n/a | close; the **field reverts** to the selected item's label and the query clears |
| Backspace | (multiple selection, empty input) remove the last chip | same |
| Typing | opens the list, filters, highlights row 0 | same |

Pick behavior:
- Single selection: commit, field shows the label, close.
- Multiple selection, unfiltered: toggle and **stay open**.
- Multiple selection, while filtering: toggle, clear the query, close.
- Create: call `onCreate(query)` and select whatever it returns.

### 7.5 SwiftUI translation notes

- Field: an `HStack` with `.frame(height: 36)` and `.background(RoundedRectangle(8).fill(state.fill))`, plus `.overlay(RoundedRectangle(8).stroke(ring, lineWidth: 1).padding(-0.5))` to approximate an outside ring.
- Wrap `NSTextField` in a representable so arrows, Return and Escape are intercepted in `control(_:textView:doCommandBy:)` (`moveUp:`, `moveDown:`, `insertNewline:`, `cancelOperation:`). SwiftUI `TextField` with `.onKeyPress` also works on macOS 14+, but the delegate route is more reliable for Up/Down.
- Popup: the same `NSPanel` host, **non-activating**, so the main window's text field keeps first responder. This is the key requirement and why a non-activating panel beats `.popover`, which steals key status.
- Chips: use a wrapping `Layout` (flow) with `.transition(.scale(0.9, anchor: .leading).combined(with: .opacity))` and `.animation(.spring(duration: 0.08, bounce: 0))`. Animate the frame height by measuring the flow's height and applying `.frame(height:)` with the same spring.
- Snap on filter: wrap the row-set change in `withTransaction(Transaction(disablesAnimations: true))` for the overlay frames, or carry a `reflowGeneration` and use `.animation(nil, value: reflowGeneration)`.

---

## 8. CommandMenu: `command-menu__command-menu.tsx`

A palette: search field, optional tabs or filter bar, grouped scrolling list and hint footer. The input keeps focus throughout; the list is driven through `aria-activedescendant`. The modal shell (`CommandMenuDialog`) is the library Dialog.

### 8.1 Dialog shell (`CommandMenuDialog`)

| | Value |
|---|---|
| Width | `w-[calc(100%-2rem)] max-w-[540px]` (C 480px), centered with `left:50%` and `x:-50%` |
| Top | `top-[max(12dvh,calc(50dvh-220px))]`: the top edge sits where a 440px panel would be **centered**, but no higher than 12dvh. It is fixed while filtering, so the field never moves and the list shrinks from the bottom. |
| Max height | `max-h-[min(440px,76dvh)]` |
| Padding | `p-0` (the dialog's default `p-6` is overridden) |
| Surface | `bg-surface-{substrate+4} shadow-surface-{same}`: **surface-5 / shadow-surface-5** on page |
| Radius | `shape.container`: 12px (follows the global shape; pill mode 24px). The list rows keep 8px. |
| Overlay | `bg-black/40` (`dark:bg-black/80`), opacity on `slow` / `slow.exit` |
| Panel enter | `{opacity 0, scale 0.97}` → `{1, 1}` on **`slow`** (0.24s, bounce 0.12). Exit is the reverse over `slow.exit` (0.16s). |
| Close ✕ | hidden (`showCloseButton={false}`) |
| Global shortcut | `mod+k` (⌘K on Mac, Ctrl+K elsewhere; either modifier matches). It toggles, ignores repeats, and fires even inside fields because it has a modifier. If several dialogs share a combo, an open one answers first; otherwise the most recently mounted one whose `shortcutScope` contains focus. |
| Picking | closes the dialog (`closeOnSelect`, default true) |

**Panel height follows its rows**: the root measures its column (offsetHeight with a ResizeObserver) and springs the frame height to it on **`moderate`** (snaps under reduced motion). Filtering animates the panel shorter or taller instead of jumping.

### 8.2 Input row (`CommandMenuInput`)

| | D | C |
|---|---|---|
| Row | `h-12` **48px**, `px-4` 16px, `gap-2.5` 10px | `h-10` **40px**, `px-3` 12px, `gap-2` 8px |
| Search icon | 16, stroke 1.5 `muted-foreground` → stroke 2 `foreground` on focus-within | 14 |
| Input text | **subtitle 14px**, line box 24px (`leading-6`): one step above the row text, as the palette's title line | 13px, `leading-5` 20px |

Placeholder: `"Type a command or search…"`, `muted-foreground`. Input is `rounded-none bg-transparent outline-none`. IME composition keys are ignored (`isComposing` / keyCode 229).

### 8.3 Optional header rows

- **CommandMenuTabs**: `"flex shrink-0 items-center"`, D `gap-2 px-2.5 pb-2`, C `gap-1 px-2 pb-1.5`. Holds `TabsSubtle size="compact"` (28px tabs, section 4). Mousedown on the tabs is prevented so the input keeps focus. With no modifiers held, ←/→ **in the input** switch tabs (wrapping); Shift/Alt/⌘/Ctrl+arrows keep their text-editing meaning. Trailing children sit at `ml-auto`.
- **CommandMenuFilters**: `"flex shrink-0 items-center gap-1"` (4px). On its own it adds `flex-wrap` and D `px-2.5 pb-2` / C `px-2 pb-1.5`. Its children are forced to compact size, and Select triggers inside drop their min width (`[&_[role=combobox]]:w-auto min-w-0`). There is no frame; the list's divider closes the header.

### 8.4 List (`CommandMenuList`)

ScrollArea class: `"scroll-divider flex min-h-0 flex-1 flex-col border-t border-border/60 [&::before]:!-top-px [&:last-child::after]:!hidden"`. Viewport: `--scroll-fade-size: 32px`, `scroll-fade`.

- A 1px `border/60` top border separates the header from the list. The scroll-divider's top hairline sits on it, pulled up 1px, and **gets stronger** once rows scroll underneath. The bottom hairline is visible while more rows continue below and fades at the end. If the list is the last child (no footer), the bottom hairline is hidden so it doesn't double the panel edge.
- List: `"relative flex flex-col gap-1 p-1 outline-none data-[empty]:p-0"`. That is 4px padding and **4px between sections**. Rows inside a section abut.
- **Section heading**: `"flex shrink-0 items-center text-muted-foreground"`, D `h-7 px-2` (28px tall, 8px inset), C `h-6 px-1.5` (24px, 6px). Caption type (12/16, C 11/14). Headings are not hover targets: the pointer over a heading highlights the nearest row.
- Section order: the `suggestions` section (label `"Suggestions"`) comes first while the query is empty; suggested rows leave their own group. Otherwise groups keep the order of their first item.
- Filter: every whitespace-separated word must appear somewhere in label, description or keywords (case-insensitive). The original order is kept, so rows never re-sort under the cursor.
- Empty: `"px-3 py-6 text-center text-muted-foreground"` + body.

### 8.5 Row (`CommandMenuItem`)

- Class: `"relative z-10 flex shrink-0 items-center cursor-pointer select-none outline-none"`, with height 36/28, `itemPx` 8/6, gap 8/4, body text, `rounded-lg` 8px, `css80` color.
- Color: `muted-foreground` → `foreground` when highlighted. Icon stroke 1.5 → 2. **No checked state and no weight change**; `aria-selected` means highlighted.
- Label and description: `flex min-w-0 flex-1 items-baseline gap-2`. The description is the **same size** as the label, always `muted-foreground`, and each truncates on its own.
- **Shortcut caps** (`CommandMenuShortcut`): `kbd` at `ml-auto`, `inline-flex gap-0.5` (2px between caps). Each cap is `"flex items-center justify-center rounded-[5px] bg-hover text-muted-foreground"`, D `h-5 min-w-5 px-1` (20px tall, at least 20px wide, 4px horizontal padding), C `h-4 min-w-4 px-1` (16px). Micro type 11/14 (C 10/12). Modifiers render as symbols on Mac (⌘ ⌥ ⇧ ⌃ ↵ ⌫ ⌦ ⇥ ↑↓←→, `Esc`, `Space`) and as words elsewhere. Letters are uppercased, and each glyph of a pre-formatted string such as `"⌘⇧P"` gets its own cap.
- Highlight: `FluidHoverHighlight` (`bg-hover`, 8px). **No focus ring.** The pointer moves it via hover, the keyboard via `setActiveIndex`, and Enter runs whatever row it is on.
- Mousedown on the list is prevented, so a click never blurs the input. **When the pointer leaves the list, the highlight stays on the last row** (it is not cleared), so Enter still has a target.

### 8.6 Footer (`CommandMenuFooter`)

- `"flex shrink-0 items-center overflow-hidden text-muted-foreground"`, D `h-10 gap-4 px-4` (40px, 16px gaps and padding), C `h-8 gap-3 px-3` (32px, 12px). Caption type. No border of its own (the list's bottom hairline does that job).
- Default hints, each `label + caps` with a 6px gap (`gap-1.5`): `Select ↑ ↓`, then `Tabs ← →` (only when tabs are mounted), then `Close Esc` (only inside the dialog).
- At the trailing edge (`ml-auto`, `text-foreground`, truncating) is the **highlighted row's action name** (`item.action ?? item.label`, for example "Open Showcase") followed by a `↵` cap. It is right-aligned, so its changing width never shifts the other hints. With no highlighted row it is not shown.

### 8.7 Keyboard and scrolling

| Key (in input) | Action |
|---|---|
| ↓ / ↑ | next/previous **enabled** row, **wrapping** at both ends (no field stop) |
| Home / End | first/last row, **only while the query is empty** (otherwise caret movement) |
| Enter | run the highlighted row (item `onSelect`, then root `onSelect`, then close the dialog) |
| Escape | in the dialog: close. Inline: clear the query (if it is non-empty). |
| ← / → | switch tabs if CommandMenuTabs is mounted |

- When the row set changes (by values), the **first enabled row is highlighted** and the viewport snaps to the top, heading included.
- A **keyboard move keeps its row centered** in the viewport, as far as the ends allow (`target = rowTop + rowH/2 − viewportH/2`, clamped). The viewport scroll animates on **`fast`**, the same spring as the highlight, so the row and its fill arrive together. Reduced motion jumps. `scrollIntoView` is never used (it would scroll the page).

### 8.8 SwiftUI translation notes

- Dialog: an in-window overlay (a ZStack over the window content) with a `Color.black.opacity(0.4)` scrim, or a floating `NSPanel` for an app-global, Spotlight-style palette.
  - Panel `frame(maxWidth: 540)`, top offset = `max(0.12·H, 0.5·H − 220)`, `maxHeight: min(440, 0.76·H)`.
  - Enter: `.scaleEffect(0.97)` with opacity, on `.spring(duration: 0.24, bounce: 0.12)`.
  - Height-follows-content: measure the VStack's ideal height and set `.frame(height: min(measured, cap))` with `.animation(.spring(duration: 0.16, bounce: 0), value: measured)`.
- List: `ScrollViewReader` is not enough for spring-centered scrolling. On macOS 14+ use `.scrollPosition(id:anchor: .center)` inside `withAnimation(.spring(duration: 0.08, bounce: 0))`, or drive `NSScrollView.contentView.scroll(to:)` from an animated value through a representable.
- Input: an `NSTextField` representable intercepting `moveUp:` / `moveDown:` / `insertNewline:` / `cancelOperation:` / `moveLeft:` / `moveRight:`, deferring to the editor when modifiers are held. Home/End map to `moveToBeginningOfDocument:` / `moveToEndOfDocument:` only when the text is empty.
- Global ⌘K: a menu command `CommandGroup` with `.keyboardShortcut("k", modifiers: .command)`, or a local `NSEvent` monitor for a non-menu app.

---

## 9. ScrollArea (scrollbar styling): `scroll-area__scroll-area.tsx` + `scroll-area__theme.json`

Radix ScrollArea with `type="always"` (the bar is mounted whenever content overflows). **Visibility is owned by the component**, not Radix. Touch-primary devices fall back to native overflow scrolling with no custom bar.

### 9.1 Geometry

| | Vertical | Horizontal |
|---|---|---|
| Track (hit target) | `w-2.5` **10px** wide, full height, flush with the edge | `h-2.5` 10px tall, full width |
| Thumb at rest | `w-1` **4px**, `mx-auto` (centered in the track), `my-1` (4px inset at both ends), `-translate-x-0.5` (moved **2px inward**). Net: 5px gap to the container edge, 1px to the track's inner side. | `h-1` 4px, `mx-1`, `-translate-y-0.5` |
| Thumb while the track is hovered | `w-1.5` **6px** (4px gap to the edge) | `h-1.5` 6px |
| Thumb radius | `shape.bg` 8px (a full pill at this width) | same |
| Z | `z-20` above content | |

### 9.2 Colors (overlay-relative, theme independent)

| State | Thumb fill |
|---|---|
| Rest | `rgb(var(--overlay) / 0.08)` (8% black in light mode, 8% white in dark) |
| Track hovered (`group-hover/scrollbar`) | `/ 0.12` |
| Dragging (`active:`) | `/ 0.16` |

Thumb transitions: `transition-[background-color,width,height] duration-160 ease-in-out` (160ms, ease-in-out).

### 9.3 Show/hide

- Visible while the **pointer is over the scroll area** OR for **600ms after the last scroll event** (`SCROLL_LINGER_MS`).
- Show: `opacity 0 → 1` over **160ms**, no delay.
- Hide: wait **160ms** (so a hover-widened thumb visibly narrows back first), then fade over **120ms ease-out**.
- Hidden means `pointer-events-none`, so the always-mounted track never eats clicks along the edge.

Track class:
`"group/scrollbar z-20 flex touch-none select-none opacity-0 transition-opacity duration-120 ease-out delay-160 data-[visible]:opacity-100 data-[visible]:duration-160 data-[visible]:delay-0 pointer-events-none data-[visible]:pointer-events-auto h-full w-2.5"`

### 9.4 Scroll-edge fades and dividers (theme CSS)

- **`.scroll-fade`**: a mask on the viewport, `linear-gradient(to bottom, rgba(0,0,0,var(--sf-start)) 0, #000 var(--scroll-fade-size), #000 calc(100% - size), rgba(0,0,0,var(--sf-end)) 100%)`.
  - Default size **48px**; popups and the command menu use **32px**.
  - Scroll-driven: `--sf-start` goes 1 → 0 over the first `size` px of scroll, so there is no top fade at scrollTop 0 and a full fade after scrolling `size` px. `--sf-end` goes 0 → 1 over the last `size` px, so the bottom fade disappears as you reach the end.
  - Content only fades at an edge that has more content beyond it. `.scroll-fade-x` is the horizontal equivalent.
- **`.scroll-divider`**: 1px `var(--border)` hairlines at the top and bottom of a scroll region, inset by `--scroll-divider-inset` (0, or 8px in the inset sidebar). The top hairline fades in over the first 48px of scroll; the bottom one fades out over the last 48px. A `:first-child` region drops its top hairline.
- Native fallback scrollbars (pointer: fine, outside ScrollArea): 10px wide, thumb `overlay/0.08` (hover 0.12, active 0.16), transparent borders (vertical: 1px left, 5px right, 3px top/bottom) that leave a 4px pill, radius 9999px.

### 9.5 SwiftUI translation notes

- Most faithful: wrap `NSScrollView` with a custom **`NSScroller` subclass**.
  - `scrollerStyle = .overlay`. Override `class func scrollerWidth(for:scrollerStyle:)` to return 10.
  - Override `drawKnobSlot(in:highlight:)` to draw nothing.
  - Override `drawKnob()` to fill a rounded rect 4px wide (6px when hovered) at `x = bounds.maxX − 5 − w`, inset 4px top and bottom, color `overlay` at 0.08 / 0.12 / 0.16. Animate the width and color through a CADisplayLink- or timer-driven `needsDisplay`, or layer-backed sublayers with CABasicAnimation (0.16s, ease-in-out).
  - Visibility: control `alphaValue` yourself (`NSAnimationContext`, 0.16s in; 0.16s delay then 0.12s out). Trigger it from an `NSTrackingArea` on the scroll view (hover) and from `NSScrollView.didLiveScrollNotification` / `boundsDidChange` (scroll, with a 600ms linger). Disable the system's own auto-hide by keeping `autohidesScrollers = false` and managing alpha.
- Pure SwiftUI alternative (macOS 15+): `.scrollIndicators(.hidden)` with an overlay thumb positioned from `onScrollGeometryChange(for: ScrollGeometry.self)`, plus `DragGesture` on the thumb.
- Edge fades: `.mask(LinearGradient(stops: [.init(color: .black.opacity(1 - topT), location: 0), .init(color: .black, location: 32/h), …]))`, where `topT = min(offset/32, 1)` and `bottomT` is the same from the end. Use `onScrollGeometryChange` (macOS 15) or a `GeometryReader` offset probe inside the content (13/14). Dividers: 1px `Rectangle().fill(border).opacity(topT)` overlays.

---

## 10. Sidebar core: `sidebar__sidebar-core.tsx`, `sidebar__sidebar.tsx`

A shadcn-style sidebar with three variants, offcanvas collapse, a drag-resize rail, hover/click **peek**, a mobile sheet and collapsible groups. There is no icon-only collapse (`collapsible: "offcanvas" | "none"`).

### 10.1 Provider defaults

| | Value |
|---|---|
| Width | `16rem` **256px** (live; the rail drag changes it), mobile `18rem` **288px** |
| Resize clamp | **160–360px** |
| Drag-to-collapse | dragging below `160 − 56 = 104px` previews collapse; dragging back above re-expands; release commits. On collapse the width resets to 160. |
| Drag threshold | 4px before a press becomes a drag. A press with no drag is a **click → toggle**. |
| Mobile breakpoint | 768px (below it the sidebar becomes a sheet) |
| Default open | true. Persisted in the cookie `sidebar_state` for 7 days. |
| Toggle shortcut | **bare `[`** for a left sidebar, `]` for a right one. Ignored with ⌘/Ctrl/Alt held (so ⌘[ keeps its browser meaning) and while typing in an input, textarea, select or contenteditable. Nested providers: the innermost one containing focus wins; with focus outside all of them, the outermost wins. |
| Peek | `"none"` (default), `"hover"` or `"click"`. Hover intent delay **150ms**; dismiss delay **250ms**. |

### 10.2 Desktop shell (open/close)

- The outer column is `peer shrink-0 sticky top-0 h-svh`, in-flow. It **animates `width`** between `width` and `0`, which reflows the main inset. It has `overflow-hidden`, except while peek is armed or pinning from a peek (then `z-40`).
- Inside it sits a fixed-width panel (`absolute inset-y-0 … style.width = width`) that **slides `x` 0% ↔ −100%** (left; +100% for right) under the clip.
- Open: **`slow`** (0.24s, bounce 0.12). Close: `slow.exit` (0.16s tween). During a drag: duration 0, so the panel is glued to the pointer. A collapse/expand flip in the middle of a drag uses `moderate` / `moderate.exit`, held until it settles. Reduced motion snaps.
- `side="right"` uses `order-last` (flex order), so the DOM order can stay Sidebar-then-Inset.
- Crossing the mobile breakpoint **dissolves** the desktop rail: opacity fades over 160ms out / 240ms in, and `display` changes discretely after the fade.

### 10.3 Variants

| Variant | Panel | Background | Inset (main) |
|---|---|---|---|
| `sidebar` (default) | flush; `border-r border-border` (1px on the inner edge; `bordered` is on by default) | **none**: sits on the substrate (page) | `bg-background`, flush |
| `floating` | `p-2` gutter (8px); a card inside: `rounded-xl` 12px, **`bg-surface-{substrate+1}` (surface-2 on page) with `shadow-surface-3`** | card | `bg-background` |
| `inset` | `py-2` (8px top and bottom only) | none (page) | becomes a card: `m-2` (8px) with `ml-0` on the sidebar side (8px restored when collapsed), `rounded-xl` 12px (pill mode 24px), **`bg-surface-2 shadow-surface-2`**, margin `css80`. The inset variant's scroll hairlines are inset 8px. |

### 10.4 Rail (resize/collapse handle, on by default)

- `absolute inset-y-0 z-20 w-2 cursor-col-resize touch-none`: an **8px** grab strip on the inner edge (at `right-0`; for floating, `right-1` so it straddles the card edge). `tabIndex -1`.
- Hover hairline: `after:` 1px line, `after:bg-transparent` → `hover:after:bg-foreground/25`, `css80`. In the floating and inset variants the hairline is masked: transparent through the corner radius (12px; 24px in pill mode), then fading in over 24px, mirrored at the bottom.
- Tooltip: on the opposite side, `sideOffset 8`, **follows the cursor's Y**. Two lines, gap 8px: "**Drag** to resize" / "**Click** to collapse [⟦key⟧]" (the bold words are semibold). The keyboard chip is `h-4 min-w-4 px-1 rounded border border-background/30`, micro-compact 10/12, `text-background` (the tooltip surface is inverted). Hidden while dragging.

### 10.5 Peek (collapsed reveal)

- **Edge strip** (collapsed, peek enabled): `absolute inset-y-0 z-40 w-3` (**12px**) invisible button at the edge. A 1px `bg-border` hairline at the very edge fades in on hover or focus-visible (`css80`). Hover mode: a mouse pointer entering it schedules the peek (150ms). Click mode, or any click: peek immediately.
- **Peek card**: `absolute inset-y-2 z-50 flex flex-col overflow-hidden rounded-xl` + `bg-surface-{substrate+1} shadow-surface-3`.
  - Top and bottom inset 8px. Left inset 0 for `sidebar`/`inset`, 8px for `floating`, matching where the pinned content sits so pinning never shifts the rows sideways.
  - Width = `width − 8px` (248px), or `width − 16px` for floating (240px).
  - Enter: `x: −108% → 0` on **`moderate`**. Exit: back to −108% over `moderate.exit` (0.12s).
- Dismissal: Escape, a pointer-down outside the shell, or (hover mode) the pointer leaving the card's box **by more than 8px**. This is checked geometrically on document `pointermove`, not via leave events, because portalled tooltips and menus over the card fire false leaves. Re-entering cancels the 250ms dismiss timer. The edge strip, the trigger and the card share **one** timer.
- Pinning open from a peek: the column's width spring runs **without clipping**, so the already-visible card doesn't wipe in from a mask.
- Related block behaviors: `SidebarInsetTopbar` hides its trigger while peeking (it fades back with `delay-200 duration-160` after a pin). `SidebarWorkspaceHeader` cross-fades the 20px tile with a `SidebarTrigger` in the same slot while peeking (opacity only, 80ms; neither element moves).

### 10.6 Trigger, mobile sheet, sections

- **SidebarTrigger**: ghost icon Button, **36×36** (`icon`, 16px glyph) or **28×28** (`icon-compact`, 14px glyph) in compact regions. `text-muted-foreground hover:text-foreground`. Icon `panel-left` (`panel-right` for a right sidebar). Tooltip below: "Expand sidebar" / "Collapse sidebar" plus the key chip. With hover-peek enabled, resting on the **collapsed** trigger also peeks.
- **Mobile sheet** (Radix Dialog: scroll lock, focus trap, Esc, outside click):
  - Panel `fixed inset-y-0`, width 288px, `bg-surface-{substrate+2} shadow-surface-3`.
  - Slides `x: ∓100% → 0` on **`moderate`** (critically damped, so no overshoot that would expose the page edge). Exit `moderate.exit`.
  - Scrim `bg-black/40` (`dark:/80`): 0.16s in, 0.12s out.
  - The panel itself takes initial focus, so no row looks selected on open.
- **SidebarHeader** / **SidebarFooter**: `flex shrink-0 flex-col gap-2 p-2` (8px padding and gap). The footer adds `mt-auto`.
- **SidebarSeparator**: `mx-2 h-px bg-border` (8px horizontal inset, 1px).
- **SidebarContent**: a `ScrollArea` with `scroll-divider` and a `scroll-fade` viewport (48px fade). Under mobile, native overflow.
- **SidebarInput**: `h-8` **32px** (C 28px), `px-3` 12px, body text, `rounded-lg` 8px. At rest transparent with `ring-1 ring-transparent`. Hover: `bg-muted/50 ring-border`. Focus: `bg-card ring-border`. Focus-visible: ring `focus-ring`. Transitions on background and box-shadow, `css80`.
  - The `SidebarSearchField` block: search icon absolute at `left-2` (8px) on the rows' 16px icon axis, text starting at `pl-8` (32px, the rows' text axis), `pr-12`. A trailing `⌘K` micro chip at `right-2` is `opacity-0` until hover or focus-within (`css80`).

### 10.7 Groups

- **SidebarGroup**: `"relative flex w-full min-w-0 flex-col p-2"` (8px padding).
- **SidebarGroupLabel** (static): `"flex h-8 shrink-0 items-center gap-2 px-2 text-muted-foreground"`, caption type. 32px tall, 8px inset, caption 12/16 (C 11/14). Leading text truncates; element children (counts) stay as flex siblings.
- **Collapsible group** (`collapsible`): the label becomes a `button` (`aria-expanded`), `rounded-lg`, with focus-visible ring-1 `focus-ring`. Hover keeps `text-muted-foreground` (no color change). The hover cue is the chevron:
  - A **chevron-right** at icon size, stroke 1.5, inside a 24px box (`ml-auto h-6`) that **rotates 90° (points down) when open**, on `fast`.
  - While open, the box is `w-0 opacity-0` at rest and appears (`w-6 opacity-100`, **no transition**: it just appears) on header hover, focus-within, an open header action popup, or a coarse pointer. While collapsed it is always visible as the reopen cue.
  - Content collapse: measured `height` with opacity, `moderate` to open and `moderate.exit` to close. It springs **only when this group toggles**; a height change from a nested sub-menu collapsing inside it snaps, so the group doesn't chase the child with a second spring. Clipping is only on while animating (a settled open group stops clipping so 2px focus rings aren't shaved).
  - With header actions, the label reserves `28n + 6` px on the right (n = number of actions) so the chevron lands one 4px gap left of the action cluster.
- **SidebarGroupAction**: `size-6` **24px**, `rounded-lg`. Standalone it is `absolute right-3.5 top-3` (14px from the right, 12px from the top, so the box center is 26px from the sidebar's inner edge, the rows' badge/action axis). Inside **SidebarGroupActions** (`absolute right-3.5 top-2 z-10 flex h-8 items-center gap-1`) it flows in the cluster.
  - Colors: `text-muted-foreground`; hover `bg-hover text-foreground`, `css80`. The SVG is drawn at icon size, stroke 1.5, thickening to 2 on hover.

### 10.8 SwiftUI translation notes (core)

- Don't use `NavigationSplitView`: no drag clamp or collapse slop, no peek, no custom surfaces or vibrancy. Build `HStack(spacing: 0) { SidebarColumn; Inset }`.
  - **SidebarColumn**: `ZStack(alignment: .leading) { panel.frame(width: w).offset(x: open ? 0 : -w) }.frame(width: open ? w : 0, alignment: .leading).clipped()`. Animate with `.spring(duration: 0.24, bounce: 0.12)` to open and `.easeInOut(duration: 0.16)` to close.
  - During a drag, set `transaction.animation = nil` (`.transaction { if isResizing { $0.animation = nil } }`).
- Rail: `Color.clear.frame(width: 8).contentShape(Rectangle())` on the trailing edge. `.onHover` pushes and pops `NSCursor.resizeLeftRight`. Use `DragGesture(minimumDistance: 0)` with a manual 4px threshold so a click can toggle. Hairline: `Rectangle().frame(width: 1).fill(foreground.opacity(hover ? 0.25 : 0))`.
- Peek: overlay the card on the inset (`.overlay(alignment: .leading)`) with `.transition(.move(edge: .leading))`. Note `move` travels exactly 100%; to reproduce the extra 8%, use `.offset(x: shown ? 0 : -1.08 * cardWidth)` with `.spring(duration: 0.16, bounce: 0)`. For the 12px edge strip, `onHover` with a 150ms `Task` delay. Geometric dismissal: `onContinuousHover` on a window-wide transparent layer, or an `NSEvent.addLocalMonitorForEvents(.mouseMoved)` check against `cardFrame.insetBy(dx: -8, dy: -8)`, with a 250ms delay.
- Bare `[` shortcut: a local `NSEvent` keyDown monitor that skips when `NSApp.keyWindow?.firstResponder is NSTextView` or modifiers are held. Avoid menu `.keyboardShortcut("[", modifiers: [])`, because menu key equivalents can pre-empt typing.
- Collapsible group: measure the content height and animate `.frame(height: open ? h : 0, alignment: .top).clipped().opacity(open ? 1 : 0)` with `.spring(duration: 0.16, bounce: 0)` (close `.easeInOut(duration: 0.12)`). Chevron: `.rotationEffect(.degrees(open ? 90 : 0))` with `.spring(duration: 0.08, bounce: 0)`.

---

## 11. Sidebar menu: `sidebar__sidebar-menu.tsx`

**One fluid-hover scope per `SidebarMenu` tree, sub-menu rows included.** A single hover background glides continuously from a parent row into its children and back. Each level (the root rows and each sub-menu) has its own active background, so "current section" and "current page inside it" can both be lit.

### 11.1 Rows

**SidebarMenu**: `ul` with `"relative flex w-full min-w-0 flex-col select-none"`. There is no gap; rows abut.

**SidebarMenuButton**: `"peer/menu-button relative z-10 flex w-full cursor-pointer select-none items-center gap-2 pl-2 text-left outline-none disabled:opacity-50 disabled:pointer-events-none transition-[padding] duration-80 pr-[var(--row-gutter)] …"` + height + `rounded-lg`.

| Size | Height | Text |
|---|---|---|
| default | `h-8` **32px** (C `h-7` 28px) | body 13/20 (C 12/18) |
| `sm` | `h-7` 28px | body compact 12/18 |
| `lg` | `h-12` **48px** | body |

- Left padding `pl-2` 8px, gap 8px, icon 16 (C 14), radius 8px.
- Right padding = the exact **trailing gutter** (section 11.4).
- Variant `outline`: `border border-border bg-background`.

Row axes (relative to the row box): the icon center is at **16px** (8 + 16/2), the label starts at **32px** (8 + 16 + 8), and the badge/action center is at **18px** from the right edge.

| State | Label color | Weight | Icon stroke / color | Background |
|---|---|---|---|---|
| Rest | `muted-foreground` | 400 | 1.5 / muted | none |
| Hovered (or keyboard-highlighted) | `foreground` | 400 | 2 / foreground | traveling `bg-hover` |
| Active (`isActive` or `status="active"`) | `foreground` | **550** (ghost-span sizer, no layout shift) | 2 / foreground | `bg-active` (one per level) |
| Active + hovered | `foreground` | 550 | 2 | `bg-active` + `bg-hover` |
| Keyboard focus-visible | (as hovered) | | | plus a focus ring: 1px `focus-ring`, 2px outset, radius 10, `z-20` |
| Disabled | `opacity-50` | | | never lit; skipped by keyboard and gap-click |

Transitions: color, weight and stroke on `css80`.

The label's ghost and visible spans both truncate, using symmetric `pt/pb-[0.25em]` with matching negative margins so the ellipsis clip doesn't shave ascenders or descenders from the trimmed box. Leading string children form the label; element children (dots, trailing chips) follow as flex siblings.

**Status dot** (`status` / `dot`, used when there is no icon): an 8px circle (`size-2 rounded-full`) centered in an icon-sized box. Filled: `bg-muted-foreground/50`, or `bg-foreground/60` when lit. Ring: a 1px border in the same colors. `status="unread"` adds screen-reader text.

### 11.2 Overlays (traveling, per menu tree)

| Overlay | Look | Motion |
|---|---|---|
| Active background(s) | `absolute rounded-lg bg-active` | **One per active row, keyed by `levelId:occurrence`**, so the usual case of one active row per level keeps a stable key and **glides** when the selection moves within that level. Moving to a **different row**: `moderate` (opacity `fade80`). The **same row moving** (reflow from a sibling sub-tree collapsing above): **snap** (duration 0). Exit `moderate.exit`. |
| Hover background | `FluidHoverHighlight` with an explicit `rect` and `session`, `bg-hover`, 8px | Fades in at the first hovered row (new session). Slides on `fast` to a different row; **snaps** when only a reflow moved its row. |
| Focus ring | 1px `focus-ring` border, rect ±2px, radius 10, `z-20` | `fast` to a different row; snap on reflow; exit `fast.exit`. Only on `:focus-visible` of a row's **main button** (action buttons keep their own static rings). Pointer-down clears it. |

- The hook measures each row's **button**, not the `<li>`. An expanded parent `<li>` is tall, and hit-testing it would hand the sub-tree's gaps to the parent. A row registered without a button is clamped to **48px** tall.
- Rows inside a collapsed sub-tree stay registered but are **skipped** (`rowHidden`), as are disabled rows (`rowDisabled`). Toggling a sub-menu calls `refreshVisibility`, which drops a highlight left on a now-hidden row.
- **Popup freeze**: while any popup anchored in the sidebar wrapper is open (a menu button or menu action with `data-state=open` / `data-popup-open`), hover tracking **freezes** in every menu scope, so a non-modal dropdown doesn't let the rows beneath keep lighting up.
- All overlays wait for `isMeasured`.

### 11.3 Sub-menus

- **SidebarMenuSub**: `ul` with `"relative ml-[15px] flex min-w-0 flex-col border-l border-border pl-2 select-none"`, `data-state=open|closed`.
  - Geometry: 15px left margin + 1px guide line + 8px padding, plus the sub-row's own 8px padding, puts the **sub-row label at 32px**, exactly on the parent label's axis.
  - Collapse: wrapper `overflow-hidden` with measured `height` and opacity, `moderate` / `moderate.exit`. Like groups, it springs only when it toggles itself and snaps when a nested sub resizes it.
- **SidebarMenuSubButton** (an `a`): `"relative z-10 flex w-full cursor-pointer select-none items-center gap-2 pl-2 text-left outline-none"` + gutter.
  - Height `h-7` **28px** by default, `h-6` **24px** in compact or `sm`. **Same text size as parent rows** (body), unless `sm`, which uses compact body.
  - Same label, icon and active treatment as SidebarMenuButton. Active means semibold, `foreground` and its own `bg-active` at the sub level. `tabIndex` is 0 only when active.

### 11.4 Trailing controls and the gutter math

| Part | Class / geometry |
|---|---|
| **SidebarMenuBadge** | `"pointer-events-none absolute right-2 z-10 flex h-5 min-w-5 items-center justify-center px-1 tabular-nums"`, `top-1.5` (C `top-1`). A 20px box, 8px from the right, 6px from the top (center 18px from the right edge). Micro type 11/14. `muted-foreground`, becoming `foreground` + **semibold** when the row is active (`css80`). |
| **SidebarMenuAction** | `size-6` (24px), `absolute right-1.5` (6px), `top-1` (4px; `top-0.5` 2px for sub or compact rows), `rounded-lg`, `text-muted-foreground`, hover `bg-hover text-foreground`. SVG at icon size, stroke 1.5 → 2 on hover. With a badge on the row it shifts to `right-8.5` (34px). Its click stops propagation, so it doesn't trigger the row. |
| `showOnHover` | `opacity-0` until the row's **own button** is hovered or focus-visible (peer-scoped, so hovering a child sub-row doesn't light the parent's action), or until its popup is open. 80ms opacity. |
| **SidebarMenuActions** | cluster `absolute right-1.5 z-10 flex items-center gap-1` with the same top and right rules. Publishes its child count. |

The button's right padding is exact: `rowGutter(actions, badge)`.
- With no trailing controls: **8px**.
- Otherwise: `inset + runWidth + 4`, where
  - inset = 8 if there is a badge, else 6;
  - runWidth = `(badge ? 24 : 0) + (n ? 24n + 4(n−1) : 0) + (badge && n ? 4 : 0)`.
- Examples: 1 action = 34px; badge only = 36px; badge + 1 action = 64px.
- With `showOnHover` actions, the rest gutter excludes them (the label gets the room) and the padding transitions to the hover gutter on row hover, focus-within or an open action popup (`transition-[padding] duration-80`).

### 11.5 Keyboard and focus

- Only the root `SidebarMenu` binds the keys. **↓/→** go to the next and **↑/←** to the previous visible menu button or sub-button in DOM order, **wrapping**. Home/End go to the first/last. Handled keys stop propagation.
- Roving tabindex: active rows' buttons are the tab stops. With no active row, the first row is.
- Gap clicks between rows activate the highlighted row's button (section 1.2; the hook resolves a wrapper to its first control).
- `focusRing={false}`: keyboard focus moves only the hover fill (for menus that are the whole surface, such as a settings dialog's section list).

### 11.6 Sidebar-anchored dropdowns (workspace switcher, user menu)

`SIDEBAR_MENU_POPUP` = `"min-w-[240px] -ml-1 w-[calc(var(--radix-dropdown-menu-trigger-width,…)_+_10px)]"` plus item overrides `pl-2 pr-1.5 gap-2`.

- The popup is the trigger width + 10px, shifted 4px left, so each item box starts exactly at the trigger row's edge. Leading icons land on the 16px axis and labels on the 32px axis, and a trailing check aligns with the trigger's chevron.
- Workspace header: below, `sideOffset 4`. The trigger row is `pl-8` with a 20px tile at `left-1.5`, a semibold name and a chevron-down that hides below a 7rem container width.
- User footer: `side="top"`, `sideOffset 6`. A 20px avatar pulled −2px onto the icon axis, and a `chevrons-up-down` in a 24px slot pulled −2px onto the action axis.

### 11.7 SwiftUI translation notes (menu)

- One `MenuScope` view model per menu tree, holding:
  - `rows: [RowID: RowInfo(frame, levelID, isHidden, isDisabled, isActive)]`, with frames collected in a named coordinate space on the root `VStack`, **including sub-rows** (they report frames in the same named space even though they are nested);
  - `hoverIndex` and `session`;
  - `activeByLevel: [levelID: RowID]`.
- Render the overlays in a `ZStack(alignment: .topLeading)` behind the root `VStack(spacing: 0)`: per-level active rects, the hover rect and the focus ring.
- To snap rather than glide on reflow, remember each overlay's last target **row id**. If the row id changed, animate with the spring; if only the frame changed (same row), apply `Transaction(disablesAnimations: true)`. This is the key detail that stops overlays chasing rows while a sub-tree collapses above them.
- Sub-menu: `VStack` with `.padding(.leading, 8)`, `.overlay(alignment: .leading) { Rectangle().frame(width: 1).fill(border) }` and `.padding(.leading, 15)`, inside a measured-height clip.
- Trailing controls: an `.overlay(alignment: .trailing)` on the row with 24px buttons, offsets 6/8/34px, and `.opacity(showOnHover && !rowHovered ? 0 : 1)`. Animate the button's trailing padding between the rest and hover gutters with `.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.08))`.
- Keyboard: `@FocusState var focusedRow: RowID?` on the root, with `.onKeyPress(.downArrow/.rightArrow/.upArrow/.leftArrow/.home/.end)` cycling over visible, enabled rows in order.

---

## 12. Quick reference

### 12.1 Motion assignment

| Tier | Used for |
|---|---|
| `fast` 0.08 | popup open; hover highlight travel; Tabs and TabsSubtle hover pill travel; focus ring travel; chip pop and chip-field height; TabsSubtle label expand; CommandMenu keyboard scroll; sidebar group chevron rotation |
| `fast.exit` 0.06 | popup close; highlight fade-out; focus ring exit; hover pill in-place fade |
| `moderate` 0.16 | selected marker / pill travel; merge/split edges and corners; group and sub-menu expand; peek card; mobile sheet; CommandMenu panel height; hover pill return-to-selected; sidebar mid-drag flip |
| `moderate.exit` 0.12 | selected marker fade-out; merge/split block fade-out; group and sub collapse; peek exit; sheet exit |
| `slow` 0.24 b0.12 | sidebar width open; CommandMenu dialog open and overlay |
| `slow.exit` 0.16 | sidebar close; dialog close |
| `fade80` | highlight fade-in; selected pill dim (0.85 / 0.8); marker opacity |
| CSS 80ms | text color, icon stroke, font weight, row padding, hairlines, reveal-on-hover opacity |
| Fixed timers | Select ack 300ms; merge commit 310ms; split drop 240ms; merge corner delay 70–100ms; peek intent 150ms / dismiss 250ms; scroll linger 600ms; scrollbar show 160ms, hide 160ms delay + 120ms; check draw 80ms easeOut / undraw 40ms easeIn |

### 12.2 Tailwind → px used above

`h-4` 16 · `h-5` 20 · `h-6` 24 · `h-7` 28 · `h-8` 32 · `h-9` 36 · `h-10` 40 · `h-12` 48 · `w-56` 224 · `w-72` 288 · `w-2` 8 · `w-2.5` 10 · `w-3` 12 · `p-0.5` 2 · `p-1` 4 · `py-1.5` 6 · `p-2` 8 · `px-2.5` 10 · `px-3` 12 · `px-4` 16 · `py-6` 24 · `gap-0.5` 2 · `gap-1` 4 · `gap-1.5` 6 · `gap-2` 8 · `gap-2.5` 10 · `gap-3` 12 · `gap-4` 16 · `right-1.5` 6 · `right-2` 8 · `right-3.5` 14 · `right-8.5` 34 · `top-0.5` 2 · `top-1` 4 · `top-1.5` 6 · `top-2` 8 · `top-3` 12 · `rounded` 4 · `rounded-[5px]` 5 · `rounded-md` 6 · `rounded-lg` 8 · `rounded-[10px]` 10 · `rounded-xl` 12 · `rounded-2xl` 16 · `rounded-3xl` 24 · `leading-5` 20 · `leading-6` 24 · `16rem` 256 · `18rem` 288.

### 12.3 Text-box trim note (applies everywhere)

Labels use `[text-box:trim-both_cap_alphabetic]`: the line box is trimmed to cap height above and the baseline below, so a label in a fixed-height row is centered on its **cap height**, not its line box. SwiftUI centers on the line box (ascent and descent), which sits about 0.5–1px high for Latin text at 12–14pt. To match, align on the cap center: `.alignmentGuide(VerticalAlignment.center) { d in d[.firstTextBaseline] - capHeight / 2 }`, with `capHeight` from `NSFont.capHeight`. Alternatively apply a measured `.offset(y:)` once per type role.
