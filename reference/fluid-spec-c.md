# Fluid Functionalism → SwiftUI: spec C

Covers CheckboxGroup, RadioGroup, Accordion, Dialog, the Settings dialog block, InputGroup, InputCopy, ColorPicker (panel + popover), Table, AskUserQuestions, ChatMessage, FileThumbnail, InputMessage, and QueuedStack.

Source: `reference/fluid-registry/src/` (Radix variants; I checked the `base_*` Base UI variants and they use the same class strings and motion). Measurements are in CSS px, which equal macOS points. All dimensions assume shape **rounded** and size **default**; compact values are given as `default / compact`.

---

## 0. Shared conventions used by every component below

### 0.1 Tokens referenced here that aren't in your foundations list

| Token | Value / use |
|---|---|
| `focus-ring` | `#6B97FF` in both themes (dark doesn't redefine it). Every custom focus ring uses it. |
| `accent` | shadcn base token. The registry doesn't define it, so the app supplies it. The shadcn neutral default is `#F5F5F5` light / `#262626` dark (assumed). Used as a **tint**: Accordion open fill (`bg-accent/20`, dark `/12`), Table rules (`border-accent/40`), the user chat bubble (`color-mix(in oklab, accent, background 45%)` = 55% accent), the queued card (`color-mix(... background 68%)` = 32% accent), the FileThumbnail placeholder (`bg-accent`), the slider hover preview (`accent 40%`). |
| `card` | shadcn base. Default `#FFFFFF` / `#171717`. Used for a focused InputGroup field, the AskUserQuestions card, and the "type here" hint. |
| `muted` | shadcn base. Default `#F5F5F5` / `#262626`. Used for InputGroup hover (`bg-muted/50`) and the queued row fill. |
| `background` | shadcn base. Default `#FFFFFF` / `#0A0A0A`. Used for the swatch ring gap, the Tab keycap fill, and inverted chip text. |
| `destructive` | shadcn base. Default ≈ `#E7000B` / `#FF6467`. |
| `destructive-light` | `#FEF2F2` / `#450A0A` (tokens theme). |
| `overlay` | RGB triplet: `0 0 0` light / `255 255 255` dark. Written as `rgb(var(--overlay)/0.03)` = 3% black or 3% white. |
| `neutral-400` / `neutral-500` / `neutral-900` | `#A3A3A3` / `#737373` / `#171717` (Tailwind). |
| `checker-a` / `checker-b` | `#BBBBBB` / `#FFFFFF` light; `#1F1F1F` / `#2A2A2A` dark (color-picker theme). |
| `shadow-color` | `rgb(0 0 0 / 0.06)` light. |

### 0.2 Timing defaults that aren't spring tiers
- Tailwind `transition-*` with `duration-80` uses 80 ms and Tailwind v4's default curve `cubic-bezier(0.4, 0, 0.2, 1)`. `transition-colors` with no duration is 150 ms on the same curve. `duration-150` is 150 ms, `duration-100` is 100 ms.
- A Motion transition with only `{ duration: X }` (no `type`) is a tween with Motion's default ease `easeInOut` = `cubic-bezier(0.42, 0, 0.58, 1)`. All the `opacity: { duration: 0.08 }` sub-transitions and `spring.*.exit` tweens use this curve.
- `animate-spin` rotates linearly at 1 turn per second, forever.

### 0.3 Lucide stroke widths as rendered
Icons are Lucide (viewBox 24) and their stroke scales with size. Rendered stroke = `strokeWidth × size / 24`.
- 16 px icon at stroke 1.5 renders **1.0 px**; at stroke 2, **1.33 px**.
- 14 px icon at stroke 1.5 renders **0.875 px**; at stroke 2, **1.17 px**.

For SF Symbols, treat stroke 1.5 as `.regular` and stroke 2 as `.medium`/`.semibold`. Hover/active transitions animate the stroke over 80 ms. For custom-drawn glyphs, use the rendered px values.

### 0.4 The row-list scaffold
CheckboxGroup, RadioGroup, the Accordion group, the ColorPicker format menu, AskUserQuestions and Table all share this structure. One `relative` container holds the rows. Every overlay is an absolutely positioned layer placed from rects measured relative to the container. Paint order, bottom to top:
1. **Selection layer:** `bg-active`. RadioGroup has one block; CheckboxGroup and AskUserQuestions use merge/split blocks.
2. **Hover highlight:** `FluidHoverHighlight`, `bg-hover`, radius 8, springs to the active row on `spring.fast` and fades opacity over 0.08 s. A new pointer session fades in at the target instead of sliding. **AskUserQuestions reverses layers 1 and 2** (selection paints *above* hover).
3. **Focus ring:** class `absolute rounded-[10px] pointer-events-none z-20 border border-[color:var(--focus-ring,#6B97FF)]`. Rect is `left−2, top−2, width+4, height+4`, so a 1 px stroke sits 1 px outside the row edge, radius 10 (row radius + 2). It moves on `spring.fast`, opacity 0.08 s; the exit fades opacity on `spring.fast.exit` (0.06 s). It shows **only for keyboard focus**. A pointer press focuses the row programmatically and sets `pointerFocusRedirect`, so no ring is drawn.
4. **Rows:** `relative z-10`, transparent.

**Focus drives hover.** Focusing a row sets `activeIndex`, so the hover highlight, label color and border darkening follow the keyboard too. Blur clears both, but only when focus leaves the whole container.

**Gap clicks.** A click in a gap between rows is forwarded to the highlighted row as a real click (foundation behavior).

**Dual-layer label (weight change with no reflow).** An inline-grid holds two copies of the label in the same cell. One is `invisible` and always semibold (550) to reserve width; the other is visible and switches 400 ↔ 550 with color over 80 ms. Labels also use `[text-box:trim-both_cap_alphabetic]`, which trims the line box to cap-height-to-baseline so the text centers optically in a fixed-height row. In SwiftUI, center the text vertically.

**Mouse-down redirect.** `onMouseDown` on a row calls `preventDefault()` and focuses the row itself, never an inner hidden primitive. This keeps arrow-key navigation alive. Genuinely interactive children (input, textarea, button) are skipped.

**SwiftUI scaffold (shared by every list below).**
- Rows in a `VStack(spacing: 0)` inside a container with `.coordinateSpace(.named("list"))`.
- Each row publishes its frame through a `PreferenceKey` (or `onGeometryChange(for: CGRect.self)` on macOS 14+).
- Overlays live in `.background { ZStack { selection; hover } }` and `.overlay { focusRing }`, positioned with `.frame(width:height:).offset(x:y:)` from the stored rects.
- Animate rect changes with explicit `withAnimation` per state change, not blanket `.animation` modifiers, so the per-layer tiers stay distinct.
- Hover-nearest: `.onContinuousHover(coordinateSpace: .named("list"))`.
- Keyboard focus: `@FocusState` on rows plus `.focusable()` and `.focusEffectDisabled()` (hides the system ring).
- Keyboard-vs-pointer modality: set a flag in a `simultaneousGesture(DragGesture(minimumDistance: 0))` or an `NSEvent` local monitor for `.leftMouseDown`, and clear it on the next `.keyDown`.

---

## 1. CheckboxGroup

Source: `checkbox-group__checkbox-group.tsx`, `use-merge-split__use-merge-split.tsx`

### Structure and sizes
- **Container:** `"relative flex flex-col w-72 max-w-full select-none"` with `role="group"`. Width **288**; rows stack with no gap.
- **Size prop:** `size?: "default" | "compact"` pins every row.
- **Row:** `` `relative z-10 flex ${control} items-center ${gap} ${shape.item} ${px} cursor-pointer outline-none` ``

| | default | compact |
|---|---|---|
| Row height (`h-9` / `h-7`) | 36 | 28 |
| Horizontal padding (`px-3` / `px-2.5`, the control padding, not item padding) | 12 | 10 |
| Box-to-label gap (`gap-2` / `gap-1`) | 8 | 4 |
| Row radius | 8 | 8 |
| Box | 16×16 | 14×14 |
| Box radius (`rounded-[5px]` / `rounded-[4px]`) | 5 | 4 |
| Box border | 1.5 | 1.5 |
| Check SVG (centered on box, overhangs 1 px per side) | 18×18 | 16×16 |
| Label type | body 13/20 | 12/18 |

### Box border by state
Class: `"absolute inset-0 border-solid transition-all duration-80"`.
- **Unchecked, rest:** `border-[1.5px] border-border`
- **Unchecked, active** (hover-nearest or focused): `border-neutral-400` (#A3A3A3) light, `dark:border-neutral-500` (#737373) dark
- **Checked:** `border-transparent`. The check alone marks the state; there is **no filled box**.
- The border color transitions over 80 ms.

### Check mark
- Path `M6 12L10 16L18 8`, viewBox 24, `strokeWidth={2}` (renders 1.5 px at 18, 1.33 px at 16), round caps and joins, color `text-foreground`.
- In 18-px space the points are (4.5, 9) → (7.5, 12) → (13.5, 6).
- **Animation (pathLength draw):** on check, 0 → 1 over **0.08 s easeOut**. On uncheck, 1 → 0 over **0.04 s easeIn**, then unmount.
- `AnimatePresence initial={false}`: rows checked at mount show the finished check without drawing.

### Label
- Color: `text-foreground` when checked **or** active; otherwise `text-muted-foreground`.
- Weight: **550 only when checked**, 400 otherwise. Weight marks state; color marks hover/focus/state.
- `transition-[color,font-variation-settings] duration-80`

### Layers
Paint order (§0.4): `SelectionBackgrounds` (bg-active) → hover highlight (`bg-hover`, radius 8) → focus ring → rows. **Hover paints above selection**, so a hovered checked row shows active + hover stacked.

### Selected backgrounds: runs, grow and shrink
- Contiguous checked indices form **runs**, each with a stable id. A run reuses the id of its first row that belonged to a run last render, unless an earlier run already claimed that id. After a split, the upper run keeps the id and the lower run gets a new one.
- Each run is one `bg-active` block covering `rect(firstRow) ∪ rect(lastRow)`. Corner radius `R = shape.mergedRadius` = **8** (rounded) / 16 (pill). Corners animate per corner (tl, tr, br, bl).
- **Growing or shrinking a run** (checking or unchecking a row at a run's end): the block keeps its key and springs top/height on **spring.moderate** (0.16 s, critically damped). Corners stay R.
- **A new isolated run** mounts with `initial={false}`: **no fade, no grow**. The block appears at full opacity while the check draws over 80 ms.
- **Removing a run** (unchecking an isolated row): opacity fades to 0 over **0.12 s** (`spring.moderate.exit`).
- Block transition: `{...spring.moderate, opacity: {duration: 0.08}}`, plus corner transitions as below.

### Merge (one unchecked row bridging two runs gets checked)
- **Survivor** is the upper run's block, drawn as the top half: its height springs so the bottom edge reaches `midY` (vertical center of the bridging row). Radii go to `[R, R, 0, 0]`.
- **Absorbed** is the lower run's block, which keeps its key and becomes a "ghost" bottom half: its top springs up to `midY`, height `bottom − midY`. Radii go to `[0, 0, R, R]`.
- Edges move on spring.moderate. The four corner radii use the same spring with a **delay**: `min(0.10, max(0.07, 0.07 + (midY / rowHeight) × 0.002))` s, i.e. about 0.07 s plus 2 ms per row index, capped at 0.10 s. The facing corners stay rounded until the halves almost meet.
- **Commit** at `(0.16 + 0.07) × 1000 + 80` = **310 ms** (timer, not animation callback):
  - The survivor jumps instantly (`duration: 0`) to the full union with radii `[R, R, R, R]`.
  - The ghost is held for one render at opacity 0 (instant), then removed with an instant exit.
  - There is no visible motion at the swap.

### Split (unchecking a middle row of a run)
- **Frame 1:** both halves are pinned at the seam instantly. The upper block spans top → `midY` with `[R, R, 0, 0]`. The new lower block mounts spanning `midY` → bottom with `[0, 0, R, R]`. The result is visually identical to the old single block.
- **Next frame** (rAF): both spring on spring.moderate to their real rects. The upper bottom edge goes `midY` → the top of the unchecked row; the lower top edge goes `midY` → that row's bottom. All corners re-round 0 → R on the same spring with **no delay**.
- The boundary is dropped at `160 + 80` = **240 ms**.

### Interrupts
- A boundary invalidated by a new toggle (e.g. the bridge row toggled again mid-flight) is cancelled and its timer cleared. Geometry is recomputed from live runs each render, so rapid toggles redirect rather than freeze.
- A synchronous "split safety net" pins the halves at the seam on the very first render of a split.

### Keyboard and accessibility
- Each row is its own tab stop (`tabIndex 0`) with `role="checkbox"`, `aria-checked` and `aria-label`. The inner Radix primitive is `aria-hidden` with `tabIndex -1`.
- ↑ / ↓ move focus only, wrapping at both ends. Home / End jump to first / last. Space or Enter toggles.
- Click toggles; a click on the square doesn't double-toggle.
- State is parent-owned: the group takes `checkedIndices: Set<number>`; items take `checked` and `onToggle`.

### SwiftUI translation notes
- **Layout:** follow the §0.4 scaffold. Rows are `HStack(spacing: 8) { box; label }.padding(.horizontal, 12).frame(height: 36)` with `.contentShape(Rectangle())`. Box: `RoundedRectangle(cornerRadius: 5).strokeBorder(color, lineWidth: 1.5)`.
- **Check mark:** a custom `Shape` for the 3-point path in an 18×18 frame centered on the box, with `.trim(from: 0, to: progress)` and `StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)`. Animate `progress` with `.easeOut(duration: 0.08)` on check and `.easeIn(duration: 0.04)` on uncheck.
- **Selection blocks:** derive runs and ids in a view model, port `assignRunIds` verbatim. Render `ForEach(blocks, id: \.key)` of `UnevenRoundedRectangle(cornerRadii: .init(topLeading:bottomLeading:bottomTrailing:topTrailing:))`; the radii are animatable.
- **Delayed corners:** use two animation scopes. Frame changes take `.spring(duration: 0.16, bounce: 0)`. Radii take `.animation(.spring(duration: 0.16, bounce: 0).delay(d), value: radii)` (or the macOS 14+ `.animation(_:body:)` scoped modifier).
- **Merge/split state machine:** port the phases `converge → commit` and `splitIn → diverge` with `Task.sleep` timers (310 / 240 ms). `splitIn → diverge` happens on the next runloop tick (`DispatchQueue.main.async`). Phase changes that must be instant use `withTransaction(Transaction(animation: nil))`.
- **Label:** `ZStack { Text(label).fontWeight(semibold).hidden(); Text(label).fontWeight(checked ? semibold : regular) }`. Weight 550 needs the Inter variable `wght` axis via `CTFontDescriptor` variation attributes.
- **Accessibility:** `.accessibilityElement(children: .ignore)`, `.accessibilityLabel(label)`, `.accessibilityAddTraits(.isToggle)` (macOS 14), `.accessibilityValue(checked ? "checked" : "unchecked")`, `.accessibilityAction(.default) { onToggle() }`.
- **Keys:** `.onKeyPress(.upArrow/.downArrow/.home/.end/.space/.return)` on the container (macOS 14+).

---

## 2. RadioGroup

Source: `radio-group__radio-group.tsx`

### Structure and sizes
- Same container and row metrics as CheckboxGroup: `w-72`, row `h-9 / h-7`, `px-3 / px-2.5`, `gap-2 / gap-1`, radius 8, label body 13/20 or 12/18. `role="radiogroup"`.
- **Selection APIs:** `value` + `onValueChange` (string), `selectedIndex`, or per-item `selected` + `onSelect`.

### Circle and dot
- **Circle:** 16×16 / 14×14, `rounded-full`, border 1.5 px. Same border color logic as the checkbox: `border-border` at rest, `neutral-400` / dark `neutral-500` when active, `border-transparent` when selected. 80 ms transition.
- **Dot:** `"rounded-full bg-foreground"`, **8×8 / 7×7**, centered.
  - Enter: opacity 0 → 1 and scale 0.3 → 1 on **spring.fast**.
  - Exit: opacity 0, scale 0.3, **0.04 s** tween.
  - `initial={false}`: no pop on mount.
- **Label:** foreground when selected or active, else muted. Weight 550 only when selected. 80 ms.

### Selected background (single shared block)
- Class: `` `absolute ${shape.bg} bg-active pointer-events-none` ``, radius 8.
- When selection changes, the block **springs** top/left/width/height from the old row to the new one on **spring.moderate**; opacity uses 0.08 s.
- `initial={false}`: the block is placed without animating on first render.
- It is **not** inside AnimatePresence, so going from no selection to a selection pops the block in instantly, and clearing the selection removes it instantly.
- Paint order: selected block → hover highlight → focus ring (`spring.fast`) → rows.

### Keyboard and accessibility
- **Roving tabindex:** the selected row has `tabIndex 0`. With no selection, row 0 gets it. All other rows are −1.
- **All four arrows move focus and select** (↓ / → next, ↑ / ← previous), wrapping, as native radios do. Selection goes through the row's click handler.
- Home / End select the first / last row. Space / Enter select.
- Row: `role="radio"`, `aria-checked`, `aria-label`. In value mode a hidden Radix `RadioGroup.Item` (`sr-only`, `aria-hidden`, `tabIndex -1`) carries form semantics.

### SwiftUI translation notes
- Reuse the CheckboxGroup row view and swap the glyph: `ZStack { Circle().strokeBorder(color, lineWidth: 1.5); if selected { Circle().fill(.foreground).frame(width: 8, height: 8).transition(.scale(0.3).combined(with: .opacity)) } }`.
- Insertion animates with `.spring(duration: 0.08, bounce: 0)`; removal with `.easeInOut(duration: 0.04)` via `.transition(.asymmetric(...))` plus explicit animations.
- **Selected block:** one `RoundedRectangle(cornerRadius: 8).fill(active)` whose frame/offset come from `rects[selected]`. Animate with `.spring(duration: 0.16, bounce: 0)`. Skip the animation when going nil → value (use a nil-animation transaction).
- **Accessibility:** `.accessibilityAddTraits(.isButton)` plus `.accessibilityValue(selected ? "selected" : "")`, or wrap the rows in a container with `.accessibilityRepresentation { Picker(...) }` for native radio semantics.

---

## 3. Accordion (Accordion, AccordionGroup, AccordionItem, AccordionTrigger, AccordionContent)

Source: `accordion__accordion.tsx`

### Variants
- **`Accordion`** (standalone): no fluid hover. Each trigger has its own hover fill.
- **`AccordionGroup`**: one fluid-hover scope across the triggers, a shared focus ring, and measured "open item" backgrounds.
- **`type`:** `"single"` (default; `collapsible` defaults to `true`) or `"multiple"`. Values are controlled or uncontrolled.
- **`highlight`:** `"item"` (default) tints the open row **and** its panel as one block, persistently. `"trigger"` tints only the trigger row, and only while that open row is hovered or focused.
- **`size`:** default / compact.
- Container: `"relative flex flex-col w-72 max-w-full"`, width **288**, no gap between items.

### Trigger
Class: `` `relative z-10 flex items-center ${gap} rounded-lg ${px} ${compact ? "py-1" : "py-2"} w-full cursor-pointer outline-none select-none` ``

| | default | compact |
|---|---|---|
| Height (body line + vertical padding) | **36** (20 + 8 + 8) | **26** (18 + 4 + 4; not 28) |
| Horizontal padding | 12 | 10 |
| Gap | 8 | 4 |
| Radius | 8 | 8 |

- **Label:** `"inline-grid flex-1 text-left"`, body type, dual-layer. Color is foreground when **open or active**, else muted. Weight 550 when **open**, else 400. 80 ms.
- **Chevron:** Lucide `chevron-right`, size **16 / 14**, trailing.
  - Stroke 1.5 → 2 when open or active (`transition-[color,stroke-width] duration-80`); color muted → foreground.
  - Wrapper rotates **0° → 90°** (points down) on **spring.fast** when open.
- **Standalone focus:** `focus-visible:ring-1 ring-[#6B97FF]`, a 1 px outer ring on the trigger. Grouped mode uses the shared springing ring (§0.4).

### Content (height animation)
- Panel: `motion.div` with `overflow-hidden`. Its height animates between 0 and a **measured px height** (ResizeObserver on the inner div), never `auto`.
- **Open:** height on **spring.fast** (0.08 s, bounce 0); opacity 0 → 1 over **0.06 s**.
- **Close:** height on **0.06 s tween** (`spring.fast.exit`); opacity 1 → 0 over **0.04 s**. Opacity leads the height so the body dissolves rather than being sliced.
- The height springs **only when this panel toggles**. Content-size changes underneath (nested collapsibles) and the mount hand-off snap (`duration: 0`). Reduced motion uses `duration: 0`.
- After close completes the panel is `hidden` (out of layout and the accessibility tree). It un-hides in the same render that opens it.
- **Inner:** `"pt-1 text-muted-foreground" + px + body + (compact ? "pb-2.5" : "pb-3")`. Padding top 4, left/right 12 / 10, bottom **12 / 10**. Text muted body 13/20.

### Group backgrounds
- **Open-item fill:** `` `absolute rounded-lg bg-accent/20 dark:bg-accent/12 pointer-events-none` `` (accent at 20% light, 12% dark), radius 8.
  - Covers the full open item (trigger + panel), measured via offset rects.
  - Geometry **snaps** (`duration: 0`) and is re-measured on every animation frame (`onUpdate`), so it hugs the animating height.
  - Opacity fades 0 → 1 over **0.12 s**.
  - While the pointer is on a **non-open** trigger, open fills dim to **0.7** (0.12 s).
  - Exit: opacity 0 over 0.12 s (`spring.moderate.exit`).
  - In `highlight="trigger"` mode the fill uses the trigger rect and exists only while that open trigger is the active index.
- **Hover highlight:** `bg-hover`, radius 8, on triggers only, `spring.fast`. While the pointer is over an expanded **content** area the highlight is suppressed (`activeIndex = null`).
- **Focus ring:** shared ring (§0.4), triggers only.
- Paint order: open fills → hover → focus ring → items.

### Standalone item backgrounds
- `highlight="item"`: an `absolute inset-0 rounded-lg bg-accent/20 dark:bg-accent/12` on the item, fading in 0.12 s and out 0.12 s.
- Per-trigger hover: `absolute inset-0 rounded-lg bg-hover`, opacity fades in **0.08 s** and out **0.06 s**. This is not fluid.
- `highlight="trigger"`: an accent tint over the trigger only, while open **and** hovered.

### Keyboard and accessibility (Radix Accordion)
- Triggers are buttons with `aria-expanded` and `aria-controls`; the content is `role="region"`.
- Tab moves between triggers. Space / Enter toggle. ↑ / ↓ move between triggers; Home / End go to first / last.
- `disabled` items are skipped.

### SwiftUI translation notes
- Don't use `DisclosureGroup`; its macOS chrome can't be restyled. Build `VStack(spacing: 0) { ForEach(items) { item in VStack(spacing: 0) { trigger; content } } }`.
- **Content:** `content.fixedSize(horizontal: false, vertical: true).onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured = $0 }`, wrapped in `.frame(height: isOpen ? measured : 0, alignment: .top).clipped().opacity(isOpen ? 1 : 0)`.
- **Animations:**
  - Open: `withAnimation(.spring(duration: 0.08, bounce: 0))` for height, plus a separate `.easeInOut(duration: 0.06)` for opacity using `.animation(_:value:)` on the opacity modifier.
  - Close: `.easeInOut(duration: 0.06)` for height and `0.04` for opacity.
  - Changes to `measured` that aren't toggles must use a nil-animation transaction.
- **Chevron:** `Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0))` with the spring.fast animation.
- **Group fills:** the open-item rect is the union of the trigger frame and the clipped content frame, both in the list coordinate space. Because SwiftUI animates layout, the fill tracks the animating height if it's laid out *in* the item's background (`.background(alignment: .top) { RoundedRectangle(8).fill(accent.opacity(0.2)) }`) rather than as an absolute overlay. That's simpler than per-frame remeasurement.
- **Hover suppression:** in `onContinuousHover`, test whether the point is inside any open content rect.
- **Accessibility:** `.accessibilityAddTraits(.isButton)` with `.accessibilityValue(isOpen ? "expanded" : "collapsed")`.

---

## 4. Dialog

Source: `dialog__dialog.tsx`

### Parts
`Dialog`, `DialogTrigger`, `DialogContent`, `DialogHeader`, `DialogFooter`, `DialogTitle`, `DialogDescription`, `DialogClose`.

### Content sizes and position
Width: `w-[calc(100%-2rem)]` (viewport − 32), capped by the size's max width.

| `size` | Max width, default | Max width, compact |
|---|---|---|
| `sm` (default) | **400** | **360** |
| `lg` | **540** | **480** |
| `xl` | **880** | **800** |

- Compact narrows the width only; padding is unchanged.
- **Padding:** `p-6` = **24** all sides. **Radius:** `rounded-xl` = **12** (shape.container).
- **Surface:** `surfaceClasses(min(substrate + 4, 8))`, both background and shadow. A dialog over surface-1 is **surface-5 + shadow-5**. Descendants are re-provided that level, so nested popovers stack above it.
- **Position:** `fixed left-1/2 z-50`.
  - `position="center"` (default): `top-1/2`, translate (−50%, −50%).
  - `position="top"`: `top-[12dvh]` (12% of viewport height), translate (−50%, 0), so the top edge stays still while the height changes.
- `focus:outline-none` on the panel.
- With a `container` prop, the overlay and panel are `absolute` inside that element (scoped dialog).

### Overlay
- `"fixed inset-0 z-50 bg-black/40 dark:bg-black/80"`: black at **40%** (light) / **80%** (dark).

### Motion
- **Overlay:** opacity 0 → 1 on **spring.slow** (0.24 s, bounce 0.12). Exit: opacity → 0 on **spring.slow.exit** (0.16 s tween).
- **Panel:** opacity 0 → 1 and **scale 0.97 → 1** on spring.slow, from the center origin. Exit: opacity 0, scale 0.97, on the 0.16 s tween.
- Content stays mounted until the exit finishes (`onAnimationComplete`), with a fallback unmount at `160 + 100` = **260 ms**.

### Header, footer, title, description
- `DialogHeader`: `"flex flex-col gap-1.5 mb-4"`, gap 6, margin-bottom 16.
- `DialogFooter`: `"flex justify-end gap-2 mt-6"`, right-aligned, gap 8, margin-top 24.
- `DialogTitle`: title role **16/22** (compact 15/20), `text-foreground`, weight **550**.
- `DialogDescription`: body **13/20** (compact 12/18), `text-muted-foreground`.

### Close button
- `Button variant="ghost" size="icon-sm"` (= `icon-compact`) at `"absolute right-3 top-3"`, 12 px from the top-right.
- **28×28**, radius 8, X icon **14 px**. Stroke 1.5 → 2 on hover (80 ms).
- Text `muted-foreground` → `foreground` on hover. Fill `bg-hover` on hover, `bg-active` on press.
- **Ghost press effect:** the background layer sits inset 1 px. A same-color 1 px spread fills it back out; pressing collapses the spread so the surface shrinks 1 px per side. The box-shadow uses 180 ms `cubic-bezier(0.23, 1, 0.32, 1)` on release and 80 ms on press.
- Screen-reader text "Close". Hide with `showCloseButton={false}`.

### Behavior (Radix Dialog, modal)
- Focus is trapped and moves into the content on open; it returns to the trigger on close.
- Esc closes; a pointer-down outside closes; body scroll is locked; `aria-modal`.
- The panel is labelled by the title and described by the description.

### SwiftUI translation notes
- Don't use `.sheet`: macOS sheets slide from the titlebar with system chrome.
- Build an in-window overlay at the root: `ZStack { app; if presented { Color.black.opacity(isDark ? 0.8 : 0.4).ignoresSafeArea().onTapGesture { dismiss() }.transition(.opacity); panel.transition(.scale(scale: 0.97).combined(with: .opacity)) } }`.
- Present with `withAnimation(.spring(duration: 0.24, bounce: 0.12))`; dismiss with `.easeInOut(duration: 0.16)`.
- **Panel:** `.padding(24).frame(maxWidth: min(windowWidth - 32, 400)).background(surface(level), in: .rect(cornerRadius: 12)).shadow(...)` using your layered shadow-N.
- **Modality:**
  - Underlying content gets `.allowsHitTesting(false)` and `.accessibilityHidden(true)`.
  - Trap focus with `.focusScope(ns)` plus `.prefersDefaultFocus(in:)`, and `.onKeyPress(.escape)` or `.onExitCommand` to close.
  - Alternatively, host the panel in a borderless child `NSPanel` for true key-window modality.
- **Close button:** the shared ghost-icon Button at `.overlay(alignment: .topTrailing) { CloseButton().padding(12) }`.

---

## 5. Settings dialog block

Source: `dialog-sidebar__settings-dialog.tsx`

### Shell
- `DialogContent size="xl"` with `className="flex h-[min(640px,calc(100dvh-4rem))] overflow-hidden p-0"`.
- **880 wide (800 compact), height `min(640, viewportHeight − 64)`, no padding, clipped to the 12 px radius.** Horizontal flex.

### Sidebar
`SidebarProvider persist={false} shortcut={null} width="13rem"`, `Sidebar collapsible="none"`.
- **Width 208**, full height.
- Background `bg-[rgb(var(--overlay)/0.03)]`: black 3% (light) / white 3% (dark) over the dialog surface.
- Right border `border-r border-border`, 1 px.
- Hidden below 640 px viewport (`hidden sm:flex`).
- **SidebarHeader:** `"px-4 pt-5 pb-2"` (overrides `p-2`, keeps `flex flex-col gap-2`): left/right 16, top 20, bottom 8. Holds `DialogTitle` "Settings" at title role **16/22, weight 400** (deliberately normal), foreground. `DialogDescription` is sr-only.
- **SidebarContent:** a ScrollArea filling the remaining height.
- **SidebarGroup:** `p-2` (8).
- **SidebarGroupLabel** "Workspace": `"flex h-8 shrink-0 items-center gap-2 px-2 text-muted-foreground"`, caption 12/16. Height 32, padding 8.
- **SidebarMenu `focusRing={false}`:** keyboard focus moves the highlight with no ring.
- **SidebarMenuButton** rows: height **32** (`h-8`; compact 28), icon 16. Stroke 1.5 → 2 and color muted → foreground when lit (active or hovered). Active row is `isActive` (the Sidebar spec covers the row fill and hover).
- Five sections: General (settings), Notifications (bell), Appearance (palette), Security (shield), Members (users).

### Panel
`"flex min-w-0 flex-1 flex-col"`.
- **Header:** `"flex shrink-0 flex-col gap-1 px-6 pt-5 pb-4 pr-12"`. Left 24, **right 48** (clears the ✕), top 20, bottom 16, gap 4.
  - `h3`: title role 16/22, weight **400**, foreground.
  - `p`: body 13/20, muted.
  - Below 640 px these are replaced by an `h2` "Settings" (`mb-3`) and a full-width `Select` used as section navigation.
- **Body:** `ScrollArea` (`min-h-0 flex-1`) with inner `"flex flex-col gap-6 px-6 pb-6"`: padding 24 left/right/bottom, gap 24 between blocks.

### SettingRow
- `"flex items-center justify-between gap-6 border-b border-border/60 py-4 last:border-b-0"`.
- Vertical padding 16; gap 24 between text and control. 1 px bottom rule at `border` 60% opacity; no rule on the last row.
- **Left:** `"flex min-w-0 flex-col gap-0.5"` (gap 2). Label body 13/20 foreground; description caption 12/16 muted.
- **Right:** `shrink-0` control (Select trigger, Switch, or `Button variant="secondary" size="sm"` = 28 tall).
- Switch labels are visually hidden (`[&>span:last-child]:sr-only`).
- The General panel starts with a full-width `InputGroup` holding one `InputField` "Workspace name".
- The Members panel uses `SelectTrigger variant="borderless"` and ends with `"pt-4"` + a secondary sm "Invite people" button.

### SwiftUI translation notes
- `HStack(spacing: 0) { sidebar.frame(width: 208); Divider(); panel }.frame(width: 880, height: min(640, windowHeight - 64))` inside the §4 overlay with `.padding(0)` and `.clipShape(.rect(cornerRadius: 12))`.
- **Sidebar:** reuse your Sidebar menu components with a fixed `selection` binding. Background `Color.primary.opacity(0.03)` over the surface.
- **Panel:** a `VStack(alignment: .leading, spacing: 4)` header with `.padding(EdgeInsets(top: 20, leading: 24, bottom: 16, trailing: 48))`, then `ScrollView { VStack(spacing: 24) { ... }.padding([.horizontal, .bottom], 24) }`.
- **SettingRow:** `HStack(spacing: 24) { VStack(alignment: .leading, spacing: 2) {...}; Spacer(minLength: 0); control }.padding(.vertical, 16).overlay(alignment: .bottom) { if !isLast { Rectangle().fill(border.opacity(0.6)).frame(height: 1) } }`.
- Skip the narrow-screen Select fallback on macOS, or set the window's minimum width ≥ 640.

---

## 6. InputGroup / InputField

Source: `input-group__input-group.tsx`

### Group
- `"relative flex flex-col gap-3 w-72 max-w-full"`: width 288, **gap 12** between fields.
- One fluid-hover scope: the field **nearest the pointer** is "active". There is **no** separate highlight layer; each field draws its own state.

### Field
- Field root: `"flex flex-col gap-1 cursor-text"` (label → box gap 4). Disabled: `opacity-50 pointer-events-none`.
- **Label:** body 13/20 (compact 12/18), `pl-2.5` (10) / `pl-2` (8), one notch tighter than the control padding.
  - Color: `text-muted-foreground`, or `text-destructive` when `error`.
  - **Weight is always 400** and the label doesn't change color on hover or focus (only the icon does).
  - `labelHidden` → `sr-only`.
- **Input box:** `` `flex items-center ${gap} rounded-lg ${compact ? "px-2" : "px-2.5"} ${control} ring-1 transition-all duration-80` ``. Height **36 / 28**, padding **10 / 8**, icon gap 8 / 4, radius 8.
  - `ring-1` is a 1 px **outer** box-shadow ring, so the visible edge sits just outside the 36 px box.

### Box states (first match wins)

| State | Background | Ring |
|---|---|---|
| disabled | transparent | `ring-border` (whole field at 50% opacity) |
| error + focused | `bg-card` | `ring-destructive/50` |
| error + hovered (active) | `bg-destructive-light/60` | `ring-destructive/50` |
| error at rest | transparent | `ring-transparent` (frameless; red label and message carry the error) |
| focused | `bg-card` (lifts to the card surface) | `ring-border` |
| hovered (nearest) | `bg-muted/50` | `ring-border` |
| rest | transparent | `ring-transparent` |

All states transition over 80 ms.

### Icon, input and error
- **Icon (optional, leading):** size 16 / 14. Stroke **1.5 → 2** and color **muted → foreground** when hovered **or** focused (`transition-[color,stroke-width] duration-80`).
- **Input:** `"w-full rounded-none bg-transparent text-foreground placeholder:text-muted-foreground outline-none"`, body field type, weight 400. No native focus ring; the box's state is the focus indicator.
- **Error message:** caption **12/16** (compact 11/14), `text-destructive`, same left inset as the label (10 / 8), weight 400. It sits 4 px under the box.
- Clicking anywhere in the box (padding, icon) focuses the input without moving the caret if you clicked the text itself.

### Accessibility
- The label is wired via `htmlFor`.
- The error id goes into `aria-describedby`; `aria-invalid` is set when `error` exists.

### SwiftUI translation notes
- `TextField("", text: $value, prompt: Text(placeholder).foregroundStyle(muted)).textFieldStyle(.plain).font(body)` in `HStack(spacing: 8) { icon; field }.padding(.horizontal, 10).frame(height: 36)`.
- Background: `RoundedRectangle(cornerRadius: 8).fill(bg)`. Ring: an overlay `RoundedRectangle(cornerRadius: 9).strokeBorder(ring, lineWidth: 1).padding(-1)` (outer ring).
- Track focus with `@FocusState`. "Nearest field" comes from group-level `onContinuousHover` over the field frames (§0.4).
- `.contentShape(Rectangle()).onTapGesture { focused = true }` on the box.
- **Accessibility:** `.accessibilityLabel(label)`; append the error with `.accessibilityValue` or `.accessibilityHint(error)`.

---

## 7. InputCopy

Source: `input-copy__input-copy.tsx`

### Props
- `variant`: `"icon"` (default; copy icon + tooltip) or `"button"` (icon + "Copy" label).
- `align`: `"right"` (default; value then action) or `"left"` (action then value).
- Also `label?`, `disabled`, `size`, `onCopy`.

### Structure
- **Root:** `"flex flex-col gap-0.5"` (label → row gap 2). Disabled: opacity 50%, no pointer.
- **Label:** body 13/20 (compact 12/18), muted, weight 400; `pl-1` (4) when `align="left"`.
- **Row** (one `<button>`): `"group flex items-center w-full cursor-pointer outline-none transition-all duration-80 focus-visible:ring-1 focus-visible:ring-[#6B97FF] rounded-lg"`.
  - **No background, border or field chrome at any state.** The only states are the hover tints below and a 1 px focus ring.
- **Row height:** padding comes from the children, `py-2` / `py-1`. Default = 8 + 20 + 8 = **36**. Compact = 4 + 18 + 4 = **26** (the source comment says 28, but the math gives 26).
- **Value:** `"flex-1 min-w-0 text-left text-foreground font-mono select-none truncate"`, body size, weight 400, single line with tail truncation. `pl-1` when align left, else `pl-0`.
  - The text is wrapped in `<mark class="bg-transparent ... transition-colors duration-80 group-hover:bg-[#6B97FF]/20">`. **On row hover, the glyph run gets a #6B97FF 20% highlight** (like a text selection) behind the text only, not the full width.
- **Action, icon variant:** `"shrink-0 px-1.5 ... text-muted-foreground group-hover:text-foreground"`. Padding 6 left/right plus the row's vertical padding; color muted → foreground over 80 ms.
- **Action, button variant:** `"shrink-0 flex items-center gap-1.5 px-1.5"`. Icon + label (body, weight 400), gap 6. The label sits in an inline-grid with an invisible "Copied" so **width never changes** between Copy / Copied / Failed.

### Icons
- **Copy:** Lucide `copy`, 14 px, stroke 1.5 → 2 on row hover.
- **Check:** path `M6 12L10 16L18 8` in an svg 14×14 with **viewBox "2 4 20 16"** (scale 0.7, content 14×11.2 centered vertically). Points in px: (2.8, 7.0) → (5.6, 9.8) → (11.2, 4.2).
  - Icon variant: stroke `[&_svg]:stroke-[1.5]` → `2` on hover (rendered 1.05 → 1.4 px).
  - Button variant: `strokeWidth={2}` fixed (1.4 px).
  - Color is inherited (muted / foreground).
- **Error ×:** path `M9 9L15 15M15 9L9 15`, same viewBox and stroke, `text-destructive`.

### Copy confirmation animation
- `AnimatePresence mode="wait" initial={false}`: the outgoing glyph exits **before** the incoming one enters.
- Outgoing glyph: opacity 1 → 0 and scale 1 → **0.8** on spring.fast.
- Incoming check or ×: opacity 0 → 1 and scale **0.6 → 1** on spring.fast, while its path **draws** (pathLength 0 → 1, **0.08 s easeOut**).
- Returning copy icon: enters from scale **0.8** and opacity 0.
- Whole swap is about 160 ms.
- Result shows for **2000 ms** and then returns to idle. Copying again restarts the 2 s window and re-keys the glyph so the draw replays.
- Copy uses the async clipboard API with an `execCommand` fallback. On failure: × and "Failed" / "Copy failed".

### Tooltip (icon variant only)
- Content "Copy to clipboard", `delayDuration 500`, `sideOffset 2`.
- After a click, the tooltip shows "Copied" / "Copy failed" (forced open) **only if it was already visible when the press began**. Otherwise it stays suppressed.
- When the 2 s window ends, the tooltip stays suppressed until the pointer leaves and re-enters.
- Leaving the row closes a forced "Copied".
- Tooltip look: `bg-foreground text-background`, caption 12/16, `px-2 py-1` (~24 tall), radius 8, spring.fast in / 0.06 s out.

### Accessibility
- The button's `aria-label` follows state: "Copied" / "Copy failed" / "Copy" (with label) / "Copy to clipboard".
- `aria-labelledby` = button + field label, so it reads "Copy <label>".

### SwiftUI translation notes
- `Button(action: copy) { HStack(spacing: 0) { value; action } }.buttonStyle(.plain)` with `.onHover` for the hover state.
- **Value:** `Text(value).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.tail)`. Draw the highlight as `.background(isHovered ? Color(hex: 0x6B97FF).opacity(0.2) : .clear)` on the `Text` itself; it hugs the text, matching `<mark>`.
- **Clipboard:** `NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)` (returns Bool, giving you the failure path).
- **Glyph swap:** `ZStack { switch status { ... } }` with `.id(copyCount)` and `.transition(.asymmetric(insertion: .scale(0.6).combined(with: .opacity), removal: .scale(0.8).combined(with: .opacity)))` under `.spring(duration: 0.08, bounce: 0)`. SwiftUI has no "wait" mode, so delay the insertion by ~0.08 s, or accept a cross-fade.
- **Check draw:** a trim-animated `Shape` with `.easeOut(duration: 0.08)`.
- **Reset:** `Task { try? await Task.sleep(for: .seconds(2)); status = .idle }`, cancelling the previous task.
- **Tooltip:** `.help()` can't force "Copied" open, so use a custom tooltip overlay or a small popover. If acceptable, use `.help(status == .idle ? "Copy to clipboard" : "Copied")`.
- **Accessibility:** `.accessibilityLabel(...)` tracks status; post `NSAccessibility.post(element:notification: .announcementRequested)` with "Copied".

---

## 8. ColorPicker / ColorPickerPopover / ColorSwatch / ColorTile

Source: `color-picker__color-picker.tsx`, slider compact engine in `slider__slider.tsx`, theme `color-picker__theme.json`

### 8.1 Model
- **State:** canonical **HSV + alpha** (`h` 0–360, `s` / `v` / `a` 0–1). Every format is derived from it.
- **Hue preservation:** when a new color has no chroma (gray, white, black; `s == 0` after `rgbToHsv`), the **existing hue is kept**, so dragging into the gray or black edge never loses H.
- **Sticky OKLCH hue:** the OKLCH H the user typed is kept across RGB rounding drift and achromatic colors. It's cleared by the hue rail, HSL H, RGB, hex, swatches, the eyedropper or an outside value. It's kept by the square, alpha, and HSL S/L edits.
- **Output:** `onValueChange(string, parsed)`, formatted in the current format:
  - hex: lowercase `#rrggbb`, or `#rrggbbaa` when alpha < 1
  - `rgb(r, g, b)` / `rgba(r, g, b, a)`
  - `hsl(h, s%, l%)` / `hsla(..., a)` (integers)
  - `oklch(L% C H)` / `oklch(L% C H / a)` with L% to 1 decimal, C to 3, H to 1
  - Alpha prints up to 3 decimals, only when < 1.
- Switching format re-emits the same color in the new format.
- **Default value:** `#6B97FF`. Default format: `hex`.
- **Parsing:** hex with 3/4/6/8 digits ("#" optional), `rgb()`/`rgba()`, `hsl()`/`hsla()`, `oklch()`. Separators can be commas, spaces or "/"; alpha can be 0–1 or %. Swatches also accept named CSS colors (browser-normalized). Unparseable input is ignored.
- **OKLCH:** Ottosson's matrices, linear sRGB. Out-of-gamut values clip per channel.

### 8.2 Panel
- `"flex flex-col gap-2 p-3"` + `surfaceClasses(max(substrate, 3), 1)` + `rounded-xl`.
- **Width 280**, padding **12**, vertical gap **8**, radius 12.
- Inline: surface **max(substrate, 3)** with **shadow-1**. In the popover: surface `min(substrate + 2, 8)` with **shadow-3**.
- Inner content width **256**.
- Order: saturation square → hue + alpha rails → [format dropdown | eyedropper] → channel inputs → swatches (optional).

### 8.3 Saturation / brightness area
- **Size:** full width (256) × **156**.
- **Radius:** `nestedRadius(containerRadius 12, inset 12)` = **0** (square corners) for rounded; 12 for pill.
- **Fill** (exactly the HSV plane): `linear-gradient(to top, #000, transparent)` over `linear-gradient(to right, #fff, hsl(h, 100%, 50%))`.
- **Mapping:** x → S 0..1 (left → right); y → V 1..0 (top → bottom). Clamped; pointer capture keeps the drag alive outside the area. **The press itself sets the color**; dragging continues to update it.
- **Thumb:** an **18×18** circle centered on (S·W, (1−V)·H), filled with the current opaque color.
  - `border: 1px solid white` and `box-shadow: 0 0 0 1px rgba(0,0,0,1)`: white inner ring with a black outer ring, legible anywhere.
  - Moves with `duration: 0` (never lags the pointer).
- **OS cursor hidden** (`cursor-none`).
- **Ghost cursor ring:** shown while hovering and not dragging. An 18 px hollow circle at the pointer with `border: 2px solid rgba(255,255,255,0.55)` and `box-shadow: 0 0 0 1px rgba(0,0,0,0.2)`. It previews where a press lands.
- **Focus:** keyboard only. `box-shadow: 0 0 0 2px #6B97FF` (2 px outer ring).
- **Keys:** ← / → adjust S by ±0.01; ↑ / ↓ adjust V by ±0.01; Shift multiplies by 10 (±0.1). Clamped.
- `role="application"`, `aria-label="Saturation and brightness"`, `tabIndex 0`.

### 8.4 Hue and alpha rails (Slider compact engine)
- **Stack:** `"flex flex-col [&>*]:mb-0 [&>*+*]:-mt-px"`. Two rails, the second overlapping the first by 1 px. **Total height 71** (36 + 36 − 1).
- **Per rail:**
  - Root: flex row. `mb-2` is overridden to 0; with `showValue={false}` there's no value label.
  - Hit row height **36** (thumb 20 + 16), `cursor-ew-resize`, plus an **extra 8 px hit area beyond each horizontal end** (presses there clamp to min or max).
  - **Track pill:** height **18**, top **9** (8 + 1), inset **1 px** left and right, `rounded-full`, `overflow-hidden`.
  - **Thumb box:** 20×20 holding a **16×16 knob** (`rounded-full`), fill `thumbColor`, `border: 1px solid rgba(255,255,255,0.9)`, `box-shadow: 0 1px 2px rgba(0,0,0,0.1)`.
  - **Thumb x:** `left = value / max × (trackWidth − 20)`; knob center = left + 10.
  - **Thumb focus ring:** a 24×24 circle with a 1 px `#6B97FF` border. Opacity animates to 1 on keyboard focus only (spring.fast).
- **Hue rail:** 0–360, step 1.
  - Pill fill: `linear-gradient(to right, hsl(0,100%,50%), hsl(60,...), hsl(120,...), hsl(180,...), hsl(240,...), hsl(300,...), hsl(360,...))`. The border is transparent (1 px, gradient shows under it).
  - Thumb color `hsl(h, 100%, 50%)` (pure hue).
- **Alpha rail:** 0–100 (whole percent), step 1.
  - Pill fill: `linear-gradient(to right, rgba(r,g,b,0) 0%, rgb(r,g,b) 98%)` over the 8 px checker, `borderWidth: 0`.
  - Thumb color: the current color, opaque.
- **No fill bar** (`hideFill`).
- **Interaction:**
  - Press: snap to the step grid and **spring** the thumb there (spring.moderate).
  - Drag: re-snap on every move and **set** the position directly (no spring).
  - Release: spring-settle on spring.moderate.
  - Keyboard / programmatic changes and track resizes also spring on spring.moderate.
- **Hover feedback** (present even with `showValue={false}`):
  - A preview bar inside the pill, from the thumb center to the snapped hover value. Fill `color-mix(srgb, accent 40%, transparent)`, outer end rounded, opacity fades over **0.15 s**, hidden while pressed.
  - After a **100 ms** hover delay, a value bubble appears at `top: −20` over the snapped x: `bg-foreground text-background`, caption 12/16, `px-2 py-1`, radius 8, tabular numbers.
  - The bubble enters with opacity 0 and y +4 → 0 on spring.fast; it exits on spring.fast.exit and hides while pressed.
- **Keys** (Radix slider): ← / → / ↑ / ↓ move ±1; Shift+arrow and PageUp / PageDown move ±10; Home / End. `aria-label` "Hue" / "Alpha".

### 8.5 Checkerboard
- CSS: `conic-gradient(var(--checker-a) 0 25%, var(--checker-b) 0 50%, var(--checker-a) 0 75%, var(--checker-b) 0)`, `background-size: 8px 8px`.
- Result: 4×4 squares. Per 8×8 tile: top-left = b, top-right = a, bottom-right = b, bottom-left = a.
- Light: a #BBBBBB, b #FFFFFF. Dark: a #1F1F1F, b #2A2A2A.

### 8.6 Format dropdown and eyedropper row
- `"grid grid-cols-2 gap-2"`: two cells of **124** each, gap 8.

**Format trigger** (Base UI `Menu.Trigger`, fills its cell):
- Class: `"flex items-center justify-between bg-transparent hover:bg-hover hover:text-foreground transition-colors duration-80 ... focus-visible:ring-1 ring-[#6B97FF]"` + `gap-2` + `h-9` + `px-3` + body + `rounded-lg`.
- Height **36 / 28**, padding 12 / 10, radius 8, weight 400.
- **Rest:** `text-muted-foreground`. **Hover:** `bg-hover` + foreground. **Pressed:** `bg-active`. **Open:** `bg-active text-foreground` (held while open).
- Label: "HEX" / "RGB" / "HSL" / "OKLCH".
- Chevron: Lucide `chevron-down` **14**, stroke 1.5, muted. Rotates **180° when open** over **150 ms** (CSS default curve).

**Format menu:**
- Positioner: `side bottom`, `align start`, `sideOffset 6`, `z-60`. Non-modal (page keeps scrolling, popup follows the trigger). Portalled inside the popover panel when one exists.
- **Motion:** opacity 0 → 1, y −4 → 0, **scaleY 0.96 → 1**, `transformOrigin: top center`, on **spring.fast**. Exit: back to the initial values on the 0.06 s tween. Unmount is held until the exit finishes (fallback 120 ms).
- **Popup:** `Elevated offset={2} shadowLevel={3}`, i.e. surface = panel level + 2 with **shadow-3**.
  - Class: `"relative flex flex-col min-w-[var(--anchor-width)] rounded-xl p-1 select-none outline-none"`. Minimum width = trigger width (124), **radius 12** (always rounded, even in pill shape), padding **4**.
- **Items:** `"relative z-10 flex items-center cursor-pointer outline-none" + (compact ? "px-2.5 py-1.5" : "px-3 py-2") + body + rounded-lg`.
  - Height **36** (20 + 16); compact **30** (18 + 12). Padding 12 / 10, radius 8.
  - Label: dual-layer, color foreground if hovered or checked else muted, **550 when checked**, 80 ms.
  - `closeOnClick`.
- **Layers:**
  - Checked bg: `bg-active`, radius 8, springs on spring.moderate between rows; exit 0.12 s.
  - Hover: `bg-hover`. Each new pointer session **fades in on the checked row** (`from={checkedRect}`) and then glides to the hovered row.
  - Focus ring: shared ring (§0.4).
- **Keys** (Base UI Menu): ↑ / ↓ roving highlight, typeahead, Enter / Space select, Esc closes and returns focus to the trigger. Uses `Menu.RadioGroup` / `RadioItem` semantics.

**Eyedropper button:**
- Class: `"flex items-center justify-center text-muted-foreground bg-transparent hover:bg-hover hover:text-foreground active:bg-active transition-colors duration-80 ... focus-visible:ring-1"` + `h-9 px-3 rounded-lg`.
- Fills its cell; height 36 / 28; Lucide `pipette` 16 / 14, stroke 1.5.
- `aria-label="Pick color from screen"`. Hidden where unsupported (non-Chromium) or with `hideEyedropper`. Cancel (Esc) is silent.

### 8.7 Channel inputs row (depends on format)
- **HEX:** `"grid grid-cols-2 gap-2"`.
  - Cell 1: text field with **prefix "#"** (caption 12/16 muted, `mr-1` = 4) and value **uppercase, no "#"**.
  - Cell 2: Alpha field.
- **RGB / HSL / OKLCH:** `"grid grid-cols-4 gap-1"`. Four cells of **61**, gap **4**: three channels + Alpha. Values centered.

**Field chrome** (both kinds): `"flex items-center bg-transparent hover:bg-hover active:bg-active transition-colors duration-80 focus-within:ring-1 focus-within:ring-[#6B97FF] select-none"` + `h-9` (h-7 compact) + `rounded-lg`. Inner padding `px-2` (8). Input text is body field type, foreground, `tabular-nums`, weight 400.

**Hex text field:**
- Focus selects all. Typing edits a draft; blur or Enter commits; Esc reverts and blurs.
- The "#" is re-added on commit. 8 digits carry alpha. Invalid input is dropped.

**Scrub fields** (all numeric channels + Alpha; Base UI NumberField):
- At rest the cursor is `cursor-ew-resize` and the input ignores the pointer.
- **Horizontal drag scrubs** under pointer lock at **1 px per step**. A virtual cursor replaces the OS one: a 24×14 ↔ arrow, path `M0.5 7l5-5v3.5h13V2l5 5-5 5V8.5h-13V12l-5-5z`, black fill, white 1 px stroke, `drop-shadow(0 1px 1px rgba(0,0,0,0.4))`.
- A **press without drag** enters edit mode (focus + select all, caret placement allowed).
- Keys: Enter commits (blur), Esc reverts. ↑ / ↓ nudge by `step`, Shift by `largeStep`. Scrubs and nudges commit immediately; typing commits on blur.

| Field | Range | Step / Shift | Format |
|---|---|---|---|
| R, G, B | 0–255 | 1 / 10 | integer |
| HSL H | 0–360, **wraps** (361 → 1) | 1 / 10 | integer |
| HSL S, L | 0–100 | 1 / 10 | integer |
| OKLCH L | 0–100 | 1 / 10 | integer (no %) |
| OKLCH C | 0–0.4 | 0.01 / 0.1 | 2 decimals |
| OKLCH H | 0–360, wraps | 1 / 10 | integer (shows sticky H) |
| Alpha | 0–100 | 1 / 10 | `NN%` |

- Each channel has a **tooltip after 300 ms**: Hex / Red / Green / Blue / Hue / Saturation / Lightness / Chroma / Alpha.

### 8.8 Swatches
- `"flex flex-wrap gap-2"`: **28×28**, gap 8, **7 per row** at 256 width.
- **ColorSwatch:** radius 8, checker behind a color layer, `transition-shadow duration-100`.
  - Rest: `box-shadow: inset 0 0 0 1px rgba(127,127,127,0.25)`
  - Hover: rest + `0 0 0 2px var(--background), 0 0 0 4px rgba(127,127,127,0.4)` (2 px gap, then a 2 px gray ring; radii 10 / 12)
  - Selected: rest + `0 0 0 2px var(--background), 0 0 0 4px #6B97FF`
- Selected = normalized lowercase hex (alpha included) equals the current hex.
- `aria-label="Select color <c>"`.
- **ColorTile** (non-interactive): default 24 px, radius 8, checker + color, `inset 0 0 0 1px rgba(127,127,127,0.25)`.

### 8.9 ColorPickerPopover

**Trigger** (Base UI `Popover.Trigger`):
- Class: `"flex items-center border border-border bg-transparent hover:bg-hover transition-colors duration-80 ... focus-visible:ring-1 ring-[#6B97FF]"` + `gap-2/gap-1` + `h-9/h-7` + `px-2/px-1.5` + `rounded-lg`.
- 1 px border, height 36 / 28, padding 8 / 6, radius 8.
- Contents, in order:
  - Optional `triggerLabel` (body, muted, `px-1`; left or right)
  - **ColorTile 20 / 16** (keeps alpha over the checker)
  - Value text (`triggerShowValue`, default on): **6-digit uppercase hex, alpha dropped**, body, foreground, tabular
  - Optional remove ×: Lucide `x` 14, stroke 1.5, muted → foreground, `ml-1`, `role="button"`, Enter / Space. It doesn't toggle the popover.

**Popover:**
- `side bottom`, `align start`, `sideOffset 6`, `z-50`, non-modal.
- **Motion:** opacity 0 → 1, y −4 → 0, **scaleY 0.96 → 1**, `transformOrigin: top left`, on **spring.moderate**. Exit: 0.12 s tween; fallback unmount 150 ms.
- Behavior: outside press, focus-out or Esc dismiss. Focus moves into the panel on open and returns to the trigger on close.

### SwiftUI translation notes
- **Model:** port the color math verbatim (pure functions). Hold `HSVA` plus `stickyOklchHue: Double?` in an `@Observable` model.
- **Saturation area:** `ZStack { LinearGradient(colors: [.white, Color(hue: h/360, saturation: 1, brightness: 1)], startPoint: .leading, endPoint: .trailing); LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom) }.frame(height: 156)`.
  - `DragGesture(minimumDistance: 0, coordinateSpace: .local)` sets S/V on `onChanged` (the press counts).
  - Hide the cursor with `.onHover { $0 ? NSCursor.hide() : NSCursor.unhide() }` (balance the calls). Draw the ghost ring from `onContinuousHover`.
  - Thumb: `Circle().fill(color).overlay(Circle().strokeBorder(.white, lineWidth: 1)).overlay(Circle().stroke(.black, lineWidth: 1).padding(-0.5))` at 18 pt, with `.animation(nil)`.
- **Rails:** custom (`Slider` can't take a gradient track). `Capsule().fill(gradient).frame(height: 18).padding(.horizontal, 1)` in a 36 pt tall hit area; knob 16 pt.
  - Press: spring the knob with `.spring(duration: 0.16, bounce: 0)`. Drag: set position without animation.
  - Hover bubble and preview bar per §8.4.
  - Checkerboard: a `Canvas` drawing 4×4 squares, or `ImagePaint` of a pre-rendered 8×8 tile.
  - Accessibility: `.accessibilityRepresentation { Slider(value:in:step:) }` for VoiceOver and arrow keys.
- **Eyedropper:** always available on macOS: `NSColorSampler().show { nsColor in ... }` (convert to sRGB with `usingColorSpace(.sRGB)`).
- **Scrub fields:** on drag start call `CGAssociateMouseAndMouseCursorPosition(0)` and `NSCursor.hide()`. Accumulate `NSEvent.deltaX` from a local `.leftMouseDragged` monitor (1 pt = 1 step). Draw the ↔ cursor overlay at the press point. On mouse up, re-associate and unhide. A tap without movement focuses a `TextField` and selects all (`NSTextView.selectAll` via the field editor).
- **Format menu:** to keep the fluid-hover menu, build it as a custom popover (overlay anchored below the trigger with `.offset(y: 36 + 6)` and `.zIndex`, or a borderless child `NSPanel`). If native is acceptable, use `Menu { Picker("", selection: $format) { ... }.pickerStyle(.inline) }` with `.menuStyle(.borderlessButton)`.
- **ColorPickerPopover:** SwiftUI `.popover` on macOS draws an NSPopover arrow and chrome. To match, present the panel in an overlay or child window anchored to the trigger's bottom-leading corner with `.scaleEffect(y: open ? 1 : 0.96, anchor: .topLeading).offset(y: open ? 0 : -4).opacity(...)` under `.spring(duration: 0.16, bounce: 0)`.

---

## 9. Table

Source: `table__table.tsx`

### Structure
- Wrapper `div.relative` holds one `FluidHoverHighlight` behind the table.
  - **No radius class is passed, so the hover pill has square corners (radius 0)**, `bg-hover`, springing on spring.fast.
- `table`: `"w-full border-collapse"` + body type 13/20 (compact 12/18).
- Header and body sections have no styling of their own.
- **Only body rows that receive an `index` register for hover.** Header rows never light up.

### Row
- Class: `"group/row relative z-10 border-b transition-[border-color] duration-80"`. Each row draws only its **bottom** border, 1 px.
- Border color: `border-accent/40` (accent at 40%) at rest. It turns **transparent** on the hovered row **and the row directly above it** (that row's bottom border is the hovered row's top edge). When body row 0 is hovered, the header row's border hides too. 80 ms fade.
- Weight: body rows **400**, header rows **550** (set on the row).
- The lit row gets class `is-active`, which drives its cells.

### Cells
| | default | compact |
|---|---|---|
| Padding (TH and TD) | `px-3 py-2` → 12 / 8 | `px-2.5 py-[5px]` → 10 / 5 |
| Row height (+1 px rule) | **36** | **28** |

- TH: `"text-left text-foreground"`.
- TD: `"text-muted-foreground transition-colors duration-80 group-[.is-active]/row:text-foreground"`, muted at rest and **foreground on the hovered row**.

### Behavior
- **No selection state and no keyboard navigation.** Hover only (focus doesn't drive it).
- A gap click forwards to the hovered row element, which matters only if the consumer adds row `onClick`.

### SwiftUI translation notes
- SwiftUI `Table` on macOS (NSTableView) can't draw this hover pill or the rule-hiding.
- Build `Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0)` (or a `LazyVStack` of `HStack` rows with fixed column widths).
  - Header `GridRow` uses semibold foreground.
  - Body rows publish frames for a single `Rectangle().fill(hover)` highlight (radius 0) in `.background`, animated with `.spring(duration: 0.08, bounce: 0)`.
  - Rules: `.overlay(alignment: .bottom) { Rectangle().fill(accent.opacity(0.4)).frame(height: 1).opacity(hideRule ? 0 : 1) }` with `.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.08), value: hideRule)`.
  - Cell padding `EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)`.
- If you need NSTableView (large data), subclass `NSTableRowView` and override `drawBackground(in:)` / `drawSeparator(in:)`, tracking the hovered row with an `NSTrackingArea`.

---

## 10. AskUserQuestions

Source: `ask-user-questions__ask-user-questions.tsx`

A multi-step question card: single-select, multi-select, an optional "Other" free-text row, or a pure `freeText` question.

### Question options
`multiSelect`, `allowOther`, `otherPlaceholder`, `skippable` (default true), `nextLabel`, `layout: "inline" | "stacked"`, `chipPosition: "right" | "left"`, `freeText`, `freeTextPlaceholder`, `freeTextMultiline` (default true), `freeTextValidate`.

### Card
- `"relative w-full max-w-[520px] overflow-hidden bg-card border border-border rounded-xl"`.
- Max width **520**, `card` fill, 1 px border, radius 12, clipped. Footer buttons animating out are clipped at the edge.
- Empty state: `p-5` (20) with "No questions." in body muted.
- Breakpoint note: `sm:` values apply at viewport ≥ 640, which is the normal case in a desktop app. The non-`sm` values are the mobile fallback.

### Header
- "Question N of M", `text-muted-foreground`.
- Default: caption 12/16, padding `px-4 sm:px-5 pt-3.5 sm:pt-4 pb-2` → **20 / 16 / 8** at sm (16 / 14 / 8 below sm).
- Compact: caption 11/14, `px-3.5 sm:px-4 pt-2.5 sm:pt-3 pb-1.5` → **16 / 12 / 6**.
- It sits outside the morphing region and never moves.

### Morphing region (height animation)
- A `motion.div` with `overflow-hidden` animates its **real height** to the measured content height (ResizeObserver) on **spring.slow** (0.24 s, bounce 0.12). The footer reflows along with it.
- Content is keyed by question id, so it **swaps instantly** and the clip reveals it as the height animates.
- Content padding:
  - Horizontal: same as the header (20 / 16 at sm).
  - Bottom: **4** (`pb-1`) when a footer exists; otherwise `pb-2.5 sm:pb-3` → 12 default, `pb-2 sm:pb-2.5` → 10 compact.
- `"flex flex-col gap-2"`: title → rows gap 8.
- **Title `h3`:** fixed `fs-title` **16/22** (it does *not* step down in compact), weight **550**, foreground.

### Option rows
- Rows container: `"relative flex flex-col -mx-3"`. It bleeds **12 px** past the content padding on each side, so row fills reach 8 px from the card edge.
- **Row:** `"relative z-10 flex cursor-pointer select-none outline-none rounded-lg"`, plus:
  - Gap: `gap-3` (12) with the chip on the right; `gap-2` (8) with the chip on the left.
  - Alignment: `items-center`, or `items-start` when `topAlign` (stacked layout, or the Other textarea once it wraps).
  - Height and padding:

| Layout | default | compact |
|---|---|---|
| inline | `min-h-10 py-1.5` → min **40**, vertical 6 | `min-h-8 py-1` → min **32**, vertical 4 |
| stacked | `min-h-14 py-2` → min **56**, vertical 8 | `min-h-12 py-1.5` → min **48**, vertical 6 |

  - Horizontal padding:
    - Chip right: `pl-3 pr-1.5` → 12 / 6
    - Chip left, single-select: `pl-1.5 pr-1.5` → 6 / 6
    - Chip left, multi-select: `pl-1.5 pr-3` → 6 / 12
- **Body:** `min-w-0 flex-1`, body 13/20 (compact 12/18).
  - Inline: title (dual-layer, **foreground at all times**, weight 400 → **550 when selected**, 80 ms), then a space, then the description in `text-muted-foreground` at the same size, all on one line (wraps naturally).
  - Stacked: `flex flex-col gap-0.5` (2). Title as above; description caption 12/16 (compact 11/14) muted.
- **Chip slot:** **28×28** (`w-7 h-7`) / **24×24** compact. With `topAlign` it shifts up `-mt-[5px]` (inline) or `-mt-[1px]` (stacked).
- **Chip:** **20×20** / 18×18, micro type 11/14, showing the number `i + 1`.
  - Single-select: no box. Text muted → **foreground** and weight 400 → **550** when selected.
  - Multi-select: radius 8 (`rounded-lg`). Unselected: `"border border-border text-muted-foreground"`. Selected: `"bg-foreground text-background"`, weight 550.
  - Transitions: `transition-[opacity,font-variation-settings] duration-80`.
- **Submit arrow** (single-select only; shown when the row is the active index, i.e. hovered or focused):
  - `"absolute inset-0 inline-flex items-center justify-center bg-foreground text-background rounded-lg"`, filling the 28×28 chip slot (24×24 compact).
  - Lucide `arrow-right` **14** stroke 2. In the Other row: 12 compact, 14 default.
  - Enter: opacity 0 → 1 (0.08 s) and scale **0.6 → 1** on spring.fast. Exit: opacity 0, scale 0.6, on the 0.06 s tween.
  - With the chip on the right, the chip fades to opacity 0 (80 ms) under the arrow. With the chip on the left, the arrow sits in its own 28×28 right-edge slot and the chip stays visible.
  - Clicking a single-select row selects it **and advances** immediately; the arrow is the visual affordance.

### Layers (bottom → top)
**Selection paints above hover here**, unlike CheckboxGroup.
1. **Other "type here" hint:** shown only while the Other textarea is focused **and empty**. `"absolute pointer-events-none bg-card ring-1 ring-inset ring-border rounded-lg"` (card fill, 1 px inset border). Fades in from opacity 0 at the row rect (0.08 s, geometry on spring.fast); exits on the 0.06 s tween.
2. **Hover highlight:** `bg-hover`, radius 8, spring.fast.
3. **Selection blocks:** `bg-active`, using the merge/split algorithm (§1) with **R = `shape.bgRadius`** = 8 (rounded) / 20 (pill). The Other row joins the selection set **once it has text**, so it merges with adjacent selected options.
4. **Focus ring:** shared ring (§0.4). It enters with opacity 0 → 1 at the first rect. **Suppressed for the Other row.**

### Other row
- Index `options.length`; chip number `options.length + 1`. Not a tab stop (the textarea is focusable on its own). Clicking the row focuses the textarea.
- **Textarea:** `rows=1`, `"block w-full bg-transparent border-0 p-0 m-0 outline-none resize-none overflow-hidden text-foreground placeholder:text-muted-foreground"`, body field type, weight 400.
  - Auto-height: height → 0, then → `scrollHeight`.
  - Placeholder: `otherPlaceholder ?? "Describe in your own words…"`.
  - Becomes `topAlign` once its content exceeds 1.5× the line height.
- **Keys:**
  - Single-select: Enter submits (trimmed text required); Shift+Enter inserts a newline.
  - Multi-select: Enter inserts a newline; ⌘↵ continues.
- The arrow shows when the row is focused or hovered **and** the trimmed text isn't empty. Clicking the arrow submits.

### freeText question
- A box replaces the rows.
- Class: `"relative mt-1 cursor-text transition-colors"` + `-mx-3 py-2.5` (compact `-mx-2.5 py-2`) + `px-3` (`px-2.5`) + `rounded-lg`.
- Min height **76** (multiline), or **40** / **32** (single-line, default / compact).
- **States:**
  - Empty at rest: transparent.
  - `hover:bg-hover`.
  - `focus-within:bg-card focus-within:ring-1 focus-within:ring-inset focus-within:ring-border`.
  - **With text:** `bg-active`.
- **Textarea:** same reset classes as the Other row; placeholder `"Type your answer…"`. **Auto-focuses** when the question appears (no scroll).
  - Multiline: Enter inserts a newline; ⌘/⌃↵ submits.
  - Single-line: Enter submits.
- `freeTextValidate` runs on submit. Its message appears in the footer and clears on edit.

### Footer
- Shown if Back, Skip or Submit is shown.
  - Back: index > 0 and total > 1.
  - Skip: total > 1 and the question is skippable.
  - Submit: multi-select or freeText.
- Padding: `pt-1` + `px-4 sm:px-5 pb-2` → top 4, left/right 20, bottom 8. Compact: `px-3.5 sm:px-4 pb-1.5` → 16 / 6.
- Inner: `"flex items-center justify-between gap-2 -mx-2 sm:-mx-3"`. It bleeds 12 px so ghost button text aligns with the content edge.
- **Left cluster** (`flex-1 min-w-0 gap-2`):
  - **Back:** `Button variant="ghost" size="sm"` → compact: height 28, `px-3`, body-compact 12/18. Leading `arrow-left` 14 (desktop only), `pl-2` at sm.
  - **Validation error:** `p` with `role="alert"`, caption 12/16 `text-destructive`, `px-2 sm:px-3`. Enters with opacity 0 → 1 (0.12 s) and y −2 → 0 (spring.fast).
- **Right cluster** (`gap-2`):
  - **Skip:** ghost, sm, trailing `arrow-right` 14, `pr-2` at sm. Label `skipLabel` (default "Skip").
  - **Continue:** `Button variant="primary" size="sm"`. Label `nextLabel ?? ("Finish" on the last question, else "Continue")`, `pr-2` at sm.
    - Disabled (opacity 50%) when nothing is selected and the Other text is empty (freeText: when the text is empty).
    - Holds a **ShortcutChip**: `kbd` `"inline-flex items-center justify-center gap-0.5 px-1 min-w-[18px] h-[18px] text-[11px] leading-none font-sans rounded-lg"`. Min width **18**, height 18, padding 4, micro 11, radius 8.
    - Chip tone `inverted`: `bg-background/15 text-background`. Content "⌘↵" on Mac, "⌃↵" elsewhere. Gap between label and chip 6.
- Each footer button sits in `AnimatePresence mode="popLayout"` with `layout="position"`. Enter: opacity 0 → 1 (0.1 s) and scale **0.85 → 1** on spring.fast. Exit: the reverse. Siblings slide (layout) while the exiting button is popped out of flow.

### Keyboard
- **Digits 1–9** (document-level, ignored inside inputs or with modifiers) select (single-select, advancing) or toggle (multi-select) option N. With `allowOther`, digit N = options + 1 focuses the Other field. Only one instance answers: the one containing focus, else the most recently mounted.
- ↑ / ↓ move the highlight **and** focus between rows, wrapping. Home / End go to first / last. Moving to the Other row focuses its textarea. In the textarea, ↑ / ↓ leave the field only when the caret is at the very start or end.
- **← = Back, → = Skip** (when available). `stopPropagation` keeps them from reaching page navigation.
- Space / Enter on a row: select (single, advancing) or toggle (multi).
- **⌘↵** (Mac) / **Ctrl+↵**: Continue for multi-select (requires an answer) or freeText (requires text).
- **Roving tabindex:** one tab stop, on the first selected row or else row 0. Single- and multi-select behave the same.
- **Focus restore:** when navigating questions while keyboard-driving (focus ring visible), the new question's first row gets focus.
- **Semantics:** container `role="radiogroup"` (single) or `"group"` (multi), labelled by the title. Rows are `role="radio"` / `"checkbox"` with `aria-checked`. Hidden Base UI primitives (`sr-only`, `aria-hidden`, `tabIndex -1`) carry group state.

### SwiftUI translation notes
- **Card:** `VStack(spacing: 0) { header; morphing; footer }.background(card, in: .rect(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(border)).clipShape(.rect(cornerRadius: 12)).frame(maxWidth: 520)`.
- **Height morph:** put the question content in a `VStack` keyed by `.id(questionID)` with `.transition(.identity)`, inside a container that is `.clipped()`. Change the question inside `withAnimation(.spring(duration: 0.24, bounce: 0.12))`. SwiftUI animates the container's height and the footer moves with it, because layout is real.
- **Rows:** the §0.4 scaffold with selection *above* hover. Reuse the CheckboxGroup merge/split engine with R = 8.
- **Chip and arrow:** `ZStack { chip.opacity(showArrow ? 0 : 1); if showArrow { RoundedRectangle(cornerRadius: 8).fill(.foreground).overlay(Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(background)).transition(.scale(0.6).combined(with: .opacity)) } }.frame(width: 28, height: 28)`.
- **Other / freeText:** `TextField("", text:, axis: .vertical)` with `.textFieldStyle(.plain)` and `.lineLimit(1...)`. Enter vs Shift+Enter needs an `NSTextView` wrapper overriding `doCommand(by:)` for `insertNewline:` and `insertNewlineIgnoringFieldEditor:`. Auto-focus with `@FocusState` in `.onAppear` / `.task(id: qId)`.
- **Digit shortcuts:** `.onKeyPress(characters: .decimalDigits)` on the focused card, plus an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` gated on "this instance is frontmost/active" for focus-outside behavior.
- **⌘↵:** `.keyboardShortcut(.return, modifiers: .command)` on the Continue button.
- **Footer buttons:** `.transition(.scale(0.85).combined(with: .opacity))` with `.spring(duration: 0.08, bounce: 0)` and an `HStack` so siblings re-layout.
- **Accessibility:** apply §1's traits per row; `.accessibilityElement(children: .contain)` with `.accessibilityLabel(title)` on the rows group.

---

## 11. ChatMessage

Source: `chat-message__chat-message.tsx`

### Props
`from: "user" | "assistant"`, `files?: File[]`, `thumbnailSize` (default **64**), `time?` (user messages only), `actions?`, `children?`, `size?`.

### Wrapper
- A `motion.div` with `layout="position"` (earlier messages slide up when one is appended).
- **Enter:** opacity 0 → 1, **y 8 → 0**, **scale 0.96 → 1**, on **spring.moderate**.
- `transformOrigin`: `bottom right` (user) / `bottom left` (assistant). No exit animation.
- Class: `"group flex max-w-[80%] flex-col gap-1.5"`: max width **80%** of the transcript, gap **6** between files, bubble and meta.
- User: `items-end self-end`. Assistant: `items-start self-start`.

### Attachments
- `"flex flex-wrap gap-1.5"` (gap 6), right-aligned for the user and left-aligned for the assistant.
- `FileThumbnail` at **64×64** (§12).

### Text
- Class: `"whitespace-pre-wrap break-words"` + `py-2` (compact `py-1.5`) + subtitle type **14/20** (compact 13/18).
- **User:** `rounded-lg` (8) + `px-3.5` (14; compact `px-3` = 12) + `"text-pretty bg-[color-mix(in_oklab,var(--accent),var(--background)_45%)] text-foreground"`. The bubble fill is **55% accent + 45% background**, mixed in OKLab.
  - Bubble size: 8 + 20 + 8 = 36 tall for one line, 14 px side padding.
- **Assistant:** plain `text-foreground`. **No bubble**, no horizontal padding (8 vertical padding remains).
- Omitted when `children` is null or empty (attachment-only message).

### Meta row
- `"flex items-center gap-2 px-1 text-muted-foreground select-none"` + caption 12/16 (compact 11/14). Gap 8, horizontal padding 4.
- It always reserves its height.
- **Hidden until hover or focus:** `opacity-0 pointer-events-none transition-opacity duration-150`, becoming opacity 1 on `group-hover` or `group-focus-within` (150 ms, default curve). Always visible on touch-primary devices.
- Contents: time (`tabular-nums`, user only), then actions in `"flex items-center gap-0.5"` (gap 2). Actions are typically ghost icon buttons.

### SwiftUI translation notes
- `VStack(alignment: isUser ? .trailing : .leading, spacing: 6)` inside `.frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)`. Cap the width with `containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }` (macOS 14), or measure the transcript width.
- **Bubble:** `Text(msg).font(subtitle).padding(.horizontal, 14).padding(.vertical, 8).background(bubbleColor, in: .rect(cornerRadius: 8))`. Precompute `bubbleColor` as the OKLab mix of accent and background (or approximate with `Color.mix` on macOS 15 / sRGB lerp at 0.45).
- **Insert transition:** `.transition(.asymmetric(insertion: .opacity.combined(with: .scale(0.96, anchor: isUser ? .bottomTrailing : .bottomLeading)).combined(with: .offset(y: 8)), removal: .identity))`, appended inside `withAnimation(.spring(duration: 0.16, bounce: 0))`. A `LazyVStack` with `.defaultScrollAnchor(.bottom)` gives the slide-up.
- **Meta row:** `.opacity(hovered || focusWithin ? 1 : 0).allowsHitTesting(hovered || focusWithin).animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.15), value: hovered)`. Track hover with `.onHover` on the whole message.
- **Text selection:** add `.textSelection(.enabled)` for assistant text.

---

## 12. FileThumbnail

Source: `file-thumbnail__file-thumbnail.tsx`

- **Square** `size × size`.
- Class: `"relative shrink-0 overflow-hidden bg-accent outline-1 -outline-offset-1 outline-black/10 dark:outline-white/10 rounded-lg"`.
  - Radius 8, or an explicit `radius` prop (nested-radius callers).
  - Placeholder fill: `accent`.
  - **Hairline:** a 1 px **inset** outline painted *over* the preview, black 10% (light) / white 10% (dark). It takes no layout space.
- **Image:** object URL with `object-cover` fill.
- **PDF:** first page rendered at 2× the target width (pdfjs), shown as a cover image.
- **Pending** (image URL not ready, or PDF rendering): centered spinner, `"w-6 h-6 rounded-full border-2 border-border border-t-muted-foreground animate-spin"`.
  - 24×24, 2 px ring in `border` with the top quarter in `muted-foreground`, rotating 1 turn/s linearly.
  - `role="status"`, `aria-label "Loading preview"`.
- **Fallback** (unsupported type or failed PDF): centered Lucide-style document glyph.
  - Size `max(16, size × 0.35)`, stroke 1.5, `text-muted-foreground`.
  - Paths `M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z` and `M14 3v5h5`.
  - `role="img"`, `aria-label` = file name.
- No interaction or animation of its own.

### SwiftUI translation notes
- `ZStack { accent; content }.frame(width: s, height: s).clipShape(.rect(cornerRadius: r)).overlay(RoundedRectangle(cornerRadius: r).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))`.
- **Previews:** `QLThumbnailGenerator.shared.generateBestRepresentation(for: .init(fileAt: url, size: CGSize(width: s, height: s), scale: 2, representationTypes: .thumbnail))` handles images and PDFs natively (no pdfjs). For an image already in memory, use `Image(nsImage:).resizable().scaledToFill()`.
- **Spinner:** `Circle().trim(from: 0, to: 0.25).stroke(mutedFg, lineWidth: 2)` over `Circle().stroke(border, lineWidth: 2)`, 24 pt, `.rotationEffect` driven by a repeating `.linear(duration: 1)` animation. `ProgressView().controlSize(.small)` is the native alternative.
- **Fallback glyph:** `Image(systemName: "doc")` at `max(16, s × 0.35)`, `.light` weight.

---

## 13. InputMessage (chat composer)

Source: `input-message__input-message.tsx`

### Container
- Class: `"flex flex-col gap-1 p-2 transition-[box-shadow,color] duration-80"` + `surfaceClasses(2, 2)` + `rounded-xl`.
  - Padding **8**; regions stack with gap **4**.
  - **surface-2 fill + shadow-surface-2** at rest. Radius 12.
  - `cursor-text` when click-to-focus is on. Disabled: opacity 50%, no pointer.
- **Edge states:** the resting edge is shadow-2's 1 px ring. States **recolor that same ring** via an inline box-shadow (never thicker), each with the drop `0 1px 1px -0.5px var(--shadow-color)`. Precedence is drag > focus > hover.

| State | Ring |
|---|---|
| drag-over (files) | `0 0 0 1px #6B97FF` |
| textarea focused (`:focus-visible`; a textarea always matches) | `0 0 0 1px color-mix(in oklab, foreground 20%, transparent)` |
| hovered (click-to-focus on, not disabled) | `0 0 0 1px var(--border)` |
| rest | shadow-surface-2 |

  Transition 80 ms.
- Mouse-down anywhere that isn't a control focuses the textarea (`clickToFocus`, default true).
- Children render under `SurfaceProvider value={2}`.

### Region order (top → bottom)
Attachments → queue → textarea → action bar → suggestions.

### Collapsible regions
Attachments, queue and suggestions share the same behavior:
- `motion.div` with `overflow-hidden`. Height 0 ↔ **measured px** (the parent's `scrollHeight`) with opacity 0 ↔ 1, on **spring.moderate** (bounce 0).
- The suggestions exit animates **height only**, so the divider holds until the space closes.

### Attachments
- Shown when files are attached.
- Inner: `"flex flex-wrap gap-2 pb-1"` (gap 8, bottom 4).
- **Tile:** `FileThumbnail` at **80×80** (`filePreviewSize`), radius `nestedRadius(12, 8)` = **4**.
  - Enter: opacity 0 and scale 0.9 → 1 on spring.fast. Exit: the reverse on the 0.06 s tween.
  - `layout` slides siblings into the gap (`AnimatePresence mode="popLayout"`).
- **Remove badge:** `"absolute top-1 right-1 w-5 h-5 rounded-full bg-neutral-900 text-white opacity-0 group-hover/tile:opacity-100 transition-opacity duration-80 ... focus-visible:opacity-100 focus-visible:ring-1"`.
  - 20×20 circle, 4 px from the top-right, #171717 with a white X **12** stroke 2.5, fixed in both themes.
  - Hidden until tile hover (80 ms) or keyboard focus. Tooltip "Remove" (top).
- **Accept:** `image/png,image/jpeg,application/pdf` by default. Duplicates (name + size + mtime) are dropped; `maxFiles` truncates.

### Queue rows (built-in, when `status` + `onQueueChange` are provided and `showQueue` is on)
- Reorder group: `"flex flex-col gap-1 pb-1"` (gap 4).
- **QueuedRow:** `"group/qrow flex items-center gap-2 rounded-lg bg-muted"` + (`h-8 px-2.5` body 13/20 | compact `h-7 px-2` 12/18) + `"text-foreground select-none outline-none cursor-grab active:cursor-grabbing focus-visible:ring-1 ring-[#6B97FF]"`.
  - Height **32 / 28**, padding 10 / 8, `muted` fill, radius 8.
- **Contents:**
  - Optional Lucide `image` 13 + file count (muted, gap 2).
  - Label, truncating (text or "N attachment(s)").
  - Remove: `"h-5 w-5 rounded-full text-muted-foreground hover:text-foreground hover:bg-hover"`, 20×20, X **13** stroke 2.5. Revealed on row hover; always shown on touch.
- **Motion:** enter opacity 0 / scale 0.97 → 1 on spring.fast; exit on the 0.06 s tween; layout reflow on reorder. Reduced motion drops the scale.
- **Keys:** Enter / F2 edit (pulls the item back into the composer); Delete / Backspace remove; Alt+↑ / ↓ reorder; double-click edits; drag reorders (top dispatches next).

### Textarea
- Class: `"w-full resize-none rounded-none bg-transparent outline-none text-foreground placeholder:text-muted-foreground"`.
- Default: subtitle **14/20**, `px-2 py-2` (8). Compact: 13/18, `px-1.5 py-1.5` (6). Weight 400.
- **Auto-grow:** between `minRows` (1) × line height and `maxRows` (8) × line height; scrolls beyond that. **Height at 1 row = 36** (20 + 16).
- **Placeholder:** `"Ask me anything…"`. While dragging files: `"Drop files here to add to chat"`.
- **Ghost suggestion** (`placeholderSuggestion`, empty draft): an overlay replacing the placeholder, in the same typography and padding.
  - The suggestion text (muted, truncates) plus a **Tab keycap**: `"inline-flex shrink-0 -translate-y-px items-center rounded-[5px] border border-border bg-background px-1 font-sans text-muted-foreground"`.
  - Keycap height **18**, micro 11/14 (compact: height 16, 10/12), radius 5, 1 px border, padding 4, raised 1 px, gap 6.
- **Keys:**
  - Enter sends; Shift+Enter inserts a newline. IME composition is ignored.
  - Tab (empty draft + suggestion) fills the suggestion without sending.
  - **History:** ↑ with the caret on the first line recalls the previous sent message (stashing the draft); ↓ on the last line walks forward and finally restores the draft.

### Action bar
- `"flex items-center justify-between"`, gap 8.
- Compact: gap 6 plus a scoped override. Every button in the bar becomes height **24** (`h-6`), 28-wide icon buttons become **24** wide, and button text becomes caption-compact 11/14.
- Left slot: `"flex items-center gap-1.5 min-w-0"`. Right slot: `"flex items-center gap-1.5 shrink-0"` (gap 6), then the send button.
- Slots may be functions receiving `{ openFilePicker(acceptOverride?), files }`.
- **Send button:** `Button variant="primary" size="icon-sm"` → **28×28** (compact 24×24), radius 8.
  - Fill `foreground`, glyph `background`. Hover mixes 90% foreground; press 80% plus the 1 px collapse. Disabled: opacity 50%.
  - **Modes:** `send` (idle), `queue` (streaming with a draft), `stop` (streaming, empty draft, `onStop` provided).
  - Send and queue show Lucide `arrow-up` **19 px** (compact 15). Stop shows a **12×12 square, radius 3**, `bg-current`.
  - Swap: `AnimatePresence mode="wait"`. Opacity 0 and scale **0.6 → 1** on spring.fast; exit on the 0.06 s tween. Only stop ⇄ arrow animates.
  - `aria-label`: "Send" / "Queue message" / "Stop".
- **Default composer height:** 8 + 36 + 4 + 28 + 8 = **84** (compact 8 + 30 + 4 + 24 + 8 = **74**).

### Suggestions list (empty draft only)
- Region `"-mx-2 -mt-1 overflow-hidden"`. Listbox `"relative mt-2 flex flex-col border-t border-border/60 px-1.5 pt-1.5"`: a full-width 1 px divider at `border` 60%, then padding 6.
- One fluid-hover highlight (`bg-hover`, radius 8).
- **Rows:** `"relative flex cursor-pointer items-center gap-2"` + (`h-8 px-2.5` subtitle 14/20 | compact `h-7 px-2` 13/18) + `"text-muted-foreground transition-colors duration-80"`, foreground when active.
  - Height **32 / 28**. Text truncates.
- **Trailing icon** (13 px):
  - The active row shows Lucide `corner-down-left` (↵).
  - While nothing is active, row 0 shows a muted `arrow-down` (↓) in that slot.
  - Other rows: ↵ at opacity 0 (80 ms fade).
- **Keys** (focus stays in the textarea, via `aria-activedescendant`):
  - ↓ enters the list or moves down, **clamping** at the end (no wrap).
  - ↑ moves up and, from row 0, exits the list.
  - Enter fills the highlighted prompt; Esc clears the highlight. Click fills.
  - Typing collapses the list.

### Streaming and queue logic
- While `status == "streaming"`, submitting enqueues `{ id, text, files }` and clears the composer.
- On the **streaming → idle** edge, the head of the queue auto-dispatches via `onSend(text, files, { queuedId })`.
- A polite live region announces "Message sent. N still queued."

### SwiftUI translation notes
- **Container:** `VStack(spacing: 4) { ... }.padding(8).background(surface2, in: .rect(cornerRadius: 12))` with the ring overlay `RoundedRectangle(cornerRadius: 12).strokeBorder(edgeColor, lineWidth: 1)` (edge color per state) plus the small drop shadow.
- **Text input:** use an `NSTextView` wrapper rather than `TextEditor`. You need:
  - Enter vs Shift+Enter, via `textView(_:doCommandBy:)` for `insertNewline:`
  - IME `hasMarkedText()`
  - Caret-line detection for history
  - Tab capture
  - Auto-height: report `layoutManager.usedRect` height, clamped to 1–8 lines, and enable scrolling past the max
  
  Placeholder and ghost are an overlay `Text` with matching insets (`textContainerInset` 8, `lineFragmentPadding` 0).
- **Drop:** `.onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in ... }`. Filter by UTType (`.png`, `.jpeg`, `.pdf`).
- **Collapsible regions:** `if !files.isEmpty { filesRow.transition(.opacity.combined(with: .move(edge: .top))) }` inside `withAnimation(.spring(duration: 0.16, bounce: 0))`. SwiftUI's own layout animation covers the height change.
- **Tiles:** `.transition(.scale(0.9).combined(with: .opacity))`. Remove badge: `Circle().fill(Color(hex: 0x171717)).frame(width: 20, height: 20).overlay(Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)).opacity(tileHovered ? 1 : 0)`.
- **Queue reordering:** `List` with `.onMove` brings selection chrome; prefer a custom `VStack` with `DragGesture` plus the Alt+↑/↓ handlers.
- **Send button:** `.keyboardShortcut(.defaultAction)` is *not* appropriate (Enter is handled by the text view). Morph the glyph with `.contentTransition(.symbolEffect(.replace))` (macOS 14) or the explicit scale/opacity transition.
- **Suggestions:** a `VStack` below a 1 pt divider; highlight driven by the text view's key handling.
- **Accessibility:** `.accessibilityAddTraits(.isSelected)` on the active row; `AccessibilityNotification.Announcement` for dispatch messages.

---

## 14. QueuedStack (docs block for the queue as a Sonner-style pile above the composer)

Source: `queued-stack__queued-stack.tsx`

### Geometry constants
| Constant | Value |
|---|---|
| Card height | **44** (compact **38**) |
| Collapsed peek offset | `STACK_PEEK` **12** per card |
| Scale step per peek | `STACK_SCALE` **0.05** |
| Expanded gap | `STACK_GAP` **8** |
| Maximum visible peeks | `STACK_MAX_PEEK` **2** (front card + 2) |

- **Container:** `absolute inset-x-0 z-10`, positioned `bottom` px above the transcript bottom (typically composer height + 8).
  - Height animates on **spring.moderate** (bounce 0): collapsed = `cardH + min(n − 1, 2) × 12`; expanded = `n × cardH + (n − 1) × 8`.
  - The pile fades in on first fill and out when it empties.
- **Expanded when:** hovered, a pointer is down on a card, a drag is in progress, or (touch) tap-expanded.

### Card transforms (origin `bottom center`, z-index `100 − i`, dragged 200)
- **Collapsed:** `y = −min(i, 2) × 12`, `scale = 1 − min(i, 2) × 0.05`. Opacity 1 for i ≤ 2, otherwise 0.
- **Expanded:** `y = −i × (cardH + 8)`, scale 1. The dragged card: `y` follows the pointer (clamped to the stack), **scale 1.03**, `duration: 0`.
- Transitions on **spring.moderate**.
- Enter: from opacity 0, y +14, scale 0.96. Exit: opacity 0, scale 0.9, **0.12 s**.
- **Enqueue recoil** (count grows, previous count > 0, collapsed): the whole pile jumps to y −7, then springs to 0 with `{ type: "spring", duration: 0.42, bounce: 0.5 }`.

### Card
- Class: `"group/qm absolute bottom-0 left-10 right-10 flex select-none items-center bg-[color-mix(in_oklab,var(--accent),var(--background)_68%)] ... text-muted-foreground shadow-surface-3 rounded-lg"`.
  - Left and right gutters **40**.
  - Fill: **32% accent + 68% background** (OKLab).
  - **shadow-3**, radius 8.
  - Subtitle type 14/20 (compact 13/18), `muted-foreground`, single line with truncation.
- **Padding:**
  - Text-only: `pl-3.5 pr-1.5 gap-2` → 14 / 6 / 8.
  - With files: `pl-2` (8).
  - Compact: `pl-3` (12) or `pl-1.5` (6), `pr-1` (4), `gap-1.5` (6).
- **Attachments:** up to 3 thumbnails at **28** (compact 24), gap 4, radius `nestedRadius(8, 8)` = **0** (compact 1). A "+N" overflow tile in `bg-background/40`, micro 11/14, foreground.
- **Hover actions** (`hidden group-hover/qm:flex`; always shown on touch): Edit (Lucide `pencil` 14 stroke 2) and Remove (`x` 14 stroke 2.5).
  - Each **32×32**, radius 8, muted → `hover:bg-hover hover:text-foreground`, gap 4, 1 px focus ring. Tooltips "Edit" / "Remove".
  - Double-clicking a card also edits it.
- **Gutter marker** (left 40 × cardH, bottom-left): Lucide `corner-down-right` **16** stroke 2, muted, right-aligned with `pr-1`.
  - When n > 3, the total count appears to its left: 10 px semibold tabular, enters with opacity/scale 0.6 → 1 on spring.fast.
  - Tooltip "N queued message(s)" (left).
  - On touch when expanded: a collapse button with `chevron-down` 18 in the same slot.
- **Drag reorder** (expanded only): starts after **4 px** of vertical movement. Slot = `floor((stackBottom − pointerY) / (cardH + 8))`, clamped; `onQueueChange` fires live while dragging.
- **Morph:** text-only cards may share a `layoutId` with the sent bubble so dispatch morphs the card into the message. The `layoutId` is dropped during drags.

### SwiftUI translation notes
- `ZStack(alignment: .bottom) { ForEach(Array(queue.enumerated()), id: \.element.id) { i, item in card.frame(height: 44).offset(y: y(i)).scaleEffect(s(i), anchor: .bottom).opacity(o(i)).zIndex(Double(100 - i)) } }.padding(.horizontal, 40).frame(height: stackH, alignment: .bottom)`, with `.onHover { expanded = $0 }` and `.animation(.spring(duration: 0.16, bounce: 0), value: expanded)`.
- **Drag:** `DragGesture(minimumDistance: 4)` on cards when expanded; compute the slot from the location.
- **Recoil:** `withAnimation(.spring(duration: 0.42, bounce: 0.5)) { bump = 0 }` after setting `bump = -7` without animation.
- **Morph into the sent bubble:** `matchedGeometryEffect(id: item.id, in: ns)` on the card and the new `ChatMessage`.
- **Card fill:** precompute the OKLab mix (32% accent).

---

## Appendix: quick reference of shared motion values used above

| Use | Value |
|---|---|
| Row hover highlight move | spring.fast (0.08 s, critically damped); opacity 0.08 s tween |
| Focus ring move / exit | spring.fast / 0.06 s tween |
| Selection block (radio, checkbox, format menu, ask) | spring.moderate (0.16 s); opacity 0.08 s |
| Merge corner delay | 0.07–0.10 s; commit at 310 ms; split drop at 240 ms |
| Checkbox check draw / retract | 0.08 s easeOut / 0.04 s easeIn |
| Radio dot in / out | spring.fast from scale 0.3 / 0.04 s to scale 0.3 |
| Accordion chevron | rotate 90°, spring.fast |
| Accordion height open / close | spring.fast (opacity 0.06 s) / 0.06 s tween (opacity 0.04 s) |
| Accordion open fill | opacity 0.12 s; dims to 0.7 on non-open hover |
| Dialog overlay + panel | spring.slow; panel scale 0.97 → 1; exit 0.16 s tween |
| Popover / format menu | spring.moderate / spring.fast; y −4 → 0, scaleY 0.96 → 1 |
| Copy glyph swap | wait mode; out scale 0.8, in scale 0.6 + path draw 0.08 s; result holds 2000 ms |
| AskUserQuestions height morph | spring.slow |
| ChatMessage enter | spring.moderate; y 8, scale 0.96 |
| Composer regions | spring.moderate height + opacity |
| Label / border / icon-stroke color changes | 80 ms `cubic-bezier(0.4, 0, 0.2, 1)` |
