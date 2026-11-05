import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// One private room, one authenticated ActionCable subscription. No keystroke
// contents, draft text, or user-supplied identity ever leave the composer.
export default class extends Controller {
  static targets = ["body", "status"]
  static values = { roomId: Number, userId: Number }

  connect() {
    this.ready = false
    this.active = false
    this.lastSent = 0
    this.disconnected = false
    this.clearStatus()

    this.onVisibility = () => {
      if (document.visibilityState !== "visible") {
        // Switching tabs is not a deliberate cancellation of an unsent draft.
        // Let the existing 3-second idle timer send "stopped" so the other
        // participant can still observe the short-lived typing indication.
        // Their own 4.5-second TTL also protects against background throttling.
        this.clearStatus()
      }
    }
    document.addEventListener("visibilitychange", this.onVisibility)

    this.subscription = consumer.subscriptions.create(
      { channel: "RoomTypingChannel", room_id: this.roomIdValue },
      {
        connected: () => {
          this.ready = true
          this.element.dataset.typingIndicatorConnected = "true"
        },
        disconnected: () => {
          this.ready = false
          this.element.dataset.typingIndicatorConnected = "false"
          this.active = false
          this.clearStatus()
        },
        rejected: () => {
          this.ready = false
          this.element.dataset.typingIndicatorConnected = "false"
          this.clearStatus()
        },
        received: (data) => this.receive(data)
      }
    )
  }

  disconnect() {
    this.disconnected = true
    this.stopTyping()
    this.subscription?.unsubscribe()
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.clearTimeout(this.stopTimer)
    this.clearStatus()
    delete this.element.dataset.typingIndicatorConnected
  }

  changed() {
    if (this.disconnected || !this.ready || document.visibilityState !== "visible") return
    if (!this.bodyTarget.value.trim()) {
      this.stopTyping()
      return
    }

    const now = Date.now()
    if (!this.active || now - this.lastSent >= 2500) {
      this.subscription.perform("typing")
      this.lastSent = now
      this.active = true
    }

    window.clearTimeout(this.stopTimer)
    this.stopTimer = window.setTimeout(() => this.stopTyping(), 3000)
  }

  stopTyping() {
    window.clearTimeout(this.stopTimer)
    if (this.active && this.ready) this.subscription?.perform("stopped")
    this.active = false
  }

  receive(data) {
    if (this.disconnected ||
        Number(data?.room_id) !== this.roomIdValue ||
        Number(data?.user_id) === this.userIdValue) return

    if (data.type === "typing") {
      this.statusTarget.textContent = "Other participant is typing…"
      this.statusTarget.hidden = false
      window.clearTimeout(this.expiryTimer)
      // If a browser closes without a stop event, the indicator still expires.
      this.expiryTimer = window.setTimeout(() => this.clearStatus(), 4500)
    } else if (data.type === "stopped") {
      this.clearStatus()
    }
  }

  clearStatus() {
    window.clearTimeout(this.expiryTimer)
    if (this.hasStatusTarget) {
      this.statusTarget.hidden = true
      this.statusTarget.textContent = ""
    }
  }
}
