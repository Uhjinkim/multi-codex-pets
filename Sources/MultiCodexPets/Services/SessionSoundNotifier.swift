import AVFoundation
import Foundation

/// Serializes notifications so several assigned pets do not speak over each other.
final class SessionSoundNotifier: NSObject, AVAudioPlayerDelegate {
  private var pending: [(petID: String, sounds: [URL])] = []
  private var player: AVAudioPlayer?
  private var playingPetID: String?
  var volume: Float = 1 { didSet { player?.volume = volume } }

  func enqueue(petID: String, sounds: [URL]) {
    guard !sounds.isEmpty else { return }
    pending.removeAll { $0.petID == petID }
    pending.append((petID, sounds))
    playNext()
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
          candidate.volume = volume
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
