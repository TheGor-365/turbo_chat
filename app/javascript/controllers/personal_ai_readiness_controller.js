import { Controller } from "@hotwired/stimulus"

// Read-only UI gate. Never reconstruct endpoints omitted by the server,
// reload a draft, cancel a signed candidate, or authorize provider spending.
export default class extends Controller {
  static targets = ["notice", "label", "reloadHint"]
  static values = { url: String, initialEnabled: Boolean, labels: Object }

  connect() {
    this.active = true
    this.onFocus = () => this.refresh()
    this.onVisibility = () => {
      if (document.visibilityState === "visible") this.refresh()
      else this.request?.abort()
    }
    window.addEventListener("focus", this.onFocus)
    document.addEventListener("visibilitychange", this.onVisibility)
    this.timer = window.setInterval(() => this.refresh(), 15000)
    this.refresh()
  }

  disconnect() {
    this.active = false
    this.request?.abort()
    window.clearInterval(this.timer)
    window.removeEventListener("focus", this.onFocus)
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  async refresh() {
    if (!this.active || document.visibilityState !== "visible") return
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    try {
      const response = await fetch(this.urlValue, {
        credentials: "same-origin", cache: "no-store", signal: request.signal,
        headers: { Accept: "application/json" }
      })
      if (!response.ok || response.redirected) throw new Error("Unavailable")
      const data = await response.json()
      if (typeof data.enabled !== "boolean" || typeof data.configured !== "boolean" ||
          !Number.isSafeInteger(data.revision) || data.revision < 0 ||
          data.configured !== (data.revision > 0)) throw new Error("Invalid snapshot")
      if (!this.active || request.signal.aborted || this.request !== request) return
      this.render(data.enabled ? "true" : "false")
    } catch (_) {
      if (this.active && !request.signal.aborted && this.request === request) this.render("unknown")
    } finally {
      if (this.request === request) this.request = null
    }
  }

  render(state) {
    const reloadNeeded = state === "true" && !this.initialEnabledValue
    const effective = reloadNeeded ? "reload" : state
    this.element.dataset.personalAiEnabled = effective
    this.noticeTarget.hidden = effective === "true"
    this.labelTarget.textContent = this.labelsValue[state === "true" ? "on" : state === "false" ? "off" : "unknown"]
    this.reloadHintTarget.hidden = !reloadNeeded
    for (const [identifier, method] of [["ai-draft", "updateButtons"],
      ["quick-beautify", "refresh"], ["ai-answer-entry", "render"]]) {
      const controller = this.application.getControllerForElementAndIdentifier(this.element, identifier)
      controller?.[method]?.()
    }
  }
}
