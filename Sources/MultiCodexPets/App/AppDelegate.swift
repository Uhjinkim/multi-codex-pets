import AVFoundation
import AppKit
import MultiCodexPetsCore
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, AVAudioPlayerDelegate,
  ObservableObject
{
  let settings: AppSettings
  @Published private(set) var settingsRevision = 0
  @Published private(set) var settingsLayout = SettingsWindowLayout(
    visibleSize: CGSize(width: 1440, height: 900))
  private var settingsWindow: NSWindowController?
  private let petLoader = PetPackageLoader()
  private lazy var defaultPetLoader = CodexDefaultPetLoader(
    codexAppURL: Self.resolveCodexAppURL()
  )
  private let petCoordinator = PetCoordinator()
  private let sessionMonitor = AgentSessionMonitor()
  private var sessionChanges = SessionStateChangeTracker()
  private let soundNotifier = SessionSoundNotifier()
  private var notificationPolicy = SessionNotificationPolicy()
  private var previousOrcaAssignments: [String: String] = [:]
  private var previewPlayer: AVAudioPlayer?
  private var previewRole = PetSoundRole.click
  private var previewPetID: String?
  @Published private(set) var previewingSound: URL?
  @Published private(set) var lastSessionCheck: Date?
  @Published private(set) var lastSuccessfulSessionCheck: Date?
  @Published private(set) var sessionDiagnostics: [String] = []
  @Published private(set) var lastOrcaMessageAt: Date?
  @Published private(set) var lastOrcaMessageSender: String?
  @Published var requestedSettingsPetID: String?
  @Published var requestedPetSheet: PetSettingsSheet?
  @Published var requestedRenamePetID: String?
  private(set) var detectedSessions: [DetectedAgentSession] = []
  private(set) var unlinkedProcesses: [DetectedAgentSession] = []
  private(set) var sessionRouting = SessionRouting() {
    didSet { settings.savedRouting = sessionRouting }
  }
  private(set) var sessionDetectionFailed = false

  private var statusItem: NSStatusItem?
  private(set) var petPackages: [PetPackage] = []
  private var previewImages: [String: NSImage] = [:]

  init(settings: AppSettings = AppSettings()) {
    self.settings = settings
    super.init()
    sessionRouting = settings.savedRouting
    soundNotifier.volume = settings.alertVolume
    petCoordinator.configure(
      preferences: settings.petPreferences, clickVolume: settings.clickVolume, muted: settings.soundsMuted)
    petCoordinator.onPreferencesChanged = { [weak self] id, preference in
      guard let self else { return }
      var values = self.settings.petPreferences
      values[id] = preference
      self.settings.petPreferences = values
    }
    petCoordinator.onContextMenu = { [weak self] id in
      guard let self, let pet = self.petPackages.first(where: { $0.id == id }) else { return nil }
      return self.petContextMenu(pet)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    sessionMonitor.stop()
    petCoordinator.hidePets()
    soundNotifier.stop()
    stopSoundPreview()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureMenuBarItem()
    refreshPets()
    showConfiguredPets()
    sessionMonitor.onDiagnostics = { [weak self] values in
      if self?.sessionDiagnostics != values { self?.sessionDiagnostics = values }
    }
    sessionMonitor.onOrcaMessages = { [weak self] events in self?.handleOrcaMessages(events) }
    sessionMonitor.onUpdate = { [weak self] sessions in
      guard let self else { return }
      let next = (sessions ?? []).filter(\.hasConversationIdentity)
      let unlinked = (sessions ?? []).filter { !$0.hasConversationIdentity }
      let failed = sessions == nil
      let changed =
        next != self.detectedSessions || unlinked != self.unlinkedProcesses
        || failed != self.sessionDetectionFailed
      self.lastSessionCheck = Date()
      if !failed { self.lastSuccessfulSessionCheck = Date() }
      self.detectedSessions = next
      self.unlinkedProcesses = unlinked
      self.sessionDetectionFailed = failed
      self.applySessionAnimations()
      if changed { self.rebuildMenu() }
    }
    sessionMonitor.start()
    if CommandLine.arguments.contains("--settings") { openSettings() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    openSettings()
    return true
  }

  private func configureMenuBarItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      if let image = NSImage(
        systemSymbolName: "pawprint.fill", accessibilityDescription: "Multi Codex Pets")
      {
        image.isTemplate = true
        button.image = image
      } else {
        button.title = "Pets"
      }
      button.toolTip = "Multi Codex Pets"
    }

    statusItem = item
    rebuildMenu()
  }

  private func rebuildMenu() {
    let menu = NSMenu()

    settingsRevision += 1
    let toggleTitle = petCoordinator.isShowingPets ? "Hide Pets" : "Show Pets"
    menu.addItem(actionItem(title: localized(toggleTitle), action: #selector(togglePets)))

    let sessionAlerts = actionItem(
      title: localized("Session sound notifications"), action: #selector(toggleSessionSoundNotifications))
    sessionAlerts.state = settings.sessionSoundNotifications ? .on : .off
    menu.addItem(sessionAlerts)

    let modes = NSMenu()
    for mode in PetBehaviorMode.allCases {
      let item = actionItem(
        title: localized(mode.rawValue), action: #selector(selectBehaviorMode(_:)))
      item.representedObject = mode.rawValue
      item.state = behaviorMode == mode ? .on : .off
      modes.addItem(item)
    }
    let modeItem = NSMenuItem(title: localized("Mode"), action: nil, keyEquivalent: "")
    modeItem.submenu = modes
    menu.addItem(modeItem)
    menu.addItem(.separator())
    let settingsItem = actionItem(title: localized("Settings…"), action: #selector(openSettings))
    settingsItem.keyEquivalent = ","
    menu.addItem(settingsItem)
    menu.addItem(.separator())
    menu.addItem(actionItem(title: localized("Quit"), action: #selector(quit)))

    statusItem?.menu = menu
  }

  var behaviorMode: PetBehaviorMode {
    settings.walksAround ? .walking : settings.followsSessions ? .sessions : .manual
  }

  func setBehaviorMode(_ mode: PetBehaviorMode) {
    resetSessionNotifications()
    settings.walksAround = mode == .walking
    settings.followsSessions = mode == .sessions
    petCoordinator.setWalksAround(settings.walksAround, baseState: settings.animationState)
    if settings.followsSessions {
      sessionMonitor.start()
    } else {
      petCoordinator.setAnimationState(settings.animationState)
    }
    applySessionAnimations()
    rebuildMenu()
  }

  @objc private func selectBehaviorMode(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
      let mode = PetBehaviorMode(rawValue: raw)
    else { return }
    setBehaviorMode(mode)
  }

  @objc private func openSettings() {
    if settingsWindow == nil {
      settingsLayout = SettingsWindowLayout(
        visibleSize: NSScreen.main?.visibleFrame.size
          ?? CGSize(width: 1440, height: 900))
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: settingsLayout.contentSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
      window.title = localized("Multi Codex Pets Settings")
      let content = NSHostingView(rootView: SettingsView(app: self))
      content.sizingOptions = []
      window.contentView = content
      window.contentMinSize = settingsLayout.minimumContentSize
      window.delegate = self
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = NSWindowController(window: window)
    }
    settingsWindow?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.window?.makeKeyAndOrderFront(nil)
  }

  func windowDidChangeScreen(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
      window === settingsWindow?.window, let screen = window.screen
    else { return }
    settingsLayout = SettingsWindowLayout(visibleSize: screen.visibleFrame.size)
    window.contentMinSize = settingsLayout.minimumContentSize
    var frame = window.frameRect(
      forContentRect: NSRect(origin: .zero, size: settingsLayout.contentSize))
    frame.origin.x = max(
      screen.visibleFrame.minX,
      min(window.frame.minX, screen.visibleFrame.maxX - frame.width))
    frame.origin.y = max(
      screen.visibleFrame.minY,
      min(window.frame.maxY - frame.height, screen.visibleFrame.maxY - frame.height))
    window.setFrame(frame, display: true)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === settingsWindow?.window else { return }
    requestedSettingsPetID = nil
    requestedPetSheet = nil
    requestedRenamePetID = nil
  }

  func requestSessionChange(_ id: String) {
    requestedSettingsPetID = id
    openSettings()
  }

  func showPetSettings(_ pet: PetPackage, kind: PetSettingsSheet.Kind) {
    openSettings()
    requestedPetSheet = PetSettingsSheet(pet: pet, kind: kind)
  }

  func requestPetRename(_ id: String) {
    openSettings()
    requestedRenamePetID = id
  }

  private func activateSessionSettings() {
    resetSessionNotifications()
    settings.followsSessions = !settings.walksAround
    if !settings.walksAround {
      petCoordinator.setWalksAround(false, baseState: settings.animationState)
    }
    sessionMonitor.start()
    applySessionAnimations()
    rebuildMenu()
  }

  func setSessionMode(_ mode: SessionRouting.Mode) {
    sessionRouting.mode = mode
    if mode == .single, sessionRouting.singleSessionID == nil {
      sessionRouting.singleSessionID = detectedSessions.first?.id
    }
    activateSessionSettings()
  }

  func selectSession(_ sessionID: String, petID: String? = nil) {
    if let petID {
      sessionRouting.mode = .perPet
      sessionRouting.sessionIDsByPet[petID] = sessionID == "automatic" ? nil : sessionID
    } else {
      sessionRouting.mode = .single
      sessionRouting.singleSessionID = sessionID == "automatic" ? nil : sessionID
    }
    activateSessionSettings()
  }

  private func actionItem(title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  func displayName(for pet: PetPackage) -> String {
    settings.petPreferences[pet.id]?.displayName(fallback: pet.displayName) ?? pet.displayName
  }

  func renamePet(_ id: String, to name: String) {
    var values = settings.petPreferences
    var preference = values[id] ?? PetPreferences()
    preference.setCustomName(name)
    values[id] = preference
    settings.petPreferences = values
    petCoordinator.configure(preferences: values, clickVolume: settings.clickVolume, muted: settings.soundsMuted)
    applySessionAnimations()
    rebuildMenu()
  }

  func setPetNameLabel(_ id: String, style: PetNameLabel) {
    var values = settings.petPreferences
    var preference = values[id] ?? PetPreferences()
    preference.nameLabel = style
    values[id] = preference
    settings.petPreferences = values
    petCoordinator.configure(preferences: values, clickVolume: settings.clickVolume, muted: settings.soundsMuted)
    rebuildMenu()
  }

  func previewImage(for package: PetPackage) -> NSImage? {
    if let cached = previewImages[package.id] {
      return cached
    }

    let image = PetPreviewImageFactory.image(for: package)
    previewImages[package.id] = image
    return image
  }

  private func showConfiguredPets() {
    resetSessionNotifications()
    guard !petPackages.isEmpty else {
      petCoordinator.hidePets()
      rebuildMenu()
      return
    }

    let packages = selectedPetPackages
    guard !packages.isEmpty else {
      petCoordinator.hidePets()
      rebuildMenu()
      return
    }

    petCoordinator.setFollowsCursor(settings.followsCursor)
    petCoordinator.showPets(
      packages,
      state: settings.animationState,
      scale: settings.scale
    )
    petCoordinator.setWalksAround(
      settings.walksAround,
      baseState: settings.animationState
    )
    applySessionAnimations()
    rebuildMenu()
  }

  private func refreshPets() {
    let defaults = defaultPetLoader.loadPackages()
    petPackages = defaults + petLoader.loadPackages(excludingIDs: Set(defaults.map(\.id)))
    previewImages.removeAll()
    updateSelectedPetsAfterPackageRefresh()
    if petCoordinator.isShowingPets {
      petCoordinator.hidePets()
      showConfiguredPets()
    } else {
      rebuildMenu()
    }
  }

  @objc private func togglePets() {
    if petCoordinator.isShowingPets {
      resetSessionNotifications()
      petCoordinator.hidePets()
      rebuildMenu()
    } else {
      showConfiguredPets()
    }
  }

  func refreshSessions() { sessionMonitor.refresh() }

  func refreshPetsAction() {
    refreshPets()
  }

  private func resetSessionNotifications() {
    sessionChanges.reset()
    notificationPolicy.reset()
    soundNotifier.stop()
    previousOrcaAssignments.removeAll()
    sessionMonitor.resetOrcaMessageBaseline()
  }

  private func applySessionAnimations() {
    let petIDs = selectedPetPackages.map(\.id)
    let assigned = sessionRouting.resolvedSessions(for: petIDs, sessions: detectedSessions)
    if settings.followsSessions {
      let animations = settings.sessionAnimations
      petCoordinator.setSessionAnimations(assigned.map { animations.animation(for: $0?.activity) })
    }
    let enabled =
      (settings.followsSessions || settings.walksAround) && settings.sessionSoundNotifications
      && !settings.soundsMuted && petCoordinator.isShowingPets && !sessionDetectionFailed
    sessionMonitor.observesOrcaMessages = settings.orcaMessageNotifications
      && (settings.followsSessions || settings.walksAround)
      && petCoordinator.isShowingPets && !sessionDetectionFailed
    var assignments: [String: DetectedAgentSession] = [:]
    for (petID, session) in zip(petIDs, assigned) { assignments[petID] = session }
    let changed = sessionChanges.changedPets(assignments: assignments, enabled: enabled)
    if !enabled { soundNotifier.stop() }
    let library = PetSoundLibrary(codexHome: petLoader.codexHome)
    for petID in changed {
      guard let session = assignments[petID], settings.petPreferences[petID]?.muted != true,
        notificationPolicy.shouldNotify(
          petID: petID, activity: session.activity,
          allowed: settings.notifiedActivities, cooldown: settings.notificationCooldown)
      else { continue }
      soundNotifier.enqueue(
        petID: petID,
        sounds: library.soundURLs(forPetID: petID, role: .notification, activity: session.activity),
        petVolume: settings.petPreferences[petID]?.resolvedSoundVolume ?? 1)
    }
    var tooltips = Dictionary(uniqueKeysWithValues: selectedPetPackages.map { ($0.id, displayName(for: $0)) })
    for (id, session) in assignments {
      tooltips[id] =
        "\(tooltips[id] ?? "")\n\(session.title ?? localized("Untitled session"))\n\(session.kind.rawValue) · \(localized(session.activity.rawValue))"
    }
    petCoordinator.setSessionTooltips(tooltips)
  }

  private func handleOrcaMessages(_ events: [OrcaMessageEvent]) {
    let pets = selectedPetPackages.map(\.id)
    let sessions = sessionRouting.resolvedSessions(for: pets, sessions: detectedSessions)
    let assignments = Dictionary(uniqueKeysWithValues: zip(pets, sessions).compactMap { id, session in
      session.map { (id, $0.id) }
    })
    defer { previousOrcaAssignments = assignments }
    guard settings.orcaMessageNotifications else { return }
    if let event = events.last,
      let sender = detectedSessions.first(where: { $0.id == event.senderSessionID }) {
      lastOrcaMessageSender = sender.title ?? localized("Untitled session")
      lastOrcaMessageAt = Date()
    }
    guard (settings.followsSessions || settings.walksAround), settings.sessionSoundNotifications,
      !settings.soundsMuted, petCoordinator.isShowingPets, !sessionDetectionFailed else { return }
    let senders = Set(events.map(\.senderSessionID))
    let library = PetSoundLibrary(codexHome: petLoader.codexHome)
    for petID in pets {
      guard let sessionID = assignments[petID], senders.contains(sessionID),
        previousOrcaAssignments[petID] == sessionID,
        settings.petPreferences[petID]?.muted != true,
        notificationPolicy.shouldNotify(petID: petID, notificationKey: OrcaMessageEvent.soundKey,
          cooldown: settings.notificationCooldown) else { continue }
      soundNotifier.enqueue(petID: petID,
        sounds: library.soundURLs(forPetID: petID, role: .notification,
          notificationKey: OrcaMessageEvent.soundKey),
        petVolume: settings.petPreferences[petID]?.resolvedSoundVolume ?? 1,
        notificationKey: OrcaMessageEvent.soundKey)
    }
  }

  func setOrcaMessageNotifications(_ enabled: Bool) {
    settings.orcaMessageNotifications = enabled
    resetSessionNotifications()
    applySessionAnimations()
    rebuildMenu()
  }

  @objc private func toggleSessionSoundNotifications() {
    setSessionSoundNotifications(!settings.sessionSoundNotifications)
  }

  func setSessionSoundNotifications(_ enabled: Bool) {
    settings.sessionSoundNotifications = enabled
    resetSessionNotifications()
    applySessionAnimations()
    rebuildMenu()
  }

  func toggleVisiblePet(_ id: String) {
    var ids = settings.selectedPetIDs ?? legacySelectedPetIDs()
    if ids.contains(id) {
      ids.removeAll { $0 == id }
    } else {
      ids.append(id)
    }
    settings.selectedPetIDs = ids

    showConfiguredPets()
  }

  func selectAllPets() {
    settings.selectedPetIDs = petPackages.map(\.id)
    showConfiguredPets()
  }

  func clearVisiblePets() {
    settings.selectedPetIDs = []
    showConfiguredPets()
  }

  func setSessionAnimation(_ state: MultiCodexPetsCore.AnimationState, for activity: AgentActivity) {
    var animations = settings.sessionAnimations
    animations.overrides[activity.rawValue] = state == activity.animationState ? nil : state.rawValue
    settings.sessionAnimations = animations
    applySessionAnimations()
    rebuildMenu()
  }

  func resetSessionAnimations() {
    settings.sessionAnimations = SessionAnimations()
    applySessionAnimations()
    rebuildMenu()
  }

  func setAnimationState(_ state: MultiCodexPetsCore.AnimationState) {
    resetSessionNotifications()
    settings.walksAround = false
    petCoordinator.setWalksAround(false, baseState: state)
    settings.followsSessions = false
    settings.animationState = state
    petCoordinator.setAnimationState(state)
    rebuildMenu()
  }

  func setFollowsCursor(_ enabled: Bool) {
    settings.followsCursor = enabled
    petCoordinator.setFollowsCursor(enabled)
    rebuildMenu()
  }

  func setScale(_ scale: Double) {
    let value = min(max(scale.isFinite ? scale : 1, 0.5), 2)
    settings.scale = value
    petCoordinator.setScale(value)
    rebuildMenu()
  }

  func sounds(for id: String, role: PetSoundRole? = nil, activity: AgentActivity? = nil, notificationKey: String? = nil) -> [URL] {
    PetSoundLibrary(codexHome: petLoader.codexHome).soundURLs(
      forPetID: id, role: role, activity: activity, notificationKey: notificationKey)
  }

  func setSoundUsage(
    _ enabled: Bool, filename: String, petID: String, role: PetSoundRole,
    activity: AgentActivity? = nil, notificationKey: String? = nil
  ) {
    do {
      try PetSoundLibrary(codexHome: petLoader.codexHome).setUsage(
        enabled, filename: filename,
        forPetID: petID, role: role, activity: activity, notificationKey: notificationKey)
      if role == .notification { soundNotifier.stop() }
      rebuildMenu()
    } catch {
      if let window = settingsWindow?.window {
        NSAlert(error: error).beginSheetModal(for: window.attachedSheet ?? window)
      }
    }
  }

  func chooseSoundFile(for id: String, role: PetSoundRole = .click, activity: AgentActivity? = nil, notificationKey: String? = nil)
  {
    guard let root = settingsWindow?.window else { return }
    let window = root.attachedSheet ?? root
    let panel = NSOpenPanel()
    panel.title = localized(role == .click ? "Add Click Sounds" : "Add Notification Sounds")
    panel.message = localized(
      "Selected files are copied to this pet’s sound folder. Existing files are kept.")
    panel.prompt = localized("Add")
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = PetSoundLibrary.supportedExtensions.sorted().compactMap {
      UTType(filenameExtension: $0)
    }
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK else { return }
      defer { self.rebuildMenu() }
      do {
        // Validate every file before importing any of the selected audio.
        for url in panel.urls { _ = try AVAudioPlayer(contentsOf: url) }
        let library = PetSoundLibrary(codexHome: self.petLoader.codexHome)
        for url in panel.urls {
          try library.importSound(from: url, forPetID: id, role: role, activity: activity, notificationKey: notificationKey)
        }
      } catch {
        NSAlert(error: error).beginSheetModal(for: window)
      }
    }
  }

  func useDefaultAlertPool(petID: String, activity: AgentActivity? = nil, notificationKey: String? = nil) {
    do {
      try PetSoundLibrary(codexHome: petLoader.codexHome).useDefaultNotificationPool(
        forPetID: petID, activity: activity, notificationKey: notificationKey)
      rebuildMenu()
    } catch { NSSound.beep() }
  }

  func setNotifiedActivity(_ activity: AgentActivity, enabled: Bool) {
    var values = settings.notifiedActivities
    if enabled { values.insert(activity) } else { values.remove(activity) }
    settings.notifiedActivities = values
    resetSessionNotifications()
    rebuildMenu()
  }

  func setNotificationCooldown(_ seconds: Double) {
    settings.notificationCooldown = seconds
    notificationPolicy.reset()
    rebuildMenu()
  }

  func setVolume(_ value: Float, role: PetSoundRole) {
    if role == .click { settings.clickVolume = value } else { settings.alertVolume = value }
    soundNotifier.volume = settings.alertVolume
    petCoordinator.configure(
      preferences: settings.petPreferences, clickVolume: settings.clickVolume, muted: settings.soundsMuted)
    if previewRole == role, let previewPetID {
      previewPlayer?.volume = soundVolume(for: previewPetID, role: role)
    }
    rebuildMenu()
  }


  func setSoundsMuted(_ enabled: Bool) {
    settings.soundsMuted = enabled
    if enabled { stopSoundPreview() }
    resetSessionNotifications()
    petCoordinator.configure(preferences: settings.petPreferences,
      clickVolume: settings.clickVolume, muted: enabled)
    applySessionAnimations()
    rebuildMenu()
  }

  func soundVolume(for petID: String, role: PetSoundRole) -> Float {
    let preference = settings.petPreferences[petID] ?? PetPreferences()
    guard !settings.soundsMuted, !preference.muted else { return 0 }
    return (role == .click ? settings.clickVolume : settings.alertVolume) * preference.resolvedSoundVolume
  }

  func previewSound(_ url: URL, role: PetSoundRole, petID: String) {
    guard !settings.soundsMuted, settings.petPreferences[petID]?.muted != true else { return }
    if previewingSound == url {
      stopSoundPreview()
      return
    }
    stopSoundPreview()
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.volume = soundVolume(for: petID, role: role)
      player.delegate = self
      if player.play() {
        previewPlayer = player
        previewPetID = petID
        previewRole = role
        previewingSound = url
      }
    } catch { NSSound.beep() }
  }

  func stopSoundPreview() {
    previewPlayer?.stop()
    previewPlayer = nil
    previewingSound = nil
    previewPetID = nil
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if player === previewPlayer { stopSoundPreview() }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    if player === previewPlayer { stopSoundPreview() }
  }

  var availableScreens: [(id: UInt32, name: String)] {
    NSScreen.screens.compactMap { screen in
      guard
        let id =
          (screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?
          .uint32Value
      else {
        return nil
      }
      return (id, screen.localizedName)
    }
  }

  func setPetPreference(_ id: String, locked: Bool? = nil, muted: Bool? = nil,
    cursorTrackingMode: PetCursorTrackingMode? = nil, soundVolume: Float? = nil) {
    var values = settings.petPreferences
    var preference = values[id] ?? PetPreferences()
    if let cursorTrackingMode { preference.cursorTrackingMode = cursorTrackingMode }
    if let soundVolume { preference.soundVolume = soundVolume.isFinite ? min(max(soundVolume, 0), 1) : 1 }
    if let locked { preference.positionLocked = locked }
    if let muted {
      preference.muted = muted
      if muted {
        soundNotifier.cancel(petID: id)
        if previewPetID == id { stopSoundPreview() }
      }
    }
    values[id] = preference
    settings.petPreferences = values
    soundNotifier.setPetVolume(preference.resolvedSoundVolume, petID: id)
    if previewPetID == id { previewPlayer?.volume = self.soundVolume(for: id, role: previewRole) }
    petCoordinator.configure(preferences: values, clickVolume: settings.clickVolume, muted: settings.soundsMuted)
    rebuildMenu()
  }

  func movePet(_ id: String, to screenID: UInt32) {
    guard
      let screen = NSScreen.screens.first(where: {
        ($0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?
          .uint32Value == screenID
      })
    else { return }
    var values = settings.petPreferences
    var preference = values[id] ?? PetPreferences()
    preference.screenID = screenID
    preference.frame = nil
    values[id] = preference
    settings.petPreferences = values
    petCoordinator.configure(preferences: values, clickVolume: settings.clickVolume, muted: settings.soundsMuted)
    petCoordinator.movePet(id, to: screen)
    rebuildMenu()
  }

  func recoverPetPositions() {
    petCoordinator.recoverPets()
    rebuildMenu()
  }

  func assignedSession(for petID: String) -> DetectedAgentSession? {
    let ids = selectedPetPackages.map(\.id)
    guard let index = ids.firstIndex(of: petID) else { return nil }
    return sessionRouting.resolvedSessions(for: ids, sessions: detectedSessions)[index]
  }

  func cursorTrackingMode(for petID: String) -> PetCursorTrackingMode {
    settings.petPreferences[petID]?.cursorTrackingMode ?? (settings.followsCursor ? .always : .off)
  }

  func petContextMenu(_ pet: PetPackage) -> NSMenu {
    let id = pet.id
    let menu = NSMenu()
    menu.autoenablesItems = false
    let session = assignedSession(for: id)
    let title =
      (session?.title ?? localized(session == nil ? "No connected session" : "Untitled session"))
      .components(separatedBy: .newlines).joined(separator: " ")
    let header = NSMenuItem(
      title: title.count > 36 ? String(title.prefix(36)) + "…" : title,
      action: nil, keyEquivalent: "")
    header.isEnabled = false
    header.toolTip = title
    let image =
      session.flatMap { AgentBrandImages.images[$0.kind] }
      ?? NSImage(systemSymbolName: "pawprint", accessibilityDescription: nil)
    if let icon = image?.copy() as? NSImage {
      let longestEdge = max(icon.size.width, icon.size.height)
      if longestEdge > 0 {
        icon.size = NSSize(
          width: icon.size.width * 16 / longestEdge, height: icon.size.height * 16 / longestEdge)
      }
      header.image = icon
    }
    let name = displayName(for: pet)
    let nameField = NSTextField(labelWithString: name)
    nameField.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
    nameField.textColor = .labelColor
    nameField.lineBreakMode = .byTruncatingTail
    let label = NSTextField(labelWithString: header.title)
    label.font = .menuFont(ofSize: 0)
    label.textColor = .labelColor
    label.lineBreakMode = .byTruncatingTail
    let width = min(520, max(180, max(label.fittingSize.width + 52, nameField.fittingSize.width + 28)))
    let headerHeight: CGFloat = session == nil ? 50 : 70
    let headerView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
    nameField.frame = NSRect(x: 14, y: headerHeight - 23, width: width - 28, height: 18)
    headerView.addSubview(nameField)
    let iconView = NSImageView(frame: NSRect(x: 14, y: headerHeight - 44, width: 16, height: 16))
    iconView.image = header.image
    iconView.contentTintColor = .labelColor
    headerView.addSubview(iconView)
    label.frame = NSRect(x: 36, y: headerHeight - 45, width: width - 48, height: 18)
    headerView.addSubview(label)
    let activity = session.map { localized($0.activity.rawValue) } ?? localized("No connected session")
    let status = NSTextField(labelWithString: activity)
    status.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
    status.textColor = .secondaryLabelColor
    status.frame = NSRect(x: 36, y: 6, width: width - 48, height: 16)
    status.lineBreakMode = .byTruncatingTail
    status.isHidden = session == nil
    headerView.addSubview(status)
    headerView.toolTip = [name, title, activity].joined(separator: "\n")
    header.view = headerView
    menu.addItem(header)
    menu.addItem(.separator())
    let openAgent = actionItem(title: localized("Open Agent App"), action: #selector(openPetAgent(_:)))
    openAgent.representedObject = id
    openAgent.isEnabled = session != nil
    menu.addItem(openAgent)
    let changeSession = actionItem(title: localized("Change Session…"), action: #selector(changePetSession(_:)))
    changeSession.representedObject = id
    changeSession.isEnabled = selectedPetIDs.contains(id)
    menu.addItem(changeSession)
    menu.addItem(.separator())
    let preference = settings.petPreferences[id] ?? PetPreferences()
    for (title, action, checked) in [
      ("Lock Position", #selector(togglePetLock(_:)), preference.positionLocked),
      ("Mute This Pet", #selector(togglePetMute(_:)), preference.muted),
    ] {
      let item = actionItem(title: localized(title), action: action)
      item.representedObject = id
      item.state = checked ? .on : .off
      menu.addItem(item)
    }
    if pet.spriteVersion == .v2 {
      let tracking = NSMenuItem(title: localized("Cursor Tracking"), action: nil, keyEquivalent: "")
      let modes = NSMenu()
      modes.autoenablesItems = false
      for mode in PetCursorTrackingMode.allCases {
        let item = actionItem(title: localized(mode.rawValue), action: #selector(changePetCursorTracking(_:)))
        item.representedObject = [id, mode.rawValue]
        item.state = cursorTrackingMode(for: id) == mode ? .on : .off
        modes.addItem(item)
      }
      tracking.submenu = modes
      tracking.toolTip = localized("Looks while idle, waiting for input, or completed. Generating, review, failure, dragging, and Reduce Motion take priority.")
      menu.addItem(tracking)
    }
    menu.addItem(.separator())
    for (title, action) in [
      ("Sounds…", #selector(editPetSounds(_:))),
      ("Rename Pet…", #selector(editPetName(_:))),
      ("Name Label…", #selector(editPetNameLabel(_:))),
      ("Animations…", #selector(previewPetAnimations(_:))),
    ] {
      let item = actionItem(title: localized(title), action: action)
      item.representedObject = id
      menu.addItem(item)
    }
    let displayItem = NSMenuItem(title: localized("Move to Display"), action: nil, keyEquivalent: "")
    let displays = NSMenu()
    displays.autoenablesItems = false
    for screen in availableScreens {
      let item = actionItem(title: screen.name, action: #selector(movePetToDisplay(_:)))
      item.representedObject = id
      item.tag = Int(screen.id)
      item.state = preference.screenID == screen.id ? .on : .off
      displays.addItem(item)
    }
    displayItem.submenu = displays
    menu.addItem(displayItem)
    let folder = actionItem(title: localized("Open Sound Folder…"), action: #selector(openPetSoundFolder(_:)))
    folder.representedObject = id
    menu.addItem(folder)
    return menu
  }

  @objc private func editPetNameLabel(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
      petPackages.contains(where: { $0.id == id })
    else { return }
    guard let pet = petPackages.first(where: { $0.id == id }) else { return }
    showPetSettings(pet, kind: .nameLabel)
  }

  @objc private func editPetSounds(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
      let pet = petPackages.first(where: { $0.id == id }) else { return }
    showPetSettings(pet, kind: .sounds)
  }

  @objc private func previewPetAnimations(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
      let pet = petPackages.first(where: { $0.id == id }) else { return }
    showPetSettings(pet, kind: .animations)
  }

  @objc private func editPetName(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    requestPetRename(id)
  }

  @objc private func openPetSoundFolder(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    openSoundFolder(id)
  }

  @objc private func movePetToDisplay(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String,
      let screenID = UInt32(exactly: sender.tag) else { return }
    movePet(id, to: screenID)
  }

  @objc private func changePetCursorTracking(_ sender: NSMenuItem) {
    guard let values = sender.representedObject as? [String], values.count == 2,
      let mode = PetCursorTrackingMode(rawValue: values[1]) else { return }
    setPetPreference(values[0], cursorTrackingMode: mode)
  }

  @objc private func togglePetMute(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    setPetPreference(id, muted: !(settings.petPreferences[id]?.muted ?? false))
  }
  @objc private func togglePetLock(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    setPetPreference(id, locked: !(settings.petPreferences[id]?.positionLocked ?? false))
  }
  @objc private func changePetSession(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    requestSessionChange(id)
  }
  @objc private func openPetAgent(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    openAgentApp(for: id)
  }

  func openAgentApp(for id: String) {
    guard let session = assignedSession(for: id)
    else { return }
    let bundleID: String
    switch session.kind {
    case .orca: bundleID = "com.stablyai.orca"
    case .codex: bundleID = "com.openai.codex"
    case .claude: bundleID = "com.anthropic.claudefordesktop"
    case .antigravity: bundleID = "com.google.antigravity"
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      NSSound.beep()
      return
    }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  func openSoundFolder(_ id: String) {
    guard let folder = PetSoundLibrary(codexHome: petLoader.codexHome).directory(forPetID: id)
    else { return }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      if !NSWorkspace.shared.open(folder) {
        NSSound.beep()
      }
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  func openPetFolder() {
    do {
      try petLoader.ensurePetsDirectoryExists()
      NSWorkspace.shared.open(petLoader.petsDirectory)
    } catch {
      NSSound.beep()
    }
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  var scaleOptions: [(title: String, value: Double)] {
    [
      ("75%", 0.75),
      ("100%", 1.0),
      ("125%", 1.25),
      ("150%", 1.5),
    ]
  }

  var selectedPetIDs: Set<String> {
    Set(settings.selectedPetIDs ?? legacySelectedPetIDs())
  }

  var selectedPetPackages: [PetPackage] {
    let ids = selectedPetIDs
    return petPackages.filter { ids.contains($0.id) }
  }

  private func updateSelectedPetsAfterPackageRefresh() {
    guard settings.selectedPetIDs == nil else { return }
    guard !petPackages.isEmpty else { return }
    settings.selectedPetIDs = legacySelectedPetIDs()
  }

  private func legacySelectedPetIDs() -> [String] {
    guard !petPackages.isEmpty else { return [] }

    if settings.visiblePetCount == -1 {
      return petPackages.map(\.id)
    }

    let count = min(max(1, settings.visiblePetCount), petPackages.count)
    return Array(petPackages.prefix(count)).map(\.id)
  }

  private static func resolveCodexAppURL() -> URL {
    if let override = ProcessInfo.processInfo.environment["CODEX_APP_PATH"]?.trimmedNonEmpty {
      return URL(fileURLWithPath: override, isDirectory: true)
    }

    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
      ?? CodexDefaultPetLoader.defaultCodexAppURL()
  }
}
