import { Controller } from "@hotwired/stimulus"

// Prepared for P3.5a. Only explicit clicks write the personal preference.
// The server owns the revision and current value; never optimistically flip it.
export default class extends Controller {
  static targets = ["toggle", "state", "feedback"]
  static values = { url: String, messages: Object }

  connect() {
    this.connected = true
    this.snapshot = null
    this.busy = false
    this.refresh()
  }

  disconnect() {
    this.connected = false
    this.pending?.abort()
  }

  async refresh() {
    if (this.busy) return
    await this.request(false)
  }

  async toggle() {
    if (this.busy || !this.snapshot) return
    await this.request(true)
  }

  async request(write) {
    this.busy = true
    this.toggleTarget.disabled = true
    const controller = new AbortController()
    this.pending = controller
    try {
      const headers = { Accept: "application/json" }
      const options = { credentials: "same-origin", cache: "no-store",
        signal: controller.signal, headers }
      if (write) {
        const csrf = document.querySelector('meta[name="csrf-token"]')?.content
        if (!csrf) throw new Error("Missing CSRF token")
        options.method = "PATCH"
        headers["Content-Type"] = "application/json"
        headers["X-CSRF-Token"] = csrf
        options.body = JSON.stringify({ enabled: !this.snapshot.enabled,
          expected_revision: this.snapshot.revision })
      }
      let response = await fetch(this.urlValue, options)
      let message = write ? "saved" : ""
      if (write && response.status === 409) {
        // Read the winner, do not retry a stale write automatically.
        response = await fetch(this.urlValue, {
          credentials: "same-origin", cache: "no-store",
          headers: { Accept: "application/json" }, signal: controller.signal
        })
        message = "conflict"
      }
      if (!response.ok || response.redirected) throw new Error("Setting unavailable")
      const snapshot = await response.json()
      if (typeof snapshot.enabled !== "boolean" ||
          typeof snapshot.configured !== "boolean" ||
          !Number.isSafeInteger(snapshot.revision) || snapshot.revision < 0 ||
          snapshot.configured !== (snapshot.revision > 0)) {
        throw new Error("Invalid setting response")
      }
      if (!this.connected || this.pending !== controller) return
      this.snapshot = snapshot
      this.stateTarget.textContent = this.messagesValue[snapshot.enabled ? "on" : "off"]
      this.toggleTarget.textContent = this.messagesValue[snapshot.enabled ? "disable" : "enable"]
      this.feedbackTarget.textContent = message ? this.messagesValue[message] : ""
    } catch (error) {
      if (!this.connected || this.pending !== controller) return
      // A lost response may conceal a successful write. Do not show a stale
      // setting as authoritative, or allow another write without a fresh GET.
      this.snapshot = null
      this.stateTarget.textContent = this.messagesValue.unknown
      this.toggleTarget.textContent = this.messagesValue.enable
      this.feedbackTarget.textContent = this.messagesValue.unavailable
    } finally {
      if (this.connected && this.pending === controller) {
        this.busy = false
        this.toggleTarget.disabled = !this.snapshot
      }
    }
  }
}
