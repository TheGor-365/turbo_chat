import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "turbo-chat:signal-deck-theme"
const MODES = ["dark", "light", "system"]
const NEXT = { dark: "light", light: "system", system: "dark" }

// Client-local appearance preference; never sent to a server or used for ACL.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.schemeQuery = window.matchMedia?.("(prefers-color-scheme: dark)") || null
    this.preference = this.readPreference()
    this.onSchemeChanged = () => { if (this.preference === "system") this.apply() }
    this.schemeQuery?.addEventListener?.("change", this.onSchemeChanged)
    // Turbo keeps the <html> element across localized body navigations.
    this.onTurboLoad = () => {
      this.element.lang = document.body?.dataset.uiLocale || this.element.lang
      this.apply()
    }
    document.addEventListener("turbo:load", this.onTurboLoad)
    this.onTurboLoad()
  }

  disconnect() {
    this.schemeQuery?.removeEventListener?.("change", this.onSchemeChanged)
    document.removeEventListener("turbo:load", this.onTurboLoad)
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
    let labels = {}
    try { labels = JSON.parse(document.body?.dataset.uiThemeLabels || "{}") } catch (_) { /* retain old copy */ }
    const localized = labels[this.preference]
    if (localized?.aria) element.setAttribute("aria-label", localized.aria)
    if (localized?.title) element.setAttribute("title", localized.title)
    element.dataset.themeCurrent = this.preference
  }
}
