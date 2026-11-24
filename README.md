# Softcut

A Mac screen recorder that produces a finished video with no editing step. Stop the recording and Softcut
renders an MP4 with a styled background, smooth cursor, zoom on clicks and click ripples, then opens it in an editor
where you can change anything.

## Use it

```bash
scripts/build-app.sh
open dist/Softcut.app
```

When Softcut opens, a **recording bar** floats at the bottom of the screen on every desktop:

- **Display, Window or Area.** Display records the screen the bar is on. Window lets you hover over any window and click
  it; the video then shows only that window, with other windows out of the way. Area lets you drag a rectangle.
  Window and Area record the whole display and start the edit cropped to what you picked, so you can widen it later in
  the editor's Crop control.
- **Camera, microphone and system audio** each have a chip: pick a specific camera or microphone from the list, or turn it off.
- **Record** (or Return) starts after a three-second countdown. The bar then shrinks to a timer and a Stop button, and is
  never part of the video. **Control + Option + R** starts and stops from anywhere.
- The folder button opens your recordings, the gear holds the zoom options, and the cross (or Esc) closes the bar. Softcut
  stays in the menu bar; click its Dock icon or choose **Show Recording Bar** to bring the bar back.

Softcut also lives in the menu bar. The first start asks for Screen Recording access; turn Softcut on in System Settings >
Privacy & Security > Screen Recording, then reopen it.

Menu options and the permission each one needs:

| Option | What it does | Permission |
| --- | --- | --- |
| Microphone | Records your voice | Microphone |
| System audio | Records sounds from your Mac | Screen Recording |
| Webcam | Shows you in a circle in the bottom-right corner; it shrinks while zoomed in | Camera |
| Zoom on clicks | Zooms in on each click or group of clicks | none |
| Zoom on typing | Zooms in while you type and follows the text caret | Input Monitoring; Accessibility is optional and finds the caret |

Without Accessibility, typing still zooms, but the camera aims at the mouse instead of the caret. Without
Input Monitoring the recording works but nothing zooms on typing.

When you stop, the recording opens in the editor, already given Softcut's automatic edit. Nothing is exported until
you choose Export. Raw recordings stay in `~/Movies/Softcut/Recordings/`, and your edits are saved beside each one as
`edit.json`, so you can close the editor and come back. **Recordings…** in the menu lists everything you have recorded.

## The editor

Four rounded blocks on a dark frame: a side panel on the left (Media, Chat and Mockups) with the window's buttons in its corner, the
preview in the middle (the same renderer as export, so what you see is what you get; click it or press Space to play) under the
recording switcher, ⋯ and Export, settings on the right under their pane icons, and the timeline underneath. Crop, hidden areas and a zoom's framing are placed by dragging on the video itself. Every change is saved automatically and can be undone with ⌘Z.

| Pane | What you can change |
| --- | --- |
| Look | Aspect ratio (auto, 16:9, 4:3, 1:1, 4:5, 9:16); padding, corner radius; background as a gradient, one of 12 wallpapers, a solid color or your own picture or SVG; shadow; a device frame (laptop, browser window, monitor, phone); crop to any part of the screen |
| Cursor | Show or hide; dark (default, black with a white outline), as recorded, arrow, dot, ring or crosshair; size; smooth movement; lean while moving; click effect (off by default) and its color |
| Camera | Show and mirror the webcam; layout: bubble, split screen (camera right, left, above or below, with a share slider) or cut-out (you without your background, standing over the screen); bubble shape, corner, size, margin, size while zoomed in |
| Zoom | Default zoom amounts, redo zooms from clicks and typing, the list of zooms, and for the selected one: amount, camera zoom or **magnifier lens**, follow cursor or fixed point, where it aims (click on a still of the screen), instant or eased; motion blur while the camera moves |
| Clip | Speed of the selected clip (0.5× to 8×), cut it out, split at the playhead, restore everything that was cut |
| Blur | Hide part of the screen for a while: blur, pixelate or cover with a plate. Drag the rectangle on a still of the screen; set its time on the timeline |
| Audio | Volume, mute microphone or system audio; **background music** (your file, repeated, with its own volume, faded in and out); **click sounds**; **voice-over** recorded from the playhead while the video plays silently |
| Captions | Captions made from your speech on this Mac (Apple's speech recognition, nothing is sent anywhere), edited line by line; size, position, plate, bold, color; export as an `.srt` subtitle file |
| Export | MP4 (720p to 4K, 30 or 60 fps, H.264 or HEVC, at a high fixed bitrate: about 44 Mbps for H.264 at 2560 wide and 60 fps, or 25 Mbps for HEVC, which looks better for its size) or an animated GIF, then Export |

The pill at the top centre is a menu of all your recordings; pick one to open it, or the house button for the Recordings
window. The Media tab lists the recordings in this video (click one to jump to it) and your other recordings: click
one, or **Add a recording…**, to attach it to the end of the same video, so one project can cover several takes. A clip can be cut (⌘X) or copied (⌘C) and
pasted at the playhead (⌘V) or at the end of the video (⇧⌘V), so reordering is cut and paste. Raw recordings are never
changed: attached recordings are remembered by their location, and everything you edit is saved in `edit.json`.

**⌘K**, or Shortcuts in the ⋯ menu above the video, opens every editor command and pane, searchable, with its shortcut.

### Mockups

The Mockups tab shows the video on the screen of a 3D device: four MacBooks and four iPhones, modelled in Blender and
rendered live. Pick a device, then how it arrives; the choice plays from the start so you can see it right away, and
**Remove** takes the video out again. It goes into the export like everything else, and the Shadow settings, zooms and
background all apply.

| Family | Devices | How it arrives |
|---|---|---|
| MacBook | Air 13 (Midnight), Air 15 (Starlight), Pro 14 (Space Black), Pro 16 (Silver) | Open from above, Slide in and open, Hero reveal, Whip turn, Slow orbit, Idle |
| iPhone | 17 (Lavender), Air (Sky Blue), 18 Pro (Burgundy), 18 Pro Max (Silver) | Spin reveal, Rise, Slide in, Stand up, Slow orbit, Idle |

The models are not in this repository; without them the rest of the app works and the tab has no devices. They are made by `scripts/mockups/build_mockups.py`, from Apple's published dimensions and proportions measured
from its product photographs, with no logos. They are detailed hard-surface models: continuous-curvature corners, real
bevels, individual keycaps with legends, a recessed keyboard well, the trackpad gap, speaker grilles, hinge, ports, side
buttons, antenna lines and multi-part camera lenses. Each device's folder in `Mockups/` has the Blender source
(`model.blend`, self-contained, with named parts, the motions as actions and a studio and camera, so it renders in Cycles
as it stands), the export the app draws (`model.usdz`), its screen position, exposure and baked motions (`device.json`),
and its picture in the tab (`thumbnail.png`).

The motions follow how product films are cut. Each part has its own timing and they overlap, quick moves end in long
settles, a laptop's display wakes as its lid opens, and after arriving the picture keeps a very slow camera drift instead of
freezing. Fast moves get real motion blur, from a short shutter sampled up to 16 times a frame, and zooms wait until the
device has arrived.

Devices are drawn at twice the canvas size and scaled down with a Lanczos filter, so the video's small text, the key legends
and thin metal highlights stay clean. A sharp recording keeps its own pixels where it can: a 3456 x 2234 recording on the
MacBook Pro 16 reaches the screen unscaled.

All of them are lit by `Mockups/studio.hdr`, an HDR photo studio made by the same script, with an exposure set per finish.
The screen shows the video's exact colors with only a faint sheen on top, and a laptop's deck picks up a soft glow of the
video's light. To rebuild them:

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python scripts/mockups/build_mockups.py -- Mockups
.build/debug/softcut-cli mockup-thumbnails
```

The aspect ratio's Auto means 16:10 for a MacBook and square for an iPhone.

### Chat

The Chat tab makes edits from plain sentences: "put it in a MacBook Air 15 sliding in", "padding 10% and use the Glacier
wallpaper", "split at 0:12", "hide the cursor". Say "help" for the full list. **It isn't an AI model.** It matches fixed
commands on your Mac, nothing leaves the computer, and it says so when it doesn't understand. Each change can be undone
with ⌘Z, or from the arrow under the reply. Return sends and Shift-Return starts a new line.

The timeline has a track for the video's clips (each a filmstrip of its recording), one for zooms and one for blurred
areas, each with a header card whose switches mute the recorded sound, hide the cursor, or switch every zoom or blurred
area off at once. The tools above it split, cut, copy and paste clips, add zooms, blurs and caption lines, undo and redo,
and change the timeline's scale. Drag the ends of a clip to trim it;
drag a zoom to move it, or its ends to change its length; drag the red playhead (or the ruler) to scrub. White dots
mark clicks. Keys: Space play or pause, **S** split, **Z** add a zoom at the playhead, **B** add a blur region, Delete
removes the selected clip, zoom or blur region, ⌘Z and ⇧⌘Z undo and redo. The ⋯ menu goes back to the automatic edit.

## The automatic edit

Most recordings should need no editing, so the automatic edit follows the rules Screen Studio uses. They were measured
from Screen Studio's own projects for the same recordings, and a test checks Softcut makes the same zooms for them:

- Each left click asks for a 2× zoom. Zooms less than 2 s apart become one, so a stretch of clicking is one long zoom,
  not a zoom in and out at every click. The click that stops the recording is ignored. The zooms end exactly when
  Screen Studio's do and start 0.3 s earlier, to leave room for the eased zoom.
- Zooming magnifies the whole picture, so a zoomed-in screen fills the video edge to edge, as in Screen Studio. Near
  the screen's edges the camera stops short of letting any background show beside the screen.
- A zoom's starting point can be moved in the Zoom pane (drag the crosshair on the still). With **Follow cursor** it
  starts there and then follows the cursor; with **Fixed point** it stays there.
- Every camera move, zooming in or out or sliding across while zoomed, moves at a steady pace with brief soft ends,
  so nothing bounces or overshoots. A zoom takes 0.7 s and a slide 0.6 s. Turn on **Easing** in the Zoom pane for
  moves that start and end softly and are fastest in the middle instead. Zooming happens about the one point that stays in the same place on screen, so the
  spot being zoomed toward glides steadily into place instead of drifting out and back.
- An automatic zoom starts 0.85 s before its click so the picture is still when the click lands, and ends 2.5 s after the button
  comes up. Inside a zoom the camera holds still while the mouse stays near the middle of the picture, sets off for
  the next group of clicks just in time to be there for the first of them, and follows the mouse to where it comes to
  rest if it strays far without clicking. Where it points and when it moves were matched against Screen Studio's own
  camera, recovered frame by frame from its export of the same recording (`softcut-cli trace-camera`).
- The cursor glides. Hand movement is split into rests and movements: while the mouse rests the cursor holds
  perfectly still, and each movement from one stop to the next becomes one clean curve along the route the mouse took,
  wobbles and overshoot-and-correct hooks straightened out, with speed that rises and falls smoothly. It starts when
  the mouse starts, lands where it stops, sits exactly on every click, never overshoots, and leans a little as it moves
  sideways. Click ripples are off unless you turn them on.
- Motion blur streaks the picture during camera moves about as much as Screen Studio does, never more than 2% of the
  picture's width.

When you stop recording, Softcut shows the finished video straight away, already edited, playing in a window with two
buttons: **Save video** (to `~/Movies/Softcut/Exports/` unless you choose somewhere else) and **Edit**, which opens the
editor if you want to change anything.

Stretches of typing play three times faster, so the video does not wait for every key. This needs Input Monitoring
(only the moments keys are pressed are recorded, never which keys), and is skipped when the microphone was on, so
narration is never sped up. In the editor each sped-up stretch is its own clip, with its speed in the Clip pane.

To check an edit without watching it, `softcut-cli check FOLDER` reports how many clicks are in view when they happen,
how often the camera moves, whether it ever wobbles, and how far the cursor lands from each click.
`softcut-cli import-screenstudio PROJECT.screenstudio FOLDER` turns a Screen Studio recording into a Softcut one (the
project is only read), so both apps' automatic edits of the same recording can be compared side by side.
`softcut-cli trace-camera EXPORT.mp4 FOLDER` recovers another app's camera from its exported video of that recording,
and `softcut-cli compare-trace TRACE.csv FOLDER` scores Softcut's camera against it.

## Command line

```bash
swift build
.build/debug/softcut-cli demo out/demo                 # synthetic recording, no permission needed
.build/debug/softcut-cli edit "path/to/recording"      # re-render a saved recording
.build/debug/softcut-cli record --seconds 10 --mic     # record from the terminal
.build/debug/softcut-cli frames video.mp4 out/frames 1.0 3.5   # save stills to inspect a render
.build/debug/softcut-cli snapshot out/demo out/editor.png --tab zoom --time 4   # draw the editor to a picture
.build/debug/softcut-cli check out/demo                # measure how watchable the edit is
.build/debug/softcut-cli stills out/demo out/stills 1.5 4.0   # render single frames of the edit
.build/debug/softcut-cli import-screenstudio "My Recording.screenstudio" out/imported
.build/debug/softcut-cli fluid-gallery out/gallery.png   # every interface component on one page
.build/debug/softcut-cli library-snapshot out out/library.png   # draw the recordings window
.build/debug/softcut-cli export out/demo out/video.mp4   # export the saved edit, as the app's Export button does
.build/debug/softcut-cli mockup-still macbook-air-15 idle 0 out/device.png   # one frame of a device on its own
.build/debug/softcut-cli mockup-thumbnails               # draw the pictures in the Mockups tab
```

To open the app straight on a recording: `open dist/Softcut.app --args --edit "path/to/recording"`.

Record with `--webcam` and `--typing` to turn those on. Edit options: `--zoom 2.5`, `--no-zoom`, `--no-typing-zoom`,
`--no-webcam`, `--no-cursor`, `--no-trim`, `--speed-idle`, `--width 3840`.

## How it works

| Stage | Where | What it does |
| --- | --- | --- |
| Capture | `Sources/SoftcutCore/Capture` | ScreenCaptureKit records the display without the cursor, plus optional system audio and microphone. The webcam goes to its own file. Mouse position (120 Hz), clicks, scrolls, cursor shapes, key-press times and the text caret are logged separately on the same clock. |
| Edit | `Sources/SoftcutCore/Edit` | `AutoEditor` turns the input log into a plan: spring-smoothed cursor, zoom segments from click groups and typing bursts, a camera that follows the cursor (or the caret while typing) only near the edge of the view, and trimmed idle ends. |
| Project | `Sources/SoftcutCore/Edit/EditProject.swift` | Everything a person can change (look, zooms, cuts, audio), with plain functions to add, move, trim, split and cut. It is saved as `edit.json` and read back, tolerating files from older or newer versions. |
| Editor | `Sources/SoftcutUI` | The SwiftUI editor: `EditorModel` (undo, autosave, live preview), the inspector, the timeline, the recordings library. |
| Render | `Sources/SoftcutCore/Render` | A custom `AVVideoCompositing` draws each frame with Core Image (background, shadow, cropped screen, cursor, ripples, webcam circle, rounded corners) and exports MP4. |

A recording is a plain folder: `screen.mov`, `webcam.mov` (optional), `input.json`, `manifest.json`, `cursors/`.
Times are seconds from the first screen frame; positions are normalized to the display. The manifest stores how far
the webcam's first frame is from the screen's, and the renderer uses that to line the two up.

## Interface

Every control in Softcut is a SwiftUI port of [Fluid Functionalism](https://www.fluidfunctionalism.com), the
React/shadcn component library by Micka Touillaud, used under its MIT license (`reference/fluid-registry/LICENSE`).
The ports live in `Sources/SoftcutUI/Fluid`:

| File | Components |
| --- | --- |
| `Fluid.swift` | Tokens (surfaces 1–8 and their layered shadows, interaction fills, motion tiers, type roles, the size ladder, radii) and the fluid hover |
| `FluidControls.swift` | Button (primary, secondary, tertiary, ghost, icon, loading), Switch, Slider (scrubber and compact) |
| `FluidTabs.swift` | Tabs (segmented) and TabsSubtle, including icon tabs whose label slides open |
| `FluidMenus.swift` | Select, Dropdown, MenuItem |
| `FluidOverlays.swift` | Dialog, CommandMenu, Combobox |
| `FluidFeedback.swift` | Badge, Banner, Tooltip, Card list, CarouselDots, ThinkingIndicator, ThinkingSteps |
| `FluidForms.swift` | CheckboxGroup, RadioGroup, Accordion, InputGroup field, InputCopy, Table, ScrollArea |
| `FluidColor.swift` | ColorPicker, ColorPickerPopover, ColorSwatch, ColorTile |
| `FluidSidebar.swift` | Sidebar (resizable, collapsible) and SidebarMenu |
| `FluidOptionCards.swift` | Option cards and icon tiles, built from Fluid's Card and selection marker |
| `FluidPopup.swift` | The floating panel every popup, menu and tooltip opens in |
| `FluidChat.swift` | ChatMessage and InputMessage (the composer), without attachments, queued messages or streaming |

The editor's settings are a floating panel with a row of pane icons at its top. Two panes have no icon: picking a clip on
the timeline opens Clip, and the Export button opens Export. Each pane's main
choices (background, cursor style, camera layout, zoom style, blur type, export format) are option cards
(`FluidOptionCards.swift`): an icon tile, a title and a line of explanation, with a purple ring on the chosen one.
Softcut themes Fluid's accent (its focus-ring color) to one brand purple, used for the Export button, switches and the chosen
option.

`softcut-cli fluid-gallery out.png` draws all of them on one page. The library's measurements, colors and timings are
written up in `reference/fluid-spec-a.md`, `-b.md` and `-c.md`. Softcut uses the system font at Inter's weights (400,
550, 700) rather than bundling Inter. The library's AI-chat pieces (chat message, composer, ask-user questions, queued
stack, file thumbnail) and its mobile drawer have no place in a desktop screen recorder and are not ported.

## Privacy

Zoom on typing records **when** keys are pressed and whether Command or Control was held. It never records which
keys. The event type holds only a time and a flag, and a test checks that. The caret position is read only while
you are typing, from the Accessibility API, and only its screen position is kept.

Captions use Apple's speech recognition in its on-device mode only. If a language cannot be recognized on this Mac
without sending sound to Apple, Softcut says so and does not fall back to the network. The first time you make captions or
record a voice-over, macOS asks for Speech Recognition or Microphone access.

## Known limits

- Voice-overs and music are placed by time in the finished video, so if you cut or reorder clips afterwards they
  stay where they were (captions and click sounds follow the clips). There is no timeline lane for them yet; they
  are edited in the Audio pane.
- The cut-out layout depends on Apple's person segmentation and works best with even lighting. If it finds no person
  in the picture, the camera falls back to the bubble. Captions are timed per line, not per word, and shortcut keys
  are never shown as captions.
- Wallpapers are drawn from short SVG descriptions (about 1 KB each), so there are no image files to ship; their film
  grain is added when the frame is drawn.
- A still mouse is not proof that nothing is happening on screen, so idle speed-up is off by default and idle
  trimming only touches the start and end. Typing counts as activity.
- Some apps do not report a caret position (for example, many custom-drawn editors). Typing zoom then aims at the mouse.
- The webcam bubble sits over the bottom-right corner of the screen area, so it can cover things there.
- Window recording keeps the crop where the window was when you started, so if you move the window while recording, it
  moves inside that frame. Recording an iPhone or iPad is not supported.
- Idle trimming is skipped when audio is recorded, so narration is never cut.
- One display per recording; no window-only capture or device recording yet. The webcam has no audio of its own; the microphone track comes from the screen recording.
- A device's arrival plays over the first seconds of the video (up to about 5), with the recording running on its screen,
  and a device applies to the whole project, not to part of it.
- A landscape recording on an iPhone is cropped at the sides to fill its screen; use Crop to choose what shows. Split
  camera layouts become a bubble on the device's screen.
- The Mockups are close likenesses of Apple's products and use their names. Check that before shipping Softcut
  commercially.
- Building and exporting need access to the system temp folder and the hardware video encoder, so run them outside
  restrictive sandboxes.

## License

MIT, see `LICENSE`. The interface is ported from Fluid Functionalism, © Micka Touillaud, also MIT
(`reference/fluid-registry/LICENSE`).
