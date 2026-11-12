import { Controller } from "@hotwired/stimulus"

// When Turbo follows a navigation/form and the server sends tagged HTML error,
// keep the current room/editor on screen. The native dialog handles Escape,
// focus containment and modal accessibility.
const copy = {
  ai_consent_paused: ["AI access paused", "A room participant may have changed AI permissions. Recheck room-wide consent before reopening this work."],
  room_access_unavailable: ["Conversation unavailable", "You may no longer have access to this conversation."],
  http_400: ["Request unavailable", "Check the request and try again."],
  http_401: ["Sign-in required", "Sign in to continue to your conversations."],
  http_403: ["Access unavailable", "You may no longer have permission to view this content."],
  http_404: ["Content unavailable", "The item may be deleted or inaccessible to your account."],
  http_406: ["Format unavailable", "This format cannot be opened here."],
  http_409: ["Changes need review", "Check the latest version before retrying."],
  http_410: ["Content no longer available", "This item is no longer accessible."],
  http_422: ["Action not completed", "Check your changes and try again."],
  http_429: ["Too many requests", "You've reached a temporary limit. Please try again shortly."],
  http_503: ["Service temporarily unavailable", "This feature is unavailable right now."]
}

export default class extends Controller {
  static targets = ["dialog", "title", "message", "status", "closeButton"]

  intercept(event) {
    const response = event.detail?.fetchResponse?.response
    if (!response || response.ok) return

    const key = response.headers.get("X-Relay-Error-State")
    const message = copy[key]
    if (!message || !this.hasDialogTarget) return

    event.preventDefault()
    this.previousFocus = document.activeElement
    this.titleTarget.textContent = message[0]
    this.messageTarget.textContent = message[1]
    this.statusTarget.textContent = "Request not completed · HTTP " + response.status

    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    this.closeButtonTarget.focus()
  }

  close(event) {
    event?.preventDefault()
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  closed() {
    if (this.previousFocus?.isConnected) this.previousFocus.focus()
    this.previousFocus = null
  }

  disconnect() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }
}
