import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "turbo-chat:signal-deck-theme"
const MODES = ["dark", "light", "system"]
const NEXT = { dark: "light", light: "system", system: "dark" }
const DESCRIPTIONS = { dark: "Dark", light: "Light", system: "System" }

// Client-local appearance preference; never sent to a server or used for ACL.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.schemeQuery = window.matchMedia?.("(prefers-color-scheme: dark)") || null
    this.preference = this.readPreference()
    this.onSchemeChanged = () => { if (this.preference === "system") this.apply() }
    this.schemeQuery?.addEventListener?.("change", this.onSchemeChanged)
    this.apply()
  }

  disconnect() {
    this.schemeQuery?.removeEventListener?.("change", this.onSchemeChanged)
  }

  toggleTargetConnected(element) {
    if (this.preference) this.updateToggle(element)
  }

  cycle(event) {
    event?.preventDefault()
    this.preference = NEXT[this.preference] || "dark"
    try { window.localStorage.setItem(STORAGE_KEY, this.preference) } catch (_) { /* private mode */ }
    this.apply()
  }

  readPreference() {
    let saved = null
    try { saved = window.localStorage.getItem(STORAGE_KEY) } catch (_) { /* private mode */ }
    return MODES.includes(saved) ? saved : "dark"
  }

  apply() {
    this.element.dataset.theme = this.preference
    this.element.style.colorScheme =
      this.preference === "system" ? (this.schemeQuery?.matches ? "dark" : "light") : this.preference
    this.toggleTargets.forEach((element) => this.updateToggle(element))
  }

  updateToggle(element) {
    const current = DESCRIPTIONS[this.preference]
    const next = DESCRIPTIONS[NEXT[this.preference]]
    element.setAttribute("aria-label", `Theme: ${current}. Switch to ${next}`)
    element.setAttribute("title", `Theme: ${current} · switch to ${next}`)
    element.dataset.themeCurrent = this.preference
  }
}
