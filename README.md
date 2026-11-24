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

- **Apps covered:**
  - Editors: VS Code (also Insiders and VSCodium), Xcode, and JetBrains IDEs on the default macOS
    keymap (IntelliJ IDEA, PyCharm, WebStorm, GoLand, CLion, Android Studio).
  - Terminals: Terminal and iTerm2, plus zsh's line-editing keys.
  - Browsers: Chrome, Safari and Firefox.
  - Presenting: Keynote, PowerPoint, Zoom and Microsoft Teams.
  - Other: Finder, Figma, Slack and Notion, plus a few universal macOS shortcuts such as Copy and
    Undo.
- **Only documented defaults:** every entry comes from the vendor's own shortcut page for the Mac
  (listed under "Shortcut sources" below and in each dictionary's `sources`). A key the vendor
  gives two meanings, or documents only for Windows, is left out.
- **Unknown shortcuts:** a shortcut not in the dictionary shows only its keycap, because a wrong
  name is worse than none.
- **App detection:** `NSWorkspace.frontmostApplication`, which needs no permission. Live keys still
  need Input Monitoring.
- **Turning it off:** Keycaps › Shortcut Subtitles, or Settings.

**Shortcut sources.**

| App | Vendor page |
|---|---|
| VS Code | [macOS shortcuts PDF](https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf), [default keybindings](https://code.visualstudio.com/docs/reference/default-keybindings), [tips and tricks](https://code.visualstudio.com/docs/editing/getting-started/tips-and-tricks) (⌘J) |
| Xcode | [Xcode menu command shortcuts (archive)](https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html), [Running tests](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/05-running_tests.html) (⌘U) |
| JetBrains IDEs | [macOS default keymap](https://www.jetbrains.com/help/idea/reference-keymap-mac-default.html), [Android Studio](https://developer.android.com/studio/intro/keyboard-shortcuts) |
| Terminal | [Terminal keyboard shortcuts](https://support.apple.com/guide/terminal/keyboard-shortcuts-trmlshtcts/mac) |
| iTerm2 | [iTerm2 documentation](https://iterm2.com/documentation-one-page.html) |
| Shell keys | [zsh line editor](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html), `termios(4)` |
| Chrome | [Chrome keyboard shortcuts](https://support.google.com/chrome/answer/157179?hl=en&co=GENIE.Platform%3DDesktop) |
| Safari | [Safari keyboard shortcuts](https://support.apple.com/guide/safari/keyboard-and-other-shortcuts-cpsh003/mac) |
| Firefox | [Firefox keyboard shortcuts](https://support.mozilla.org/en-US/kb/keyboard-shortcuts-perform-firefox-tasks-quickly) |
| Finder, system-wide | [Mac keyboard shortcuts](https://support.apple.com/en-us/102650), [screenshots](https://support.apple.com/en-us/102646) |
| Keynote | [Keynote keyboard shortcuts](https://support.apple.com/guide/keynote/keyboard-shortcuts-tanfde4a3e6d/mac) |
| PowerPoint | [PowerPoint for Mac](https://support.microsoft.com/en-us/office/keyboard-shortcuts-in-powerpoint-for-mac-f25f92b3-b0a8-4c60-aec8-954b72aa81ad), [delivering presentations](https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-deliver-powerpoint-presentations) |
| Figma | Help center: [group/frame](https://help.figma.com/hc/en-us/articles/360039832054), [actions menu](https://help.figma.com/hc/en-us/articles/23570416033943-Use-the-actions-menu-in-Figma-Design), [hide UI](https://help.figma.com/hc/en-us/articles/41414918021271-Hide-or-minimize-the-UI), [visibility](https://help.figma.com/hc/en-us/articles/360041112614-Toggle-visibility-to-hide-layers), [lock](https://help.figma.com/hc/en-us/articles/360041596573-Lock-and-unlock-layers), [components](https://help.figma.com/hc/en-us/articles/360038663154-Create-components-to-reuse-in-designs), [images](https://help.figma.com/hc/en-us/articles/360040028034-Add-images-and-videos-to-designs) |
| Slack | [Slack keyboard shortcuts](https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts) |
| Notion | [Notion keyboard shortcuts](https://www.notion.com/help/keyboard-shortcuts) |
| Zoom | [Zoom hotkeys](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050) |
| Microsoft Teams | [Teams keyboard shortcuts](https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2) |

**Your own VS Code keybindings.** Keycaps › "Import VS Code keybindings…" opens a file panel
(starting in `~/Library/Application Support/Code/User`); the sandbox can read only the file you
pick. Keyray reads it as VS Code does (comments and trailing commas allowed) and keeps a copy in
its settings, so re-import after changing the file. In VS Code, VS Code Insiders and VSCodium:

- **Your bindings win.** `cmd+p` bound to `workbench.action.files.openRecent` shows "Open Recent".
  Common commands have hand-written names; others are spelled out from the command id.
- **Removed defaults** (`"-command"`) show no subtitle unless you bind the key again.
- **`when` clauses:** Keyray can't see VS Code's context, so a key that does different things in
  different places (your terminal binding vs. the default in the editor) shows no subtitle. A
  `when` binding on a key nothing else uses is named.
- **Skipped:** two-step chords (`cmd+k cmd+s`) and keys it can't read. The import summary counts
  them.
- **Undo:** "Remove imported keybindings" in the same menu.

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

## Agents

Agents that drive the Mac (for a screen recording or a live demo) can tell Keyray what they are
doing. Their keycaps carry a small 🤖 badge with the agent's name, so viewers can tell agent input
from a person's. No permission is needed, and it works in any keycap mode (turn it off under
Settings › Agents). Input never leaves the Mac: the CLI and MCP server reach the running app with a
per-user distributed notification, and `keyray://` URLs go through Launch Services. Keys are
limited to 32 characters, captions to 120 and agent names to 24, control and bidi characters are
removed, and the app shows at most 8 at once, then 4 a second.

```sh
mkdir -p ~/.local/bin && ln -sf /Applications/Keyray.app/Contents/MacOS/Keyray ~/.local/bin/keyray
keyray show ⌘K --caption "Open the command bar" --source claude
keyray show cmd+shift+p --caption "Command Palette"      # words become ⇧⌘P
keyray caption "npm test" --source codex
open -g "keyray://show?keys=cmd%2Bs&caption=Save&source=playwright"
```

`keyray show` starts the app if it is not running. Settings › Agents copies both commands below.

MCP (tools `show_keys` and `show_caption`), for Claude Code, Codex or any MCP client:

```sh
claude mcp add keyray -- /Applications/Keyray.app/Contents/MacOS/Keyray mcp
```

Or have Claude Code caption every shell command it runs, with a `PreToolUse` hook in
`.claude/settings.json`:

```json
{ "hooks": { "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command",
  "command": "/Applications/Keyray.app/Contents/MacOS/Keyray caption --source claude-code \"$(jq -r .tool_input.command | head -c 200)\"" } ] } ] } }
```

Keys an agent types with CGEventPost, System Events or cliclick show as ordinary keycaps if the
posting app has Accessibility. Keys sent with Playwright/CDP, or typed into a terminal through a
pty, never become macOS key events, so the script should also call `keyray show`.

## Build

Requires macOS 14 or later and Swift 6. With only the Command Line Tools 27.2 installed (no Xcode),
use the 26.5 SDK and the native build system:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
SWIFT_BUILD_FLAGS="--build-system native" scripts/bundle.sh   # -> build/Keyray.app
open build/Keyray.app
```

`scripts/bundle.sh` builds the release binary, writes `Info.plist` (`LSUIElement`, so there is no
Dock icon), copies the app icon (`Resources/AppIcon.icns`, made from the hand-drawn
`Resources/AppIcon.svg` by `scripts/icon.sh`), and signs ad hoc with `--options runtime` and `Resources/Keyray.entitlements`:
`com.apple.security.app-sandbox`, plus `com.apple.security.files.user-selected.read-only` for the
keybindings import. Check the result with:

```sh
codesign -dvv --entitlements - build/Keyray.app   # flags=0x10002(adhoc,runtime), app-sandbox
```

An ad hoc build has a new code identity on every rebuild, so macOS drops its Input Monitoring
grant. For an install that keeps the grant across updates, `scripts/release.sh` signs with
Developer ID (secure timestamp, hardened runtime), notarizes with `notarytool` using an App Store
Connect API key, staples the ticket and checks `spctl` reports `source=Notarized Developer ID`:

```sh
NOTARY_ISSUER=<issuer id> scripts/release.sh   # -> build/Keyray.app, build/Keyray-<version>.zip
```

See the script header for the key, identity and keychain defaults.

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
