# Keyray (키레이)

A presentation cursor highlighter for macOS: a menu-bar app that makes the cursor, clicks and
shortcuts easy to see while presenting, teaching or recording. Its mascot is Hotaru. The bundle id
is `com.s3onghyun.keyray`; the project was developed under the codename cursor-proto.

It is a native Swift app built for the Mac App Store's rules from day one: App Sandbox on,
Hardened Runtime on, no Accessibility and no Screen Recording permission.

## What it does

| Feature | How it works | Permission |
|---|---|---|
| Cursor ring: size, line, color, opacity; hides when idle; "only while clicking" mode | Click-through overlay window per display, Core Animation layer | none |
| Click ripples, separate colors for left, right and middle | `NSEvent` global mouse monitor | none |
| Laser pointer with a vanishing trail | same monitor; tapered trail drawn only while it fades | none |
| Temporary ink: pen, arrow, highlighter; fades on its own | overlay takes the mouse while drawing, then gives it back | none |
| Keycaps: shortcuts only or all keys, repeat count (⌘Z ×3), draggable position, hides the app's own shortcuts | listen-only `CGEventTap` | Input Monitoring |
| Global shortcuts, everything off at once | Carbon `RegisterEventHotKey` | none |
| All Spaces, full-screen apps, every display | `.canJoinAllSpaces`, `.fullScreenAuxiliary`, one window per `NSScreen` | none |
| Steps aside for permission prompts | hides while System Settings, SecurityAgent or a TCC prompt is frontmost, and while asking for Input Monitoring | none |

With the overlays switched off (⌃⌥⌘O, or while a permission prompt is in front) the app removes its
mouse monitors, so it receives no events and uses no CPU.

### Themes

Menu › Theme (or Settings) switches the look of every overlay; behavior and timing stay the same.
Hotaru is the theme on first launch.

| Theme | Ring | Click | Laser | Keycaps |
|---|---|---|---|---|
| Hotaru (default) | a pool of light from Hotaru's tail lantern, which sits on the ring's rim | the lantern flashes (about 120 ms up, 400 ms back), short rays, a beam to the click | the lantern is the laser point, its amber light the trail | night-ink plaques; subtitle as a lantern-lit caption |
| Cyberpunk | neon reticle | target-lock brackets labeled LMB, RMB, MMB | neon beam | terminal keycaps; subtitle as a `// comment` |
| Minimal | colored ring | ripple, color per button | dot and tapered trail | dark glass; plain subtitle |

Hotaru is a hand-drawn firefly (direction art from Claude Design, implemented in code). It rests
beside the pointer, beats its wings while moving, tilts its head at right and middle clicks, holds
its light as the laser pointer, dozes with the lantern dimmed to about 15% when the cursor is
still, and waves hello once on first launch. Brush & Ink and Keynote Glow are parked: their code
stays (`Theme.isParked`), but they are not offered in the menu or Settings.

**Future theme ideas:** a solar-system theme family (owner idea, for later).

### Shortcut Subtitles

Keycaps also say what a shortcut does in the frontmost app: ⇧⌘P in VS Code shows "Command
Palette", ⌃R in Terminal shows "Search History". The names come from bundled dictionaries of each
app's documented default key bindings (`ShortcutSubtitles` in `KeyrayCore`).

- **Apps covered:** VS Code, Xcode, Terminal, iTerm2, Chrome, Safari, Finder, Keynote, PowerPoint
  and Figma, plus a few universal macOS shortcuts such as Copy and Undo.
- **Unknown shortcuts:** a shortcut not in the dictionary shows only its keycap, because a wrong
  name is worse than none.
- **App detection:** `NSWorkspace.frontmostApplication`, which needs no permission. Live keys still
  need Input Monitoring.
- **Turning it off:** Keycaps › Shortcut Subtitles, or Settings.

For demos without Input Monitoring:

- **Menu:** Keycaps › "Preview subtitles for…" plays a sample through the real feed.
- **Launch argument:**

  ```sh
  open -g build/Keyray.app --args --preview-keycaps com.microsoft.VSCode 2
  ```

  This plays the sample for that app after 2 s.

The theme sets its own colors; the color pickers apply to Minimal. The companion is drawn with
Core Graphics, and its poses come from an event-driven animator in `KeyrayCore`, so a still
cursor needs no timer.

### Shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥⌘O | all overlays on/off |
| ⌃⌥⌘L | laser pointer |
| ⌃⌥⌘D | start/stop drawing |
| ⌃⌥⌘1 / 2 / 3 | pen / arrow / highlighter (starts drawing) |
| ⌃⌥⌘X | clear ink |
| ⌃⌥⌘K | keycaps on/off |
| Esc | stop drawing (registered only while drawing) |

### Drawing and click-through

By default ("overlay takes the mouse, gives it back"), starting to draw lets the overlay take
mouse input so strokes never click or drag the app underneath. 2.5 s after the last stroke (or on
Esc or ⌃⌥⌘D) the overlay is click-through again, while the ink stays visible and fades
(3 s hold, 1 s fade by default). Ink on screen never blocks clicks.

The other mode, "clicks always pass through", never takes the mouse: strokes follow drags that
also reach the app underneath. It suits apps where dragging does nothing.

### Screen sharing

Overlays are ordinary windows, so they appear in recordings and shares of the **entire screen**.
A single-window or single-tab share (Zoom, Meet, Teams) carries only that app's window, so the
overlays are not in it. The menu's "Screen sharing tips…" says this to the user.

## Build

Requires macOS 14 or later and Swift 6. With only the Command Line Tools 27.2 installed (no Xcode),
use the 26.5 SDK and the native build system:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
SWIFT_BUILD_FLAGS="--build-system native" scripts/bundle.sh   # -> build/Keyray.app
open build/Keyray.app
```

`scripts/bundle.sh` builds the release binary, writes `Info.plist` (`LSUIElement`, so there is no
Dock icon), and signs ad hoc with `--options runtime` and `Resources/Keyray.entitlements`,
which contains only `com.apple.security.app-sandbox`. Check the result with:

```sh
codesign -dvv --entitlements - build/Keyray.app   # flags=0x10002(adhoc,runtime), app-sandbox
```

## Tests

The pure logic (settings decoding and clamping, ripple, ink and idle timing, the laser trail,
arrowheads, keycap labels, repeat counting, typing runs and hidden shortcuts) lives in
`KeyrayCore` and is covered by Swift Testing:

```sh
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  swift test --build-system native -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F
```

## Permissions

The ring, ripples, laser, ink, shortcuts and multi-display support need **no** permission.

Keycaps need **Input Monitoring**. Keycaps are off until you choose a keycap mode in the menu;
then the app checks `CGPreflightListenEventAccess()` and, if it is not granted, opens a short
explanation with three steps:

1. Click "Ask macOS" (calls `CGRequestListenEventAccess()`; the overlays hide while the prompt is up).
2. Turn the app on in System Settings › Privacy & Security › Input Monitoring.
3. Click "Check again". If it still fails, quit and reopen the app.

The tap is listen-only: it cannot change, block or create events, nothing is stored or sent, and
macOS withholds secure-input (password) keystrokes from it. "Preview keycaps" in the menu shows
sample keycaps without any permission, for checking the look and position.

## Logs

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "com.s3onghyun.keyray"'
```

The launch line reports `sandboxed=true` when the App Sandbox is active.
