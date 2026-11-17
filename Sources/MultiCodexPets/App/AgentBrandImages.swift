import AppKit
import MultiCodexPetsCore

/// Share the official service marks across SwiftUI and native menus.
enum AgentBrandImages {
  static let images: [AgentSession: NSImage] = {
    var images: [AgentSession: NSImage] = [:]
    for kind in AgentSession.allCases {
      if let url = Bundle.module.url(forResource: kind.rawValue.lowercased(), withExtension: "png"),
        let image = NSImage(contentsOf: url)
      {
        image.isTemplate = kind == .codex || kind == .orca
        images[kind] = image
      }
    }
    return images
  }()
}
