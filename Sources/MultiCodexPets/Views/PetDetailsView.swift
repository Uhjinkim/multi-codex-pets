import AppKit
import MultiCodexPetsCore
import SwiftUI

struct PetDetailsView: View {
  @ObservedObject var app: AppDelegate
  let pet: PetPackage
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  private var preference: PetPreferences { app.settings.petPreferences[pet.id] ?? PetPreferences() }
  private var style: PetNameLabel { app.settings.petPreferences[pet.id]?.nameLabel ?? PetNameLabel() }
  private var scale: CGFloat { app.settingsLayout.scale }

  var body: some View {
    VStack(spacing: 0) {
      ViewThatFits(in: .vertical) {
        controls
        ScrollView { controls.fixedSize(horizontal: false, vertical: true) }
      }
      Divider()
      HStack {
        Text(localized("Changes apply immediately."))
          .font(.system(size: 13 * scale)).foregroundStyle(.secondary)
        Spacer()
        Button(localized("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
      }
      .padding(20 * scale)
    }
    .font(.system(size: 14 * scale)).controlSize(.large)
    .frame(width: min(520, app.settingsLayout.contentSize.width - 60),
      height: min(660, app.settingsLayout.contentSize.height - 60))
    .onAppear { name = app.displayName(for: pet) }
    .onDisappear { NSColorPanel.shared.close() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
      if let panel = notification.object as? NSColorPanel, panel.isVisible { panel.close() }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(localizedFormat("Settings for %@", app.displayName(for: pet)))
        .font(.system(size: 19 * scale, weight: .semibold)).lineLimit(2)
      HStack {
        TextField(localized("Pet Name"), text: $name)
          .onSubmit(saveName)
        Button(localized("Save"), action: saveName)
          .disabled(name.trimmedNonEmpty == nil || name == app.displayName(for: pet))
        if preference.customName != nil {
          Button(localized("Use Original Name")) {
            app.renamePet(pet.id, to: "")
            name = app.displayName(for: pet)
          }
        }
      }
      Picker(localized("Pet Size"), selection: Binding(
        get: { preference.scale }, set: { app.setPetScale(pet.id, to: $0) }
      )) {
        Text(localized("Use Shared Size")).tag(nil as Double?)
        ForEach(AppDelegate.petSizePercents, id: \.self) { percent in
          Text("\(percent)%").tag(Optional(Double(percent) / 100))
        }
      }
      if pet.spriteVersion == .v2 {
        Picker(localized("Cursor Tracking"), selection: Binding(
          get: { app.cursorTrackingMode(for: pet.id) },
          set: { app.setPetPreference(pet.id, cursorTrackingMode: $0) }
        )) {
          ForEach(PetCursorTrackingMode.allCases, id: \.self) { mode in
            Text(localized(mode.rawValue)).tag(mode)
          }
        }
      }
      Toggle(localized("Lock Position"), isOn: Binding(
        get: { preference.positionLocked }, set: { app.setPetPreference(pet.id, locked: $0) }))
      Toggle(localized("Mute This Pet"), isOn: Binding(
        get: { preference.muted }, set: { app.setPetPreference(pet.id, muted: $0) }))
      if app.availableScreens.count > 1 {
        Menu(localized("Move to Display")) {
          ForEach(app.availableScreens, id: \.id) { screen in
            Button(screen.name) { app.movePet(pet.id, to: screen.id) }
          }
        }
        .disabled(!app.selectedPetIDs.contains(pet.id))
      }
      HStack {
        Button(localized("Change Session…")) {
          dismiss()
          app.requestSessionChange(pet.id)
        }
        .disabled(!app.selectedPetIDs.contains(pet.id))
        if app.assignedSession(for: pet.id) != nil {
          Button(localized("Open Agent App")) { app.openAgentApp(for: pet.id) }
        }
      }
      Divider()
      Text(localized("Name Label")).font(.headline)
      VStack(spacing: 3) {
        if style.position == .above { nameLabel }
        if let image = app.previewImage(for: pet) {
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .frame(width: 80 * petScale, height: 87 * petScale)
            .accessibilityHidden(true)
        }
        if style.position == .below { nameLabel }
      }
      .frame(maxWidth: .infinity)
      .frame(height: max(120, 87 * petScale + style.resolvedFontSize + 24))
      Picker(localized("Label Position"), selection: Binding(
        get: { style.position },
        set: { var value = style; value.position = $0; app.setPetNameLabel(pet.id, style: value) }
      )) {
        ForEach(PetNameLabelPosition.allCases, id: \.self) { position in
          Text(localized(position.rawValue)).tag(position)
        }
      }
      .pickerStyle(.segmented)
      HStack {
        Text(localized("Font Size"))
        Slider(value: Binding(
          get: { style.resolvedFontSize },
          set: { var value = style; value.fontSize = $0; app.setPetNameLabel(pet.id, style: value) }
        ), in: 9...28, step: 1)
          .labelsHidden().accessibilityLabel(localized("Font Size"))
        Text(localizedFormat("%d pt", Int(style.resolvedFontSize)))
          .monospacedDigit().frame(width: 56, alignment: .trailing)
      }
      ColorPicker(localized("Text Color"), selection: Binding(
        get: { Color(nsColor: style.color) }, set: { setColor($0, background: false) }
      ), supportsOpacity: false)
      ColorPicker(localized("Background Color"), selection: Binding(
        get: { Color(nsColor: style.backgroundColor.withAlphaComponent(1)) },
        set: { setColor($0, background: true) }
      ), supportsOpacity: false)
      HStack {
        Text(localized("Background Transparency"))
        Slider(value: Binding(
          get: { 1 - style.resolvedBackgroundOpacity },
          set: { var value = style; value.backgroundOpacity = 1 - $0; app.setPetNameLabel(pet.id, style: value) }
        ), in: 0...1, step: 0.01)
          .labelsHidden().accessibilityLabel(localized("Background Transparency"))
        Text((1 - style.resolvedBackgroundOpacity).formatted(.percent.precision(.fractionLength(0))))
          .monospacedDigit().frame(width: 56, alignment: .trailing)
      }
      Text(localized("0% is opaque; 100% is fully transparent."))
        .font(.system(size: 13 * scale)).foregroundStyle(.secondary)
    }
    .padding(20 * scale)
  }

  private var petScale: Double { preference.resolvedScale(default: app.settings.scale) }

  private func saveName() {
    guard name.trimmedNonEmpty != nil else { return }
    app.renamePet(pet.id, to: name)
    name = app.displayName(for: pet)
  }

  private func setColor(_ color: Color, background: Bool) {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
    let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
      .map { Int((min(max($0, 0), 1) * 255).rounded()) }
    let hex = String(format: "%02X%02X%02X", components[0], components[1], components[2])
    var value = style
    if background { value.backgroundColorHex = hex } else { value.colorHex = hex }
    app.setPetNameLabel(pet.id, style: value)
  }

  private var nameLabel: some View {
    Text(app.displayName(for: pet))
      .font(.system(size: style.resolvedFontSize, weight: .medium))
      .foregroundStyle(Color(nsColor: style.color))
      .lineLimit(1).truncationMode(.tail)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(Color(nsColor: style.backgroundColor), in: RoundedRectangle(cornerRadius: 6))
      .frame(maxWidth: 280)
  }
}
