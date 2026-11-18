import { Controller } from "@hotwired/stimulus"

// A Turbo-replaced message gets a fresh controller. Document listeners are
// installed only for an open tray and removed on close/disconnect.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.outsideHandler = this.outsidePointerDown.bind(this)
    this.escapeHandler = this.onDocumentKeydown.bind(this)
  }

  disconnect() {
    this.removeDocumentListeners()
  }

  toggle() {
    if (!this.panelTarget.hidden) return this.close({ restoreFocus: true })

    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("pointerdown", this.outsideHandler, true)
    document.addEventListener("keydown", this.escapeHandler, true)
  }

  close({ restoreFocus = false } = {}) {
    if (this.panelTarget.hidden) return
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.element.querySelectorAll(".reaction-picker[open]").forEach(picker => {
      picker.open = false
    })
    this.removeDocumentListeners()
    if (restoreFocus && this.triggerTarget.isConnected) this.triggerTarget.focus()
  }

  actionSelected(event) {
    const control = event.target.closest("button, a, summary")
    if (!control || !this.panelTarget.contains(control) || control.matches("summary")) return
    // The established room-wide reply listener focuses the composer after
    // bubbling; do not steal its focus here.
    this.close()
  }

  outsidePointerDown(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  onDocumentKeydown(event) {
    if (event.key !== "Escape") return
    event.preventDefault()
    event.stopPropagation()
    this.close({ restoreFocus: true })
  }

  removeDocumentListeners() {
    document.removeEventListener("pointerdown", this.outsideHandler, true)
    document.removeEventListener("keydown", this.escapeHandler, true)
  }
}
