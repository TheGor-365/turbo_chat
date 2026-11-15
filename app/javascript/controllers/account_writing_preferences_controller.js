import { Controller } from "@hotwired/stimulus"

// Visual account profile selection is not a provider action. The server
// separately validates and persists a complete allowlisted snapshot.
export default class extends Controller {
  static targets = ["profile", "style", "tone"]

  profileChanged() {
    const selected = this.profileTarget.selectedOptions[0]
    if (!selected?.value) return
    const style = selected.dataset.style
    const tone = selected.dataset.tone
    if (!Array.from(this.styleTarget.options).some(option => option.value === style) ||
        !Array.from(this.toneTarget.options).some(option => option.value === tone)) return
    this.styleTarget.value = style
    this.toneTarget.value = tone
    this.styleTarget.dispatchEvent(new Event("ui-select:sync"))
    this.toneTarget.dispatchEvent(new Event("ui-select:sync"))
  }

  styleChanged() {
    // Explicit custom style is a custom account profile, not an invalid
    // preset/profile pair or unreviewed permission grant.
    this.profileTarget.value = ""
    this.profileTarget.dispatchEvent(new Event("ui-select:sync"))
  }
}
