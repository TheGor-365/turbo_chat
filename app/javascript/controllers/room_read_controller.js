import { Controller } from "@hotwired/stimulus"

// A conversation is read only when this visible tab is near the bottom.
// The exact rendered message ID, not the latest database message, is sent
// so messages arriving during page load cannot be silently marked read.
export default class extends Controller {
  static values = { url: String, roomId: Number, historyFocus: Boolean }

  connect() {
    this.scroller = this.element.querySelector("#messages")
    this.messages = this.element.querySelector("#messages-container")
    if (!this.scroller || !this.messages || !this.hasUrlValue) return

    this.stopped = false
    this.lastAcknowledged = 0
    this.pending = false
    this.onScroll = () => this.schedule()
    this.onVisibility = () => this.schedule()
    this.scroller.addEventListener("scroll", this.onScroll, { passive: true })
    document.addEventListener("visibilitychange", this.onVisibility)
    this.observer = new MutationObserver(() => this.schedule())
    this.observer.observe(this.messages, { childList: true })
    this.schedule()
  }

  disconnect() {
    this.stopped = true
    window.clearTimeout(this.timer)
    this.observer?.disconnect()
    this.scroller?.removeEventListener("scroll", this.onScroll)
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  schedule() {
    if (this.stopped) return
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => this.acknowledgeVisible(), 300)
  }

  highestRenderedId() {
    let maximum = 0
    this.messages.querySelectorAll(':scope > [id^="message_"]').forEach((node) => {
      const id = Number(node.id.slice(8))
      if (Number.isSafeInteger(id) && id > maximum) maximum = id
    })
    return maximum
  }

  nearBottom() {
    return this.scroller.scrollHeight - this.scroller.scrollTop - this.scroller.clientHeight <= 100
  }

  async acknowledgeVisible() {
    // A bounded search-result window is not the live end of the conversation.
    // Reading a historical hit must not clear newer unread messages.
    if (this.historyFocusValue || this.stopped || this.pending || document.visibilityState !== "visible" || !this.nearBottom()) return
    const id = this.highestRenderedId()
    if (!id || id <= this.lastAcknowledged) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) return

    this.pending = true
    let acknowledged = false
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        credentials: "same-origin",
        cache: "no-store",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": token
        },
        body: JSON.stringify({ last_read_message_id: id })
      })
      if (!response.ok) return
      this.lastAcknowledged = id
      acknowledged = true
      if (!this.stopped) {
        document.querySelectorAll('[data-unread-room-id="' + this.roomIdValue + '"]').forEach((badge) => badge.remove())
      }
    } catch (_) {
      // Network failures leave the cursor unchanged. A later scroll,
      // visibility change or message append will safely retry.
    } finally {
      this.pending = false
      if (acknowledged && !this.stopped && this.highestRenderedId() > this.lastAcknowledged) this.schedule()
    }
  }
}
