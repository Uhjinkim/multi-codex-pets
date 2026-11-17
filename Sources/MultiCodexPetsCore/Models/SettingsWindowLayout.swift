import Foundation

public struct SettingsWindowLayout {
  public let contentSize: CGSize
  public let minimumContentSize: CGSize
  public let scale: CGFloat

  public init(visibleSize: CGSize) {
    // Screen dimensions are logical points; macOS already accounts for Retina scaling.
    let availableWidth = max(320, visibleSize.width - 48)
    let availableHeight = max(240, visibleSize.height - 80)
    contentSize = CGSize(
      width: min(availableWidth, min(max(visibleSize.width * 0.48, 720), 820)),
      height: min(availableHeight, min(max(visibleSize.height * 0.78, 600), 920)))
    minimumContentSize = CGSize(
      width: min(680, contentSize.width), height: min(560, contentSize.height))
    scale = min(max(visibleSize.height / 900, 1), 1.15)
  }
}
