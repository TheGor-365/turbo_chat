import { Controller } from "@hotwired/stimulus"

// Read-only preference indicators. No provider or consent actions.
export default class extends Controller {
  static targets = ["indicator"]
  static values = { url: String, messages: Object, description: String }

  connect() {
    this.active = true
    this.onFocus = () => this.refresh()
    this.onVisibility = () => {
      if (document.visibilityState === "visible") this.refresh()
      else {
        this.request?.abort()
        this.clear()
      }
    }
    this.onMembership = () => {
      this.clear()
      this.refresh()
    }
    window.addEventListener("focus", this.onFocus)
    document.addEventListener("visibilitychange", this.onVisibility)
    document.addEventListener("room-membership:changed", this.onMembership)
    this.timer = window.setInterval(() => this.refresh(), 15000)
    this.refresh()
  }

  disconnect() {
    this.active = false
    this.request?.abort()
    window.clearInterval(this.timer)
    window.removeEventListener("focus", this.onFocus)
    document.removeEventListener("visibilitychange", this.onVisibility)
    document.removeEventListener("room-membership:changed", this.onMembership)
    this.clear()
  }

  indicatorTargetConnected(indicator) {
    // Membership markup can be replaced independently. Never reuse a stale
    // snapshot for newly inserted rows, even if the same user ID reappears.
    this.render(indicator, "unknown")
    if (this.active) this.refresh()
  }

  clear() {
    this.indicatorTargets.forEach(indicator => this.render(indicator, "unknown"))
  }

  render(indicator, state) {
    indicator.dataset.aiMemberState = state
    indicator.textContent = this.messagesValue[state] || this.messagesValue.unknown || "—"
  }

  async refresh() {
    if (!this.active || document.visibilityState !== "visible" || !this.hasUrlValue) return
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    try {
      const response = await fetch(this.urlValue, {
        credentials: "same-origin", cache: "no-store", signal: request.signal,
        headers: { Accept: "application/json" }
      })
      if (!response.ok || response.redirected) throw new Error("Unavailable")
      const payload = await response.json()
      if (!Array.isArray(payload.members)) throw new Error("Invalid snapshot")
      const states = new Map()
      for (const member of payload.members) {
        if (!Number.isSafeInteger(member.user_id) || member.user_id < 1 ||
            typeof member.enabled !== "boolean" || typeof member.configured !== "boolean" ||
            states.has(String(member.user_id))) throw new Error("Invalid member")
        states.set(String(member.user_id), member.enabled ? "on" : "off")
      }
      if (!this.active || request.signal.aborted || this.request !== request) return
      this.indicatorTargets.forEach(indicator =>
        this.render(indicator, states.get(indicator.dataset.aiMemberUserId) || "unknown"))
    } catch (error) {
      if (this.active && !request.signal.aborted && this.request === request) this.clear()
    } finally {
      if (this.request === request) this.request = null
    }
  }
}
