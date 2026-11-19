import { Controller } from "@hotwired/stimulus"

// Native dialog gives keyboard Escape and focus containment; source URLs
// are generated server-side by the existing membership-scoped route.
export default class extends Controller {
  static targets = ["dialog", "openButton", "closeButton"]

  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    this.closeButtonTarget.focus()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  closed() {
    if (this.openButtonTarget.isConnected) this.openButtonTarget.focus()
  }

  disconnect() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }
}
