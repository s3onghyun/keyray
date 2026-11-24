import KeyrayCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $store.settings.theme) {
                    ForEach(Theme.offered, id: \.self) { Text($0.title).tag($0) }
                }
                if store.settings.theme != .minimal {
                    Text("The theme sets its own colors; the color pickers below apply to Minimal.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Cursor ring") {
                Picker("Show", selection: $store.settings.ringMode) {
                    Text("Always").tag(RingMode.always)
                    Text("Only while clicking").tag(RingMode.clickOnly)
                    Text("Off").tag(RingMode.off)
                }
                slider("Size", $store.settings.ringDiameter, AppSettings.ringDiameterRange, "%.0f pt")
                slider("Line", $store.settings.ringLineWidth, AppSettings.ringLineWidthRange, "%.0f pt")
                ColorPicker("Color", selection: color($store.settings.ringColor), supportsOpacity: false)
                slider("Opacity", $store.settings.ringOpacity, 0.1...1, "%.0f%%", scale: 100)
                slider("Hide when idle after", $store.settings.idleHideSeconds, AppSettings.idleHideRange, "%.1f s (0 = never)")
            }
            Section("Click ripples") {
                Toggle("Show ripples", isOn: $store.settings.ripplesEnabled)
                ColorPicker("Left click", selection: color($store.settings.rippleLeft), supportsOpacity: false)
                ColorPicker("Right click", selection: color($store.settings.rippleRight), supportsOpacity: false)
                ColorPicker("Middle click", selection: color($store.settings.rippleMiddle), supportsOpacity: false)
                slider("Size", $store.settings.rippleDiameter, AppSettings.rippleDiameterRange, "%.0f pt")
                slider("Duration", $store.settings.rippleDuration, AppSettings.rippleDurationRange, "%.2f s")
            }
            Section("Laser and ink") {
                ColorPicker("Laser color", selection: color($store.settings.laserColor), supportsOpacity: false)
                slider("Laser trail", $store.settings.laserTrailSeconds, AppSettings.laserTrailRange, "%.2f s")
                ColorPicker("Pen and arrow color", selection: color($store.settings.inkColor), supportsOpacity: false)
                slider("Ink stays for", $store.settings.inkHoldSeconds, AppSettings.inkHoldRange, "%.1f s")
                slider("Ink fades over", $store.settings.inkFadeSeconds, AppSettings.inkFadeRange, "%.1f s")
                Picker("While drawing", selection: $store.settings.inkInput) {
                    Text("Overlay takes the mouse, gives it back after").tag(InkInput.captureWhileDrawing)
                    Text("Clicks always pass through (drags reach the app too)").tag(InkInput.passThrough)
                }
                if store.settings.inkInput == .captureWhileDrawing {
                    slider("Give the mouse back after", $store.settings.inkAutoReleaseSeconds, AppSettings.inkAutoReleaseRange, "%.1f s")
                }
            }
            Section("Keycaps") {
                Picker("Show", selection: $store.settings.keycapMode) {
                    Text("Off").tag(KeycapMode.off)
                    Text("Shortcuts only").tag(KeycapMode.shortcutsOnly)
                    Text("All keys").tag(KeycapMode.allKeys)
                }
                Toggle("Shortcut Subtitles (what the shortcut does in the frontmost app)", isOn: $store.settings.keycapSubtitles)
                Toggle("Count repeats (⌘Z ×3)", isOn: $store.settings.keycapShowRepeatCount)
                Toggle("Hide this app's own shortcuts", isOn: $store.settings.keycapHideActivationKeys)
                slider("Stay on screen", $store.settings.keycapLingerSeconds, AppSettings.keycapLingerRange, "%.1f s")
                slider("Size", $store.settings.keycapScale, AppSettings.keycapScaleRange, "%.0f%%", scale: 100)
                slider("Subtitle size", $store.settings.keycapSubtitleScale, AppSettings.keycapScaleRange, "%.0f%%", scale: 100)
                Picker("Position", selection: placement) {
                    ForEach(KeycapPlacement.allCases, id: \.self) { Text($0.title).tag(KeycapPlacement?.some($0)) }
                    if placement.wrappedValue == nil { Text("Custom (dragged)").tag(KeycapPlacement?.none) }
                }
            }
            Section("Agents") {
                Toggle("Show keys and captions sent by agents (🤖 badge)", isOn: $store.settings.agentAnnouncements)
                Text("Agents can run `keyray show ⌘K --caption \"npm test\" --source claude`, open `keyray://show?keys=cmd+k&caption=…`, or use the `keyray mcp` server. Local to this Mac and user only.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Copy CLI install command") { copy("mkdir -p ~/.local/bin && ln -sf '\(executable)' ~/.local/bin/keyray") }
                    Button("Copy Claude Code MCP command") { copy("claude mcp add keyray -- '\(executable)' mcp") }
                }
            }
            Section("Privacy prompts") {
                Toggle("Hide overlays while System Settings or a security prompt is in front",
                       isOn: $store.settings.hideWhileSystemSettingsFrontmost)
            }
            Section("Shortcuts") {
                ForEach(AppShortcut.allCases, id: \.self) { s in
                    LabeledContent(s.title, value: s.stroke.label)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ format: String, scale: Double = 1) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: format, value.wrappedValue * scale))
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The preset matching the saved position; nil after "Move keycaps" put them elsewhere.
    private var placement: Binding<KeycapPlacement?> {
        Binding(get: { KeycapPlacement(position: store.settings.keycapPosition) },
                set: { if let p = $0 { store.settings.keycapPosition = p.position } })
    }

    private var executable: String { Bundle.main.executablePath ?? "/Applications/Keyray.app/Contents/MacOS/Keyray" }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func color(_ binding: Binding<RGBA>) -> Binding<Color> {
        Binding(get: { Color(nsColor: binding.wrappedValue.nsColor) },
                set: { binding.wrappedValue = RGBA(NSColor($0)) })
    }
}

extension KeycapPlacement {
    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .top: "Top center"
        case .topRight: "Top right"
        case .left: "Middle left"
        case .center: "Center"
        case .right: "Middle right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom center"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Explains why keycaps need Input Monitoring and walks through granting it.
struct OnboardingView: View {
    let status: () -> String
    let request: () -> Void
    let openSettings: () -> Void
    let retry: () -> Void
    @State private var statusText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keycaps show the shortcuts you press, so your audience can follow along.")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("""
            To see key presses, macOS asks you to allow Input Monitoring for this app. The app only \
            listens: it cannot type, click or change anything, keystrokes are never saved or sent \
            anywhere, and macOS hides password fields from it.

            The cursor ring, click ripples, laser and ink need no permission at all.
            """)
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Click “Ask macOS”. The overlays hide while the prompt is up.")
                Text("2. In System Settings › Privacy & Security › Input Monitoring, turn this app on.")
                Text("3. Come back and click “Check again”. If it still says no, quit and reopen the app.")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Text(statusText).font(.callout.bold())
            HStack {
                Button("Ask macOS") { request(); refresh() }.keyboardShortcut(.defaultAction)
                Button("Open System Settings") { openSettings() }
                Spacer()
                Button("Check again") { retry(); refresh() }
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .keycapStatusChanged)) { _ in refresh() }
    }

    private func refresh() { statusText = status() }
}
