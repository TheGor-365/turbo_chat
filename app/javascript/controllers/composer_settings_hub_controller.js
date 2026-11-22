import { Controller } from "@hotwired/stimulus"

// D3.1a: visible status/proxy for existing canonical controllers, not a new
// settings owner. Never use localStorage or PATCH from this controller.
// Reversible local switches delegate to their existing DOM controls.
// Consent/grants remain an explicit action in the canonical Room editor.
const SOURCES = {
  spelling: "[data-ai-draft-target='spellToggle']",
  consent: "[data-ai-draft-target='smartReplyToggle']",
  auto: ".sd-ai-room-switch--locked",
  contextReady: ".msg-form",
  translation: "[data-incoming-translation-target='toggle']",
  detailed: "[data-simple-chat-target='detailToggle']"
}

export default class extends Controller {
  connect() {
    this.room = this.element.closest(".msg-form")
    this.onChange = () => this.queueRender()
    this.onRefresh = () => this.queueRender()
    document.addEventListener("change", this.onChange, true)
    document.addEventListener("ai-draft:preferences-saved", this.onRefresh)
    this.observers = []
    for (const key of Object.keys(SOURCES)) {
      const node = this.source(key)
      if (!node) continue
      const observer = new MutationObserver(() => this.queueRender())
      observer.observe(node, {
        attributes: true, attributeFilter: ["aria-checked", "disabled", "data-enabled"]
      })
      this.observers.push(observer)
    }
    if (this.room) {
      const observer = new MutationObserver(() => this.queueRender())
      observer.observe(this.room, {attributes: true,
        attributeFilter: ["data-ai-room-context-ready"]})
      this.observers.push(observer)
    }
    this.queueRender()
    // The source controllers restore room/browser/consent asynchronously.
    this.initialRefresh = window.setTimeout(() => this.queueRender(), 180)
  }

  disconnect() {
    document.removeEventListener("change", this.onChange, true)
    document.removeEventListener("ai-draft:preferences-saved", this.onRefresh)
    this.observers?.forEach(observer => observer.disconnect())
    if (this.initialRefresh) window.clearTimeout(this.initialRefresh)
    if (this.renderFrame) window.cancelAnimationFrame(this.renderFrame)
  }

  source(key) {
    // The translation and display controllers may be mounted above the dock.
    if (key === "contextReady") return this.room
    return (this.room || document).querySelector(SOURCES[key]) ||
      document.querySelector(SOURCES[key])
  }

  queueRender() {
    if (this.renderFrame) return
    this.renderFrame = window.requestAnimationFrame(() => {
      this.renderFrame = null
      this.render()
    })
  }

  render() {
    this.element.querySelectorAll("[data-composer-setting]").forEach(button => {
      const key = button.dataset.composerSetting
      const node = this.source(key)
      const unavailable = !node || key === "auto"
      const enabled = !unavailable && (key === "contextReady"
        ? node.dataset.aiRoomContextReady === "true"
        : node.matches("input[type='checkbox']")
          ? node.checked === true
          : node.getAttribute("aria-checked") === "true")
      const draft = this.application.getControllerForElementAndIdentifier(
        this.room, "ai-draft")
      const unknownReadiness = key === "contextReady" &&
        node?.dataset.aiRoomContextReady == null
      const consentError = key === "consent" && draft?.contextStatusError === true
      const waiting = unknownReadiness || (key === "consent" && node?.disabled === true)
      const state = unavailable || consentError ? "locked" :
        waiting ? "pending" : enabled ? "on" : "off"
      button.dataset.state = state
      button.setAttribute("aria-pressed", String(enabled))
      const label = button.dataset.label || key
      const stateLabel = state === "locked" ? button.dataset.locked :
        state === "pending" ? button.dataset.pending :
          state === "on" ? button.dataset.on : button.dataset.off
      button.setAttribute("aria-label", label + ": " + stateLabel)
      button.title = label + ": " + stateLabel + (button.dataset.help ? " · " + button.dataset.help : "")
      const output = button.querySelector("[data-setting-value]")
      if (output) output.textContent = stateLabel
    })
  }

  activate(event) {
    event.preventDefault()
    const key = event.currentTarget.dataset.composerSetting
    const source = this.source(key)
    // No consent toggle from a tiny badge: authorizations need full context.
    // Auto Reply is explicitly unavailable; only reveal its explanation.
    if (["consent", "contextReady", "auto"].includes(key) || !source || source.disabled) {
      this.openRoomSettings(event.currentTarget, key)
      return
    }
    // Calls the existing canonical controller's click/change handler.
    source.click()
    this.queueRender()
  }

  openRoomSettings(trigger = null, key = null) {
    const draft = this.application.getControllerForElementAndIdentifier(
      this.room, "ai-draft")
    if (!draft) return
    draft.lastSheetTrigger = trigger
    draft.showSettings()
    const target = key === "auto"
      ? draft.settingsPanelTarget.querySelector(".sd-ai-room-option--auto")
      : key === "consent" || key === "contextReady"
        ? draft.settingsPanelTarget.querySelector(".sd-ai-room-option--smart")
        : null
    if (target) {
      const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
      target.scrollIntoView({block: "center", behavior: reduced ? "instant" : "smooth"})
      const button = target.querySelector("button[role='switch']")
      button?.focus({preventScroll: true})
    }
  }
}
