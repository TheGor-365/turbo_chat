import { Controller } from "@hotwired/stimulus"

// Progressive enhancement only: Rails validates compatibility and scope.
export default class extends Controller {
  static targets = ["operation", "preset", "details"]

  connect() {
    this.operationChanged()
  }

  operationChanged() {
    const operation = this.operationTarget.value
    const options = Array.from(this.presetTarget.options)

    options.forEach(option => {
      const compatible = option.dataset.operation === operation
      option.disabled = !compatible
      option.hidden = !compatible
    })

    const selected = this.presetTarget.selectedOptions[0]
    if (!selected || selected.disabled) {
      const first = options.find(option => !option.disabled)
      if (first) this.presetTarget.value = first.value
    }
    this.presetChanged()
  }

  presetChanged() {
    if (!this.hasDetailsTarget) return
    const option = this.presetTarget.selectedOptions[0]
    if (!option || option.disabled) {
      this.detailsTarget.textContent = "Choose a compatible built-in preset."
      return
    }
    this.detailsTarget.textContent =
      "v" + option.dataset.version + " · " + option.dataset.tone + " / " +
      option.dataset.style + " · manual context, up to " +
      option.dataset.limit + " messages · local preview only"
  }
}
