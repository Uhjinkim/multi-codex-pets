import AppKit
import SwiftUI

struct ReduceMotionSettingsLink: View {
  @State private var enabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(localized(enabled ? "Reduce Motion is on" : "Reduce Motion is off"))
        .foregroundStyle(.secondary)
      Button(localized("Open Motion Accessibility Settings…")) {
        let address: String
        if #available(macOS 26, *) {
          address = "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Motion"
        } else {
          address = "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display"
        }
        if let url = URL(string: address), !NSWorkspace.shared.open(url) { NSSound.beep() }
      }
      .buttonStyle(.link)
      .help(localized("Opens macOS accessibility settings. Reduce Motion affects all apps."))
    }
    .font(.callout)
    .onReceive(NSWorkspace.shared.notificationCenter.publisher(
      for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
    ) { _ in enabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  }
}
