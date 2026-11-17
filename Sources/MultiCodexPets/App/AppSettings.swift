import Foundation
import MultiCodexPetsCore

final class AppSettings {
  private enum Key {
    static let visiblePetCount = "visiblePetCount"
    static let selectedPetIDs = "selectedPetIDs"
    static let animationState = "animationState"
    static let scale = "scale"
    static let walksAround = "walksAround"
    static let followsSessions = "followsSessions"
    static let followsCursor = "followsCursor"
    static let sessionSoundNotifications = "sessionSoundNotifications"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var savedRouting: SessionRouting {
    get {
      guard let data = defaults.data(forKey: "savedRouting"),
        let routing = try? JSONDecoder().decode(SessionRouting.self, from: data)
      else { return SessionRouting() }
      return routing
    }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "savedRouting") }
  }

  var sessionAnimations: SessionAnimations {
    get {
      guard let data = defaults.data(forKey: "sessionAnimations"),
        let value = try? JSONDecoder().decode(SessionAnimations.self, from: data)
      else { return SessionAnimations() }
      return value
    }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "sessionAnimations") }
  }

  var petPreferences: [String: PetPreferences] {
    get {
      guard let data = defaults.data(forKey: "petPreferences") else { return [:] }
      return (try? JSONDecoder().decode([String: PetPreferences].self, from: data)) ?? [:]
    }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "petPreferences") }
  }

  var notifiedActivities: Set<AgentActivity> {
    get {
      let values =
        defaults.stringArray(forKey: "notifiedActivities")
        ?? [
          AgentActivity.completed.rawValue, AgentActivity.approval.rawValue,
          AgentActivity.failed.rawValue,
        ]
      return Set(values.compactMap(AgentActivity.init(rawValue:)))
    }
    set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: "notifiedActivities") }
  }

  var notificationCooldown: Double {
    get { defaults.object(forKey: "notificationCooldown") as? Double ?? 5 }
    set { defaults.set(min(max(newValue, 0), 60), forKey: "notificationCooldown") }
  }

  var orcaMessageNotifications: Bool {
    get { defaults.object(forKey: "orcaMessageNotifications") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "orcaMessageNotifications") }
  }

  var clickVolume: Float {
    get { defaults.object(forKey: "clickVolume") as? Float ?? 1 }
    set { defaults.set(min(max(newValue, 0), 1), forKey: "clickVolume") }
  }

  var soundsMuted: Bool {
    get { defaults.bool(forKey: "soundsMuted") }
    set { defaults.set(newValue, forKey: "soundsMuted") }
  }

  var alertVolume: Float {
    get { defaults.object(forKey: "alertVolume") as? Float ?? 1 }
    set { defaults.set(min(max(newValue, 0), 1), forKey: "alertVolume") }
  }

  var visiblePetCount: Int {
    get {
      let value = defaults.integer(forKey: Key.visiblePetCount)
      return value == 0 ? 2 : value
    }
    set {
      defaults.set(newValue, forKey: Key.visiblePetCount)
    }
  }

  var selectedPetIDs: [String]? {
    get {
      guard let ids = defaults.array(forKey: Key.selectedPetIDs) as? [String] else {
        return nil
      }

      return ids.uniqueNonEmptyValues
    }
    set {
      guard let newValue else {
        defaults.removeObject(forKey: Key.selectedPetIDs)
        return
      }

      defaults.set(newValue.uniqueNonEmptyValues, forKey: Key.selectedPetIDs)
    }
  }

  var animationState: AnimationState {
    get {
      guard let rawValue = defaults.string(forKey: Key.animationState),
        let state = AnimationState(rawValue: rawValue)
      else {
        return .idle
      }

      return state
    }
    set {
      defaults.set(newValue.rawValue, forKey: Key.animationState)
    }
  }

  var scale: Double {
    get {
      let value = defaults.double(forKey: Key.scale)
      return value == 0 ? 1 : value
    }
    set {
      defaults.set(newValue, forKey: Key.scale)
    }
  }

  var followsSessions: Bool {
    get { defaults.object(forKey: Key.followsSessions) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.followsSessions) }
  }

  var sessionSoundNotifications: Bool {
    get { defaults.object(forKey: Key.sessionSoundNotifications) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.sessionSoundNotifications) }
  }

  var followsCursor: Bool {
    get { defaults.object(forKey: Key.followsCursor) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.followsCursor) }
  }

  var walksAround: Bool {
    get {
      defaults.bool(forKey: Key.walksAround)
    }
    set {
      defaults.set(newValue, forKey: Key.walksAround)
    }
  }
}

extension Array where Element == String {
  fileprivate var uniqueNonEmptyValues: [String] {
    var seen = Set<String>()
    return compactMap { value in
      guard let trimmed = value.trimmedNonEmpty, !seen.contains(trimmed) else {
        return nil
      }

      seen.insert(trimmed)
      return trimmed
    }
  }
}
