import CryptoKit
import Foundation

public enum PetSource: String, Equatable {
  case codexDefault
  case custom
}

public struct PetPackage: Equatable, Identifiable {
  public let id: String
  public let folderName: String
  public let displayName: String
  public let description: String?
  public let spritesheetURL: URL
  public let spritesheetData: Data?
  public let packageDirectory: URL
  public let spriteVersion: PetSpriteVersion
  public let source: PetSource
  public var directionLayout: PetDirectionLayout?

  public func spritesheetHash() -> String? {
    guard let data = spritesheetData ?? (try? Data(contentsOf: spritesheetURL, options: .mappedIfSafe))
    else { return nil }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public init(
    id: String,
    folderName: String,
    displayName: String,
    description: String?,
    spritesheetURL: URL,
    spritesheetData: Data? = nil,
    packageDirectory: URL,
    source: PetSource = .custom,
    spriteVersion: PetSpriteVersion = .v1
  ) {
    self.id = id
    self.folderName = folderName
    self.displayName = displayName
    self.description = description
    self.spritesheetURL = spritesheetURL
    self.spritesheetData = spritesheetData
    self.packageDirectory = packageDirectory
    self.source = source
    self.spriteVersion = spriteVersion
  }
}
