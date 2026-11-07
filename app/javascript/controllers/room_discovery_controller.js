import { Controller } from "@hotwired/stimulus"

// Public room discovery remains server-authoritative (Turbo Stream action).
// This controller owns only progressive disclosure, keyboard flow and debounce.
export default class extends Controller {
  static targets = ["trigger", "panel", "input", "form", "results", "hint"]

  connect() {
    this.timer = null
    const expanded = this.inputTarget.value.trim().length > 0
    this.panelTarget.hidden = !expanded
    this.triggerTarget.setAttribute("aria-expanded", String(expanded))
    this.hintTarget.hidden = expanded
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  open(event) {
    event?.preventDefault()
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.inputTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    window.clearTimeout(this.timer)
    this.inputTarget.value = ""
    this.resultsTarget.replaceChildren()
    this.hintTarget.hidden = false
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.focus()
  }

  changed() {
    window.clearTimeout(this.timer)
    const value = this.inputTarget.value.trim()
    if (value.length < 2) {
      this.resultsTarget.replaceChildren()
      this.hintTarget.hidden = false
      return
    }
    this.hintTarget.hidden = true
    this.timer = window.setTimeout(() => this.formTarget.requestSubmit(), 450)
  }

  submit(event) {
    // The form's Turbo Stream response is rendered by Turbo. No user HTML
    // interpolation is necessary; avoid submitting incomplete searches.
    if (this.inputTarget.value.trim().length < 2) event.preventDefault()
  }
}
