import { Controller } from "@hotwired/stimulus"

// Public room discovery remains server-authoritative (Turbo Stream action).
// This controller owns only progressive disclosure, keyboard flow and debounce.
export default class extends Controller {
  static targets = ["panel", "input", "form", "results", "hint"]

  connect() {
    this.timer = null
    // People and room discovery are now both always-visible search fields.
    this.panelTarget.hidden = false
    this.hintTarget.hidden = this.inputTarget.value.trim().length !== 1
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  close(event) {
    event?.preventDefault()
    window.clearTimeout(this.timer)
    this.inputTarget.value = ""
    this.resultsTarget.replaceChildren()
    this.hintTarget.hidden = true
    this.inputTarget.focus()
  }

  changed() {
    window.clearTimeout(this.timer)
    const value = this.inputTarget.value.trim()
    if (value.length < 2) {
      this.resultsTarget.replaceChildren()
      this.hintTarget.hidden = value.length === 0
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
