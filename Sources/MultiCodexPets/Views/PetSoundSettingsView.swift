import AppKit
import MultiCodexPetsCore
import SwiftUI

struct PetSoundSettingsView: View {
  @ObservedObject var app: AppDelegate
  let pet: PetPackage
  @Environment(\.dismiss) private var dismiss
  @State private var alertPoolKey = ""
  @State private var previewRole = PetSoundRole.click
  @State private var showsGlobalVolume = false
  @State private var soundSearch = ""
  private var notificationKey: String? { alertPoolKey.isEmpty ? nil : alertPoolKey }
  private var alertPoolTitle: String {
    alertPoolKey == OrcaMessageEvent.soundKey ? "Orca message sent" : (notificationKey ?? "Default alerts")
  }

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
    .onAppear { soundSearch = pet.displayName }
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
      VStack(alignment: .leading, spacing: 12) {
        Toggle(localized("Mute This Pet"), isOn: Binding(
          get: { app.settings.petPreferences[pet.id]?.muted ?? false },
          set: { app.setPetPreference(pet.id, muted: $0) }))
        HStack {
          Text(localized("Pet Volume"))
          Slider(value: Binding(
            get: { Double(app.settings.petPreferences[pet.id]?.resolvedSoundVolume ?? 1) },
            set: { app.setPetPreference(pet.id, soundVolume: Float($0)) }), in: 0...1)
            .labelsHidden().accessibilityLabel(localized("Pet Volume"))
          Text(Double(app.settings.petPreferences[pet.id]?.resolvedSoundVolume ?? 1)
            .formatted(.percent.precision(.fractionLength(0))))
            .monospacedDigit().frame(width: 54, alignment: .trailing)
        }
        .disabled(app.settings.petPreferences[pet.id]?.muted == true)
        DisclosureGroup(localized("Global Volume — All Pets"), isExpanded: $showsGlobalVolume) {
          GlobalSoundVolumeSettings(app: app).padding(.top, 10)
        }
        .font(detailFont)
        if app.settings.soundsMuted {
          Text(localized("All pet sounds are muted. Unmute in Global Volume to hear this pet."))
            .font(detailFont).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 20).padding(.vertical, 14)
      Divider()
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          TextField(localized("Character name or alias"), text: $soundSearch)
            .textFieldStyle(.roundedBorder)
            .onSubmit { openSoundSearch() }
          Button(localized("Find on Myinstants…")) { openSoundSearch() }
        }
        Text(localized("Preview and download in your browser, then add the file as a click or alert sound below."))
          .font(detailFont).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
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
            app.chooseSoundFile(for: pet.id, role: .notification, notificationKey: notificationKey)
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
          notificationKey.map { _ in
            localizedFormat("Editing alert sounds for %@.", localized(alertPoolTitle))
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
        Button(localized("Default alerts")) { alertPoolKey = "" }
        ForEach(AgentActivity.allCases.filter { $0 != .unknown }, id: \.self) { activity in
          Button(localized(activity.rawValue)) { alertPoolKey = activity.rawValue }
        }
        Divider()
        Button(localized("Orca message sent")) { alertPoolKey = OrcaMessageEvent.soundKey }
      } label: {
        Label(localized(alertPoolTitle), systemImage: "bell")
          .font(detailFont).lineLimit(1)
      }
      .fixedSize(horizontal: true, vertical: false)
      .controlSize(.regular)
      .help(localized("Alert pool"))
      if notificationKey != nil {
        Button {
          app.useDefaultAlertPool(petID: pet.id, notificationKey: notificationKey)
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
        .help(localized("Use default pool")).accessibilityLabel(localized("Use default pool"))
      }
    }
  }

  private func openSoundSearch() {
    app.stopSoundPreview()
    if !NSWorkspace.shared.open(CatalogSearch.soundURL(query: soundSearch)) { NSSound.beep() }
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
    let files = app.sounds(for: pet.id)
    let clickSounds = Set(app.sounds(for: pet.id, role: .click).map(\.lastPathComponent))
    let alertSounds = Set(app.sounds(for: pet.id, role: .notification, notificationKey: notificationKey).map(\.lastPathComponent))
    return ScrollView {
      LazyVStack(spacing: 0) {
        if files.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 28))
            Text(localized("Add audio files to enable sounds for this pet."))
          }
          .foregroundStyle(.secondary).multilineTextAlignment(.center)
          .frame(maxWidth: .infinity).padding(.vertical, 36)
        }
        ForEach(files, id: \.lastPathComponent) { url in
          HStack(spacing: 10) {
            Button {
              app.previewSound(url, role: previewRole, petID: pet.id)
            } label: {
              Image(systemName: app.previewingSound == url ? "stop.fill" : "play.fill")
                .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(app.settings.soundsMuted || app.settings.petPreferences[pet.id]?.muted == true)
            .accessibilityLabel(
              localized(app.previewingSound == url ? "Stop preview" : "Play preview"))
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
              .help(url.lastPathComponent).frame(maxWidth: .infinity, alignment: .leading)
            roleToggle(url, role: .click, enabled: clickSounds.contains(url.lastPathComponent)).frame(width: 72)
            roleToggle(url, role: .notification, enabled: alertSounds.contains(url.lastPathComponent)).frame(width: 72)
          }
          .padding(.horizontal, 12).frame(minHeight: 48 * scale)
          .background(app.previewingSound == url ? Color.accentColor.opacity(0.06) : .clear)
          .overlay(alignment: .bottom) { Divider().padding(.leading, 54) }
        }
      }
    }
  }

  private func roleToggle(_ url: URL, role: PetSoundRole, enabled: Bool) -> some View {
    Toggle(
      isOn: Binding(
        get: { enabled },
        set: {
          app.setSoundUsage(
            $0, filename: url.lastPathComponent, petID: pet.id, role: role,
            notificationKey: role == .notification ? notificationKey : nil)
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
