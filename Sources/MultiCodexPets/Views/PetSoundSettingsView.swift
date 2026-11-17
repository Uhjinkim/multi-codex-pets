import AppKit
import MultiCodexPetsCore
import SwiftUI

struct PetSoundSettingsView: View {
  @ObservedObject var app: AppDelegate
  let pet: PetPackage
  @Environment(\.dismiss) private var dismiss
  @State private var alertActivityKey = ""
  @State private var previewRole = PetSoundRole.click
  private var alertActivity: AgentActivity? { AgentActivity(rawValue: alertActivityKey) }

  private var scale: CGFloat { app.settingsLayout.scale }
  private var detailFont: Font { .system(size: 13 * scale) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ViewThatFits(in: .vertical) {
        contents
        ScrollView { contents.fixedSize(horizontal: false, vertical: true) }
      }
      Divider()
      HStack(spacing: 12) {
        Group {
          if let playing = app.previewingSound {
            Label(playing.lastPathComponent, systemImage: "waveform")
          } else {
            Text(localized("Use the play button to preview a file."))
          }
        }
        .font(detailFont).foregroundStyle(.secondary).lineLimit(1)
        Spacer(minLength: 8)
        Button(localized("Open Sound Folder…")) { app.openSoundFolder(pet.id) }
        Button(localized("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 20).padding(.vertical, 14)
    }
    .font(.system(size: 15 * scale)).controlSize(.large)
    .frame(
      width: min(860, app.settingsLayout.contentSize.width - 60),
      height: min(680, app.settingsLayout.contentSize.height - 60)
    )
    .onChange(of: previewRole) { _ in app.stopSoundPreview() }
    .onDisappear { app.stopSoundPreview() }
  }

  private var contents: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 14) {
        if let image = app.previewImage(for: pet) {
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .frame(width: 38, height: 42).accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 5) {
          Text(localizedFormat("Sounds for %@", app.displayName(for: pet)))
            .font(.system(size: 19 * scale, weight: .semibold))
          Text(localized("Choose multiple sounds for random playback."))
            .font(detailFont).foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(20)
      Divider()
      HStack(spacing: 24) {
        volumeSlider(.click, title: "Click Volume")
        volumeSlider(.notification, title: "Alert Volume")
      }
      .padding(.horizontal, 20).padding(.vertical, 14)
      Divider()
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(localizedFormat("Audio Files (%d)", app.sounds(for: pet.id).count))
            .font(.system(size: 16 * scale, weight: .semibold))
          Spacer()
          Button {
            app.chooseSoundFile(for: pet.id, role: .click)
          } label: {
            Label(localized("Add Click Sounds…"), systemImage: "plus")
          }
          Button {
            app.chooseSoundFile(for: pet.id, role: .notification, activity: alertActivity)
          } label: {
            Label(localized("Add Notification Sounds…"), systemImage: "bell.badge")
          }
        }
        .font(detailFont)
        .controlSize(.regular)
        ViewThatFits(in: .horizontal) {
          HStack {
            poolControls
            Spacer(minLength: 12)
            previewControls
          }
          VStack(alignment: .leading, spacing: 10) {
            poolControls
            previewControls
          }
        }
        Text(
          alertActivity.map {
            localizedFormat("Editing alert sounds for %@.", localized($0.rawValue))
          }
            ?? localized("The default alert pool is used unless a state has its own sounds.")
        )
        .font(detailFont).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        VStack(spacing: 0) {
          HStack(spacing: 10) {
            Color.clear.frame(width: 32, height: 1).accessibilityHidden(true)
            Text(localized("Audio File")).frame(maxWidth: .infinity, alignment: .leading)
            Text(localized("Click")).frame(width: 72)
            Text(localized("Alert")).frame(width: 72)
          }
          .font(detailFont.weight(.medium)).foregroundStyle(.secondary)
          .padding(.horizontal, 12).frame(height: 38 * scale)
          Divider()
          fileList.frame(minHeight: 160)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
      }
      .padding(20)
    }
  }

  private var poolControls: some View {
    HStack(spacing: 8) {
      Menu {
        Button(localized("Default alerts")) { alertActivityKey = "" }
        ForEach(AgentActivity.allCases.filter { $0 != .unknown }, id: \.self) { activity in
          Button(localized(activity.rawValue)) { alertActivityKey = activity.rawValue }
        }
      } label: {
        Label(localized(alertActivity?.rawValue ?? "Default alerts"), systemImage: "bell")
          .font(detailFont).lineLimit(1)
      }
      .fixedSize(horizontal: true, vertical: false)
      .controlSize(.regular)
      .help(localized("Alert pool"))
      if let alertActivity {
        Button {
          app.useDefaultAlertPool(petID: pet.id, activity: alertActivity)
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
        .help(localized("Use default pool")).accessibilityLabel(localized("Use default pool"))
      }
    }
  }

  private var previewControls: some View {
    HStack(spacing: 8) {
      Text(localized("Preview volume")).font(detailFont).foregroundStyle(.secondary)
      previewChooser
    }
  }

  private var previewChooser: some View {
    Picker(localized("Preview volume"), selection: $previewRole) {
      Text(localized("Click Volume")).tag(PetSoundRole.click)
      Text(localized("Alert Volume")).tag(PetSoundRole.notification)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .font(detailFont)
    .frame(width: 180 * scale)
    .controlSize(.regular)
    .accessibilityLabel(localized("Preview volume"))
    .help(localized("Preview volume"))
  }

  private var fileList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        if app.sounds(for: pet.id).isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 28))
            Text(localized("Add audio files to enable sounds for this pet."))
          }
          .foregroundStyle(.secondary).multilineTextAlignment(.center)
          .frame(maxWidth: .infinity).padding(.vertical, 36)
        }
        ForEach(app.sounds(for: pet.id), id: \.lastPathComponent) { url in
          HStack(spacing: 10) {
            Button {
              app.previewSound(url, role: previewRole)
            } label: {
              Image(systemName: app.previewingSound == url ? "stop.fill" : "play.fill")
                .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
              localized(app.previewingSound == url ? "Stop preview" : "Play preview"))
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
              .help(url.lastPathComponent).frame(maxWidth: .infinity, alignment: .leading)
            roleToggle(url, role: .click).frame(width: 72)
            roleToggle(url, role: .notification).frame(width: 72)
          }
          .padding(.horizontal, 12).frame(minHeight: 48 * scale)
          .background(app.previewingSound == url ? Color.accentColor.opacity(0.06) : .clear)
          .overlay(alignment: .bottom) { Divider().padding(.leading, 54) }
        }
      }
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

  private func roleToggle(_ url: URL, role: PetSoundRole) -> some View {
    Toggle(
      isOn: Binding(
        get: {
          app.sounds(for: pet.id, role: role, activity: role == .notification ? alertActivity : nil)
            .contains {
              $0.lastPathComponent == url.lastPathComponent
            }
        },
        set: {
          app.setSoundUsage(
            $0, filename: url.lastPathComponent, petID: pet.id, role: role,
            activity: role == .notification ? alertActivity : nil)
        })
    ) {
      Text(localized(role == .click ? "Click" : "Alert"))
    }
    .labelsHidden().toggleStyle(.checkbox)
    .accessibilityLabel(
      localizedFormat(role == .click ? "Click sound: %@" : "Alert sound: %@", url.lastPathComponent)
    )
  }
}
