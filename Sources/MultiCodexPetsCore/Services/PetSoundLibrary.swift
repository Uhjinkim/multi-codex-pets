import Foundation

public enum PetSoundRole: String, CaseIterable { case click, notification }

public struct PetSoundLibrary {
  private struct Roles: Codable {
    var excludedFromClick: [String] = []
    var notifications: [String] = []
    var notificationsByActivity: [String: [String]] = [:]
    enum CodingKeys: String, CodingKey {
      case excludedFromClick, notifications, notificationsByActivity
    }
    init() {}
    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      excludedFromClick =
        try values.decodeIfPresent([String].self, forKey: .excludedFromClick) ?? []
      notifications = try values.decodeIfPresent([String].self, forKey: .notifications) ?? []
      notificationsByActivity =
        try values.decodeIfPresent([String: [String]].self, forKey: .notificationsByActivity) ?? [:]
    }
  }

  public let directory: URL
  public static let supportedExtensions: Set<String> = ["wav", "mp3", "m4a", "aif", "aiff", "caf"]

  public init(codexHome: URL = PetPackageLoader.defaultCodexHome()) {
    directory = codexHome.appendingPathComponent("pet-sounds", isDirectory: true)
  }

  public func directory(forPetID id: String) -> URL? {
    guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\0") else {
      return nil
    }
    return directory.appendingPathComponent(id, isDirectory: true)
  }

  public func soundURLs(
    forPetID id: String, role: PetSoundRole? = nil, activity: AgentActivity? = nil, notificationKey: String? = nil
  ) -> [URL] {
    guard let folder = directory(forPetID: id),
      let files = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    else { return [] }

    var sounds = files.filter {
      Self.supportedExtensions.contains($0.pathExtension.lowercased())
        && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    if let selected = try? String(
      contentsOf: folder.appendingPathComponent(".selected-sound"), encoding: .utf8),
      let index = sounds.firstIndex(where: { $0.lastPathComponent == selected })
    {
      sounds.insert(sounds.remove(at: index), at: 0)
    }
    guard let role else { return sounds }
    let roles = (try? loadRoles(folder)) ?? Roles()
    return sounds.filter {
      switch role {
      case .click: return !roles.excludedFromClick.contains($0.lastPathComponent)
      case .notification:
        let names =
          (notificationKey ?? activity?.rawValue).flatMap { roles.notificationsByActivity[$0] } ?? roles.notifications
        return names.contains($0.lastPathComponent)
      }
    }
  }

  public func setUsage(
    _ enabled: Bool, filename: String, forPetID id: String, role: PetSoundRole,
    activity: AgentActivity? = nil, notificationKey: String? = nil
  )
    throws
  {
    guard let folder = directory(forPetID: id),
      soundURLs(forPetID: id).contains(where: { $0.lastPathComponent == filename })
    else { throw CocoaError(.fileReadNoSuchFile) }
    var roles = try loadRoles(folder)
    switch role {
    case .click:
      roles.excludedFromClick.removeAll { $0 == filename }
      if !enabled { roles.excludedFromClick.append(filename) }
    case .notification:
      if let key = notificationKey ?? activity?.rawValue {
        var names = roles.notificationsByActivity[key] ?? roles.notifications
        names.removeAll { $0 == filename }
        if enabled { names.append(filename) }
        roles.notificationsByActivity[key] = names
      } else {
        roles.notifications.removeAll { $0 == filename }
        if enabled { roles.notifications.append(filename) }
      }
    }
    try saveRoles(roles, folder: folder)
  }

  public func useDefaultNotificationPool(forPetID id: String, activity: AgentActivity? = nil,
    notificationKey: String? = nil) throws {
    guard let folder = directory(forPetID: id) else { throw CocoaError(.fileWriteInvalidFileName) }
    var roles = try loadRoles(folder)
    guard let key = notificationKey ?? activity?.rawValue else { return }
    roles.notificationsByActivity.removeValue(forKey: key)
    try saveRoles(roles, folder: folder)
  }

  private func loadRoles(_ folder: URL) throws -> Roles {
    let url = folder.appendingPathComponent(".sound-roles.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return Roles() }
    return try JSONDecoder().decode(Roles.self, from: Data(contentsOf: url))
  }

  private func saveRoles(_ roles: Roles, folder: URL) throws {
    try JSONEncoder().encode(roles).write(
      to: folder.appendingPathComponent(".sound-roles.json"), options: .atomic)
  }

  @discardableResult
  public func importSound(
    from source: URL, forPetID id: String, role: PetSoundRole = .click,
    activity: AgentActivity? = nil, notificationKey: String? = nil
  ) throws
    -> URL
  {
    guard let folder = directory(forPetID: id) else { throw CocoaError(.fileWriteInvalidFileName) }
    guard Self.supportedExtensions.contains(source.pathExtension.lowercased()),
      (try source.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true
    else { throw CocoaError(.fileReadCorruptFile) }
    let manager = FileManager.default
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let alreadyInFolder =
      !source.lastPathComponent.hasPrefix(".")
      && source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        == folder.resolvingSymlinksInPath().standardizedFileURL
    let filename =
      source.lastPathComponent.hasPrefix(".")
      ? "sound-\(source.lastPathComponent.dropFirst())" : source.lastPathComponent
    var destination = folder.appendingPathComponent(filename)
    if !alreadyInFolder {
      while manager.fileExists(atPath: destination.path) {
        destination = folder.appendingPathComponent(
          "\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(8)).\(source.pathExtension)"
        )
      }
      try manager.copyItem(at: source.resolvingSymlinksInPath(), to: destination)
    }
    do {
      var roles = try loadRoles(folder)
      let name = destination.lastPathComponent
      roles.excludedFromClick.removeAll { $0 == name }
      if role == .notification {
        roles.excludedFromClick.append(name)
        if let key = notificationKey ?? activity?.rawValue {
          var names = roles.notificationsByActivity[key] ?? roles.notifications
          names.removeAll { $0 == name }
          names.append(name)
          roles.notificationsByActivity[key] = names
        } else {
          roles.notifications.removeAll { $0 == name }
          roles.notifications.append(name)
        }
      }
      try saveRoles(roles, folder: folder)
      try destination.lastPathComponent.write(
        to: folder.appendingPathComponent(".selected-sound"),
        atomically: true, encoding: .utf8)
    } catch {
      if !alreadyInFolder { try? manager.removeItem(at: destination) }
      throw error
    }
    return destination
  }
}
