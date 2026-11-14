import { Controller } from "@hotwired/stimulus"

// Progressive enhancement only. The server independently enforces the same
// eight-message bound; disabling a checkbox does not grant AI consent.
export default class extends Controller {
  static targets = ["checkbox", "counter"]
  static values = { max: { type: Number, default: 8 } }

  connect() {
    this.changed()
  }

  changed() {
    const checked = this.checkboxTargets.filter(box => box.checked).length
    this.checkboxTargets.forEach(box => {
      box.disabled = !box.checked && checked >= this.maxValue
    })
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${checked} / ${this.maxValue} selected`
    }
  }
}
