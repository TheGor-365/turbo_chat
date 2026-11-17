import { Controller } from "@hotwired/stimulus"

// Progressive enhancement only: Rails validates compatibility and scope.
export default class extends Controller {
  static targets = ["operation", "preset", "details"]
  static values = { copy: Object }

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
    this.presetTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.presetChanged()
  }

  presetChanged() {
    if (!this.hasDetailsTarget) return
    const option = this.presetTarget.selectedOptions[0]
    if (!option || option.disabled) {
      this.detailsTarget.textContent = this.copyValue?.incompatible || "Choose a compatible built-in preset."
      return
    }
    const template = this.copyValue?.details || "v{version} · {tone} / {style} · manual context, up to {max} messages · local preview only"
    this.detailsTarget.textContent = template
      .replace("{version}", option.dataset.version || "")
      .replace("{tone}", option.dataset.tone || "")
      .replace("{style}", option.dataset.style || "")
      .replace("{max}", option.dataset.limit || "")
  }
}
