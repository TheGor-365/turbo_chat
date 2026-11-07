import { Controller } from "@hotwired/stimulus"

// On phones the existing authorized sidebar slides over the conversation.
// It stays an ordinary page on /rooms and a two-pane rail on desktop.
export default class extends Controller {
  static targets = ["panel", "backdrop", "trigger", "closeButton"]
  static values = { conversation: Boolean }

  connect() {
    this.media = window.matchMedia("(max-width: 767px)")
    this.onMediaChange = () => this.reset()
    this.media.addEventListener?.("change", this.onMediaChange)
    this.opened = false
    this.reset()
  }

  disconnect() {
    this.media?.removeEventListener?.("change", this.onMediaChange)
    this.unlock()
    this.panelTarget.inert = false
  }

  get isDrawer() { return this.media.matches && this.conversationValue }

  reset() {
    this.opened = false
    this.element.classList.remove("sd-drawer-open")
    this.backdropTarget.tabIndex = -1
    this.backdropTarget.setAttribute("aria-hidden", "true")
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "false")
    this.panelTarget.inert = this.isDrawer
    this.panelTarget.setAttribute("aria-hidden", String(this.isDrawer))
    this.unlock()
  }

  open(event) {
    if (!this.isDrawer) return
    event?.preventDefault()
    this.opened = true
    this.element.classList.add("sd-drawer-open")
    this.panelTarget.inert = false
    this.panelTarget.setAttribute("aria-hidden", "false")
    this.backdropTarget.tabIndex = 0
    this.backdropTarget.setAttribute("aria-hidden", "false")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.lock()
    this.closeButtonTarget.focus()
  }

  close(event) {
    if (!this.isDrawer || !this.opened) return
    event?.preventDefault()
    this.opened = false
    this.triggerTarget.focus()
    this.element.classList.remove("sd-drawer-open")
    this.panelTarget.inert = true
    this.panelTarget.setAttribute("aria-hidden", "true")
    this.backdropTarget.tabIndex = -1
    this.backdropTarget.setAttribute("aria-hidden", "true")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.unlock()
  }

  escape(event) {
    if (this.opened && event.key === "Escape") this.close(event)
  }

  trapTab(event) {
    if (!this.opened || event.key !== "Tab") return
    const selectors = "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
    const items = [...this.panelTarget.querySelectorAll(selectors)].filter(
      (element) => element.getClientRects().length && !element.closest("[hidden]")
    )
    if (!items.length) return
    const first = items[0], last = items[items.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  lock() {
    this.prevOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
  }

  unlock() {
    if (this.prevOverflow !== undefined) {
      document.body.style.overflow = this.prevOverflow
      this.prevOverflow = undefined
    }
  }
}
