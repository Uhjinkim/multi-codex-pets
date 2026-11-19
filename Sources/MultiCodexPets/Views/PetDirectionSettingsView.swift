import AppKit
import MultiCodexPetsCore
import SwiftUI

struct PetDirectionSettingsView: View {
  @ObservedObject var app: AppDelegate
  let pet: PetPackage
  @Environment(\.dismiss) private var dismiss
  @State private var draft: PetDirectionLayout
  @State private var selected: Int?
  @State private var thumbnails: [NSImage] = []
  @State private var hash: String?
  @State private var originalLayout = PetDirectionLayout()
  @State private var error: String?

  init(app: AppDelegate, pet: PetPackage) {
    self.app = app
    self.pet = pet
    _draft = State(initialValue: pet.directionLayout ?? PetDirectionLayout())
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(localizedFormat("Arrange frames for %@", app.displayName(for: pet))).font(.title2.bold())
          Text(localized("Select two frames to swap them. Select a frame to flip it horizontally."))
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          if thumbnails.isEmpty {
            Text(localized("Could not read the sprite frames. Refresh pets and try again."))
              .foregroundStyle(.secondary)
          } else {
            HStack {
              Button(localized("Swap Running Rows")) {
                draft.swapRunningRows()
                selected = nil
              }
              Button(localized("Flip Selected Frame")) {
                if let selected { draft.mirror(selected) }
              }
              .disabled(selected == nil)
            }
            row("Run Right", start: 0)
            row("Run Left", start: 8)
            if pet.spriteVersion == .v2 {
              Divider().padding(.vertical, 4)
              Text(localized("Cursor Tracking")).font(.headline)
              row("Up to Lower Right", start: 16)
              row("Down to Upper Left", start: 24)
            }
          }
        }
        .padding(20)
      }
      Divider()
      HStack {
        Button(localized("Restore Original Layout")) {
          draft = PetDirectionLayout()
          selected = nil
        }
        .disabled(draft == PetDirectionLayout() || hash == nil)
        Spacer()
        Button(localized("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button(localized("Apply")) { apply() }
          .keyboardShortcut(.defaultAction)
          .disabled(hash == nil || draft == originalLayout)
      }
      .padding(20)
    }
    .frame(width: min(660, app.settingsLayout.contentSize.width - 36),
      height: min(pet.spriteVersion == .v2 ? 700 : 466, app.settingsLayout.contentSize.height - 36))
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear(perform: loadFrames)
    .alert(localized("Could not apply frame layout"), isPresented: Binding(
      get: { error != nil }, set: { if !$0 { error = nil } }
    )) {
      Button(localized("OK"), role: .cancel) {}
    } message: {
      Text(error ?? "")
    }
  }

  private func row(_ title: String, start: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(localized(title)).font(.subheadline.weight(.semibold))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 8), spacing: 5) {
        ForEach(start..<(start + 8), id: \.self) { index in
          let cell = draft.cells[index]
          let isSelected = selected == index
          let position = index < 16 ? "\(index % 8 + 1)" : String(format: "%g°", Double(index - 16) * 22.5)
          Button {
            select(index)
          } label: {
            VStack(spacing: 3) {
              Image(nsImage: thumbnails[cell.source])
                .resizable().interpolation(.high).scaledToFit()
                .scaleEffect(x: cell.mirrored ? -1 : 1, y: 1)
                .frame(height: 52)
                .accessibilityHidden(true)
              Text(position).font(.caption.monospacedDigit()).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
              .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(localized(title)), \(position)")
          .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
      }
    }
  }

  private func select(_ index: Int) {
    if let selected, selected != index, (selected < 16) == (index < 16) {
      draft.swap(selected, index)
      self.selected = nil
    } else {
      selected = selected == index ? nil : index
    }
  }

  private func loadFrames() {
    guard thumbnails.isEmpty, let hash = pet.spritesheetHash(),
      let sheet = PetImageDecoder.image(for: pet) else { return }
    let count = pet.spriteVersion == .v2 ? 32 : 16
    let images = (0..<count).compactMap { index -> NSImage? in
      guard let image = PetImageDecoder.cell(in: sheet, frame: PetDirectionLayout.frame(at: index))
      else { return nil }
      return NSImage(cgImage: image, size: .zero)
    }
    guard images.count == count, hash == pet.spritesheetHash() else { return }
    if let saved = app.settings.petPreferences[pet.id]?.directionLayout, saved.spritesheetHash == hash {
      originalLayout = saved.layout
    }
    draft = originalLayout
    thumbnails = images
    self.hash = hash
  }

  private func apply() {
    guard let hash, app.saveDirectionLayout(draft, for: pet, hash: hash) else {
      error = localized("The sprite file changed. Close this window, refresh pets, and try again.")
      return
    }
    dismiss()
  }
}
