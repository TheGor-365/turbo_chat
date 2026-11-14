import { Controller } from "@hotwired/stimulus"

// UI-only progressive disclosure. This never changes the AI consent, provider,
// server permissions, chat data, or which actions the account is allowed to run.
export default class extends Controller {
  static targets = ["detailToggle"]
  static values = { user: String }

  connect() {
    this.key = "relay.chat.display.v1." + this.userValue
    let saved = null
    try { saved = localStorage.getItem(this.key) } catch (_) { /* private mode */ }
    this.detailed = saved === "detailed"
    this.update()
  }

  change() {
    this.detailed = this.detailToggleTarget.checked
    this.update()
    try {
      localStorage.setItem(this.key, this.detailed ? "detailed" : "simple")
    } catch (_) { /* Device policy may block local storage. UI still works. */ }
  }

  update() {
    this.element.dataset.chatUiMode = this.detailed ? "detailed" : "simple"
    if (this.hasDetailToggleTarget) this.detailToggleTarget.checked = this.detailed
  }
}
