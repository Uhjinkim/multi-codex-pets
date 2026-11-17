import AppKit
import MultiCodexPetsCore

final class PetCoordinator {
  private var windowControllersByPetID: [String: PetWindowController] = [:]
  private var visiblePetIDs: [String] = []
  private var rememberedFramesByPetID: [String: NSRect] = [:]
  private var walkingMotionsByPetID: [String: WalkingMotion] = [:]
  private var walkingTimer: Timer?
  private var lastWalkingTickAt: Date?
  private var walksAround = false
  private var followsCursor = true
  private var preferences: [String: PetPreferences] = [:]
  private var clickVolume: Float = 1
  private var soundsMuted = false
  var onPreferencesChanged: ((String, PetPreferences) -> Void)?
  var onContextMenu: ((String) -> NSMenu?)?

  func configure(preferences: [String: PetPreferences], clickVolume: Float, muted: Bool = false) {
    self.preferences = preferences
    self.clickVolume = clickVolume
    soundsMuted = muted
    for (id, controller) in windowControllersByPetID {
      let preference = preferences[id] ?? PetPreferences()
      controller.setInteraction(
        volume: clickVolume * preference.resolvedSoundVolume,
        muted: soundsMuted || preference.muted, locked: preference.positionLocked)
      controller.setCursorTrackingMode(preference.cursorTrackingMode ?? (followsCursor ? .always : .off))
      controller.setNameLabel(preference.displayName(fallback: controller.pet.displayName),
        style: preference.nameLabel ?? PetNameLabel())
    }
    updateWalkingTimer()
  }

  func setSessionTooltips(_ values: [String: String]) {
    for (id, controller) in windowControllersByPetID {
      controller.setSessionTooltip(values[id] ?? controller.pet.displayName)
    }
  }

  func movePet(_ id: String, to screen: NSScreen) {
    guard let controller = windowControllersByPetID[id], let frame = controller.currentFrame else {
      return
    }
    let target = PetPlacement.fitted(
      CGRect(
        x: screen.visibleFrame.midX - frame.width / 2,
        y: screen.visibleFrame.minY + 80, width: frame.width, height: frame.height),
      to: screen.visibleFrame)
    controller.setFrameOrigin(target.origin)
    remember(id, frame: target, screen: screen)
  }

  func recoverPets() {
    for (id, controller) in windowControllersByPetID {
      guard let frame = controller.currentFrame else { continue }
      let screen = screenForPet(id, frame: frame)
      let fitted = PetPlacement.fitted(frame, to: screen.visibleFrame)
      controller.setFrameOrigin(fitted.origin)
      remember(id, frame: fitted, screen: screen)
    }
  }

  private func screenForPet(_ id: String, frame: NSRect? = nil) -> NSScreen {
    let saved = preferences[id]?.screenID
    return NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?
        .uint32Value == saved
    }
      ?? frame.flatMap { frame in NSScreen.screens.first { $0.visibleFrame.intersects(frame) } }
      ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private func remember(_ id: String, frame: NSRect, screen: NSScreen? = nil) {
    rememberedFramesByPetID[id] = frame
    var preference = preferences[id] ?? PetPreferences()
    preference.frame = frame
    let target =
      screen
      ?? NSScreen.screens.first { $0.visibleFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
    preference.screenID =
      (target?.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?
      .uint32Value
    preferences[id] = preference
    onPreferencesChanged?(id, preference)
  }

  var isShowingPets: Bool {
    !visiblePetIDs.isEmpty
  }

  func showPets(
    _ packages: [PetPackage],
    state: AnimationState,
    scale: Double
  ) {
    guard !packages.isEmpty else {
      hidePets()
      return
    }

    let requestedPetIDs = Set(packages.map(\.id))
    let removedPetIDs = visiblePetIDs.filter { !requestedPetIDs.contains($0) }
    for petID in removedPetIDs {
      closeController(forPetID: petID)
    }

    var nextVisiblePetIDs: [String] = []
    for (index, package) in packages.enumerated() {
      let controller =
        existingController(for: package)
        ?? makeController(for: package, index: index, state: state, scale: scale)
      controller.setCursorTrackingMode(preferences[package.id]?.cursorTrackingMode ?? (followsCursor ? .always : .off))
      controller.setScale(scale)
      let now = Date()
      let motion = walkingMotion(
        forPetID: package.id,
        frame: controller.currentFrame,
        now: now
      )
      controller.setAnimationState(
        walksAround ? walkingAnimationState(for: motion.velocity) : state,
        randomizeInitialFrame: walksAround
      )
      controller.show()
      windowControllersByPetID[package.id] = controller
      nextVisiblePetIDs.append(package.id)
    }

    visiblePetIDs = nextVisiblePetIDs
    updateWalkingTimer()
  }

  func hidePets() {
    for petID in visiblePetIDs {
      closeController(forPetID: petID)
    }
    visiblePetIDs.removeAll()
    updateWalkingTimer()
  }

  func setAnimationState(_ state: AnimationState) {
    guard !walksAround else { return }

    for controller in visibleControllers {
      controller.setAnimationState(state)
    }
  }

  func setSessionAnimations(_ states: [AnimationState]) {
    guard !walksAround else { return }
    for (petID, state) in zip(visiblePetIDs, states) {
      windowControllersByPetID[petID]?.setAnimationState(state)
    }
  }

  func setFollowsCursor(_ enabled: Bool) {
    followsCursor = enabled
    for controller in visibleControllers {
      controller.setCursorTrackingMode(preferences[controller.pet.id]?.cursorTrackingMode ?? (enabled ? .always : .off))
    }
  }

  func setScale(_ scale: Double) {
    for controller in visibleControllers {
      controller.setScale(scale)
    }
  }

  func setWalksAround(_ enabled: Bool, baseState: AnimationState) {
    walksAround = enabled

    if enabled {
      let now = Date()
      for petID in visiblePetIDs {
        let motion = walkingMotion(
          forPetID: petID,
          frame: windowControllersByPetID[petID]?.currentFrame,
          now: now
        )
        windowControllersByPetID[petID]?.setAnimationState(
          walkingAnimationState(for: motion.velocity),
          randomizeInitialFrame: true
        )
      }
    } else {
      for controller in visibleControllers {
        controller.setAnimationState(baseState)
      }
    }

    updateWalkingTimer()
  }

  private var visibleControllers: [PetWindowController] {
    visiblePetIDs.compactMap { windowControllersByPetID[$0] }
  }

  private func existingController(for package: PetPackage) -> PetWindowController? {
    guard let controller = windowControllersByPetID[package.id] else {
      return nil
    }

    guard controller.pet == package else {
      closeController(forPetID: package.id)
      return nil
    }

    return controller
  }

  private func makeController(
    for package: PetPackage,
    index: Int,
    state: AnimationState,
    scale: Double
  ) -> PetWindowController {
    let controller = PetWindowController(
      pet: package,
      initialFrame: initialFrame(forPetID: package.id, index: index, scale: scale),
      animationState: state,
      scale: scale
    )
    let preference = preferences[package.id] ?? PetPreferences()
    controller.setInteraction(
      volume: clickVolume * preference.resolvedSoundVolume,
      muted: soundsMuted || preference.muted, locked: preference.positionLocked)
    controller.setNameLabel(preference.displayName(fallback: package.displayName),
      style: preference.nameLabel ?? PetNameLabel())
    controller.onFrameChanged = { [weak self] frame in self?.remember(package.id, frame: frame) }
    controller.setContextMenuProvider { [weak self] in self?.onContextMenu?(package.id) }
    return controller
  }

  private func closeController(forPetID petID: String) {
    guard let controller = windowControllersByPetID.removeValue(forKey: petID) else {
      return
    }

    if let frame = controller.currentFrame {
      remember(petID, frame: frame)
    }
    walkingMotionsByPetID.removeValue(forKey: petID)
    controller.close()
  }

  private func updateWalkingTimer() {
    guard walksAround,
      visibleControllers.contains(where: { !$0.isPositionLocked })
    else {
      walkingTimer?.invalidate()
      walkingTimer = nil
      lastWalkingTickAt = nil
      return
    }

    guard walkingTimer == nil else { return }

    lastWalkingTickAt = Date()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      self?.moveWalkingPets()
    }
    RunLoop.main.add(timer, forMode: .common)
    walkingTimer = timer
  }

  private func moveWalkingPets() {
    let now = Date()
    let elapsed = min(now.timeIntervalSince(lastWalkingTickAt ?? now), 0.1)
    lastWalkingTickAt = now

    guard elapsed > 0 else { return }

    for petID in visiblePetIDs {
      guard let controller = windowControllersByPetID[petID],
        !controller.isUserDragging, !controller.isPositionLocked,
        let frame = controller.currentFrame
      else {
        continue
      }

      let screenFrame = screenFrame(containing: frame)
      var motion = walkingMotion(
        forPetID: petID,
        frame: frame,
        now: now
      )
      if now >= motion.retargetAt || frame.origin.distance(to: motion.targetOrigin) < 32 {
        motion = randomWalkingMotion(
          now: now,
          frame: frame,
          screenFrame: screenFrame
        )
      } else {
        motion.velocity = velocity(from: frame.origin, to: motion.targetOrigin, speed: motion.speed)
      }

      let movement = walkingMovement(
        frame: frame,
        velocity: motion.velocity,
        elapsed: elapsed,
        screenFrame: screenFrame
      )

      if movement.didBounce {
        motion = randomWalkingMotion(
          now: now,
          frame: NSRect(origin: movement.origin, size: frame.size),
          screenFrame: screenFrame
        )
      } else {
        motion.velocity = movement.velocity
      }
      walkingMotionsByPetID[petID] = motion
      controller.setFrameOrigin(movement.origin)
      controller.setAnimationState(walkingAnimationState(for: motion.velocity))
    }
  }

  private func walkingMotion(forPetID petID: String, frame: NSRect?, now: Date) -> WalkingMotion {
    if let motion = walkingMotionsByPetID[petID] {
      return motion
    }

    let frame = frame ?? NSRect(origin: .zero, size: PetWindowController.windowSize(scale: 1))
    let motion = randomWalkingMotion(
      now: now,
      frame: frame,
      screenFrame: screenFrame(containing: frame)
    )
    walkingMotionsByPetID[petID] = motion
    return motion
  }

  private func randomWalkingMotion(
    now: Date,
    frame: NSRect,
    screenFrame: NSRect
  ) -> WalkingMotion {
    let targetOrigin = randomTargetOrigin(for: frame, in: screenFrame)
    let speed = CGFloat.random(in: 38...62)
    let retargetDelay = TimeInterval.random(in: 6.0...14.0)

    return WalkingMotion(
      velocity: velocity(from: frame.origin, to: targetOrigin, speed: speed),
      targetOrigin: targetOrigin,
      speed: speed,
      retargetAt: now.addingTimeInterval(retargetDelay)
    )
  }

  private func randomTargetOrigin(for frame: NSRect, in screenFrame: NSRect) -> NSPoint {
    let padding: CGFloat = 24
    let minX = screenFrame.minX + padding
    let maxX = max(minX, screenFrame.maxX - frame.width - padding)
    let minY = screenFrame.minY + padding
    let maxY = max(minY, screenFrame.maxY - frame.height - padding)

    return NSPoint(
      x: CGFloat.random(in: minX...maxX),
      y: CGFloat.random(in: minY...maxY)
    )
  }

  private func velocity(from origin: NSPoint, to target: NSPoint, speed: CGFloat) -> CGVector {
    let deltaX = target.x - origin.x
    let deltaY = target.y - origin.y
    let distance = max(1, hypot(deltaX, deltaY))

    return CGVector(
      dx: deltaX / distance * speed,
      dy: deltaY / distance * speed
    )
  }

  private func walkingMovement(
    frame: NSRect,
    velocity: CGVector,
    elapsed: TimeInterval,
    screenFrame: NSRect
  ) -> WalkingMovement {
    let elapsed = CGFloat(elapsed)
    let minOriginX = screenFrame.minX
    let maxOriginX = max(minOriginX, screenFrame.maxX - frame.width)
    let minOriginY = screenFrame.minY
    let maxOriginY = max(minOriginY, screenFrame.maxY - frame.height)
    var nextOrigin = NSPoint(
      x: frame.origin.x + velocity.dx * elapsed,
      y: frame.origin.y + velocity.dy * elapsed
    )
    var nextVelocity = velocity
    var bouncedHorizontally = false
    var bouncedVertically = false

    if nextOrigin.x <= minOriginX {
      nextOrigin.x = minOriginX
      nextVelocity.dx = abs(nextVelocity.dx)
      bouncedHorizontally = true
    } else if nextOrigin.x >= maxOriginX {
      nextOrigin.x = maxOriginX
      nextVelocity.dx = -abs(nextVelocity.dx)
      bouncedHorizontally = true
    }

    if nextOrigin.y <= minOriginY {
      nextOrigin.y = minOriginY
      nextVelocity.dy = abs(nextVelocity.dy)
      bouncedVertically = true
    } else if nextOrigin.y >= maxOriginY {
      nextOrigin.y = maxOriginY
      nextVelocity.dy = -abs(nextVelocity.dy)
      bouncedVertically = true
    }

    return WalkingMovement(
      origin: nextOrigin,
      velocity: nextVelocity,
      bouncedHorizontally: bouncedHorizontally,
      bouncedVertically: bouncedVertically
    )
  }

  private func walkingAnimationState(for velocity: CGVector) -> AnimationState {
    velocity.dx < 0 ? .runningLeft : .runningRight
  }

  private func screenFrame(containing frame: NSRect) -> NSRect {
    let matchingScreen = NSScreen.screens.first { screen in
      screen.visibleFrame.intersects(frame)
    }

    return matchingScreen?.visibleFrame
      ?? NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
  }

  private func initialFrame(forPetID petID: String, index: Int, scale: Double) -> NSRect {
    let saved = rememberedFramesByPetID[petID] ?? preferences[petID]?.frame
    let screen = screenForPet(petID, frame: saved)
    if let saved {
      return PetPlacement.fitted(
        NSRect(origin: saved.origin, size: PetWindowController.windowSize(scale: scale)),
        to: screen.visibleFrame)
    }
    return defaultInitialFrame(index: index, scale: scale, screen: screen.visibleFrame)
  }

  private func defaultInitialFrame(index: Int, scale: Double, screen: NSRect) -> NSRect {
    let size = PetWindowController.windowSize(scale: scale)
    let horizontalStep = size.width + 22
    let rowOffset = CGFloat(index % 2) * 32
    let originX = max(
      screen.minX + 24,
      screen.maxX - size.width - 80 - CGFloat(index) * horizontalStep
    )
    let originY = min(
      screen.maxY - size.height - 24,
      screen.minY + 96 + rowOffset
    )

    return NSRect(origin: NSPoint(x: originX, y: originY), size: size)
  }
}

private struct WalkingMotion {
  var velocity: CGVector
  var targetOrigin: NSPoint
  var speed: CGFloat
  var retargetAt: Date
}

private struct WalkingMovement {
  let origin: NSPoint
  let velocity: CGVector
  let bouncedHorizontally: Bool
  let bouncedVertically: Bool

  var didBounce: Bool {
    bouncedHorizontally || bouncedVertically
  }
}

extension NSPoint {
  fileprivate func distance(to point: NSPoint) -> CGFloat {
    hypot(point.x - x, point.y - y)
  }
}
