import { Controller } from "@hotwired/stimulus"

// A neutral, honest cover remains visible until the private poster loads.
// The native video element and its private HTTP Range endpoint own playback.
export default class extends Controller {
  static targets = ["video", "cover", "poster", "fallback", "status"]

  posterLoaded() {
    if (!this.posterTarget.naturalWidth) return this.posterError()
    this.posterTarget.hidden = false
    this.fallbackTarget.hidden = true
  }

  posterError() {
    this.posterTarget.hidden = true
    this.fallbackTarget.hidden = false
    this.fallbackTarget.textContent = "Preview unavailable"
  }

  play() {
    // Reveals built-in controls even if the codec cannot play.
    this.coverTarget.hidden = true
    const attempt = this.videoTarget.play()
    if (attempt && typeof attempt.catch === "function") {
      attempt.catch(() => {
        this.statusTarget.textContent = "Playback unavailable. Try the video controls."
      })
    }
  }

  playing() {
    this.coverTarget.hidden = true
    this.statusTarget.textContent = "Playing video"
  }
}
