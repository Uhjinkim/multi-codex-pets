import AppKit
import MultiCodexPetsCore
import SwiftUI

struct PetNameLabelSettingsView: View {
  @ObservedObject var app: AppDelegate
  let pet: PetPackage
  @Environment(\.dismiss) private var dismiss

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
    .onDisappear { NSColorPanel.shared.close() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
      if let panel = notification.object as? NSColorPanel, panel.isVisible { panel.close() }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(localizedFormat("Name Label for %@", app.displayName(for: pet)))
        .font(.system(size: 19 * scale, weight: .semibold)).lineLimit(2)
      VStack(spacing: 3) {
        if style.position == .above { nameLabel }
        if let image = app.previewImage(for: pet) {
          Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            .frame(width: 80 * app.settings.scale, height: 87 * app.settings.scale)
            .accessibilityHidden(true)
        }
        if style.position == .below { nameLabel }
      }
      .frame(maxWidth: .infinity)
      .frame(height: max(120, 87 * app.settings.scale + style.resolvedFontSize + 24))
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
