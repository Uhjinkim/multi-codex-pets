import MultiCodexPetsCore
import SwiftUI

struct GlobalSoundVolumeSettings: View {
  @ObservedObject var app: AppDelegate

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(localized("Mute All Pets"), isOn: Binding(
        get: { app.settings.soundsMuted }, set: app.setSoundsMuted))
      Group {
        volumeSlider(.click, title: "Click Volume")
        volumeSlider(.notification, title: "Alert Volume")
      }
      .disabled(app.settings.soundsMuted)
    }
  }

  private func volumeSlider(_ role: PetSoundRole, title: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label(localized(title), systemImage: role == .click ? "speaker.wave.2" : "bell")
        Spacer()
        Text(
          Double(role == .click ? app.settings.clickVolume : app.settings.alertVolume)
            .formatted(.percent.precision(.fractionLength(0)))
        )
        .monospacedDigit().foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(
          get: { Double(role == .click ? app.settings.clickVolume : app.settings.alertVolume) },
          set: { app.setVolume(Float($0), role: role) }), in: 0...1
      )
      .labelsHidden().accessibilityLabel(localized(title))
    }
  }

}
