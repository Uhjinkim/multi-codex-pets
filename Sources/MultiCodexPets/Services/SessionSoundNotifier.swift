import AVFoundation
import Foundation

/// Serializes notifications so several assigned pets do not speak over each other.
final class SessionSoundNotifier: NSObject, AVAudioPlayerDelegate {
  private var pending: [(petID: String, sounds: [URL], volume: Float, notificationKey: String?)] = []
  private var player: AVAudioPlayer?
  private var playingPetID: String?
  private var playingVolume: Float = 1
  var volume: Float = 1 { didSet { player?.volume = volume * playingVolume } }

  func enqueue(petID: String, sounds: [URL], petVolume: Float = 1, notificationKey: String? = nil) {
    guard !sounds.isEmpty, petVolume > 0, volume > 0 else { return }
    pending.removeAll { $0.petID == petID && $0.notificationKey == notificationKey }
    pending.append((petID, sounds, petVolume, notificationKey))
    playNext()
  }

  func setPetVolume(_ value: Float, petID: String) {
    guard value > 0 else { cancel(petID: petID); return }
    for index in pending.indices where pending[index].petID == petID { pending[index].volume = value }
    if playingPetID == petID {
      playingVolume = value
      player?.volume = volume * playingVolume
    }
  }

  func stop() {
    pending.removeAll()
    player?.stop()
    player = nil
    playingPetID = nil
  }

  func cancel(petID: String) {
    pending.removeAll { $0.petID == petID }
    if playingPetID == petID {
      player?.stop()
      player = nil
      playingPetID = nil
      playNext()
    }
  }

  private func playNext() {
    guard player == nil else { return }
    while !pending.isEmpty {
      let next = pending.removeFirst()
      for url in next.sounds.shuffled() {
        do {
          let candidate = try AVAudioPlayer(contentsOf: url)
          candidate.delegate = self
          playingVolume = next.volume
          candidate.volume = volume * playingVolume
          if candidate.play() {
            player = candidate
            playingPetID = next.petID
            return
          }
        } catch { continue }
      }
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard self.player === player else { return }
    self.player = nil
    playingPetID = nil
    playNext()
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard self.player === player else { return }
    self.player = nil
    playingPetID = nil
    playNext()
  }
}
