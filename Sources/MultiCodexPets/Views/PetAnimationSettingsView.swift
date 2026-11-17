import AppKit
import MultiCodexPetsCore
import SwiftUI

struct PetAnimationSettingsView: View {
  @ObservedObject var app: AppDelegate
  let pet: PetPackage
  @Environment(\.dismiss) private var dismiss
  @State private var animation = MultiCodexPetsCore.AnimationState.idle
  @State private var previewsGaze = false

  private var scale: CGFloat { app.settingsLayout.scale }

  var body: some View {
    VStack(alignment: .leading, spacing: 16 * scale) {
      HStack {
        Text(localizedFormat("Animations for %@", app.displayName(for: pet)))
          .font(.system(size: 19 * scale, weight: .semibold))
        Spacer()
        if pet.spriteVersion == .v2 { Text("V2").foregroundStyle(.secondary) }
      }
      Text(localized("Select an animation to preview. Your desktop pet stays unchanged."))
        .font(.system(size: 13 * scale)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if pet.spriteVersion == .v2 {
        Toggle(localized("Preview Cursor Tracking"), isOn: $previewsGaze)
          .toggleStyle(.switch)
          .font(.system(size: 14 * scale))
      }
      PetAnimationPreview(
        pet: pet, animation: previewsGaze ? .idle : animation, followsCursor: previewsGaze
      )
        .frame(width: 144 * scale, height: 156 * scale)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(localized(previewsGaze ? "Preview Cursor Tracking" : animation.displayName))
      if previewsGaze {
        Text(localized("Move the cursor around the preview to see all 16 look directions. Reduce Motion takes priority."))
          .font(.system(size: 13 * scale)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8 * scale) {
        ForEach(MultiCodexPetsCore.AnimationState.allCases) { state in
          Button {
            previewsGaze = false
            animation = state
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "checkmark")
                .opacity(!previewsGaze && animation == state ? 1 : 0).accessibilityHidden(true)
              Text(localized(state.displayName))
            }
            .frame(maxWidth: .infinity, minHeight: 32 * scale)
            .contentShape(Rectangle())
          }
          .buttonStyle(.bordered)
          .tint(!previewsGaze && animation == state ? .accentColor : nil)
          .accessibilityAddTraits(!previewsGaze && animation == state ? .isSelected : [])
        }
      }
      Divider()
      HStack {
        Text(localized("Set session animations in Behavior."))
          .font(.system(size: 13 * scale)).foregroundStyle(.secondary)
        Spacer()
        Button(localized("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(20 * scale)
    .font(.system(size: 14 * scale))
    .controlSize(.large)
    .frame(width: min(600, app.settingsLayout.contentSize.width - 60))
  }
}

private struct PetAnimationPreview: NSViewRepresentable {
  let pet: PetPackage
  let animation: MultiCodexPetsCore.AnimationState
  let followsCursor: Bool

  func makeNSView(context: Context) -> PetSpriteView {
    let view = PetSpriteView(pet: pet, animationState: animation)
    view.isInteractive = false
    view.followsCursor = followsCursor
    view.isMuted = true
    return view
  }

  func updateNSView(_ view: PetSpriteView, context: Context) {
    view.followsCursor = followsCursor
    view.setAnimationState(animation)
  }
}
