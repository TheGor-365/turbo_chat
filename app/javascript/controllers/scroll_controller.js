import { Controller } from "@hotwired/stimulus"

// Preserve the reader's position when older history is prepended. Follow
// genuinely new messages only if the user was already near the bottom.
export default class extends Controller {
  connect() {
    this.followBottom = true
    this.onScroll = () => {
      this.followBottom = this.nearBottom()
    }
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
    this.observer = new MutationObserver(() => {
      if (this.followBottom) this.scrollToBottom()
    })
    this.observer.observe(this.element, { childList: true, subtree: true })
    window.requestAnimationFrame(() => {
      // A result URL uses a real message anchor. Center that exact message
      // instead of the normal live-chat auto-follow position.
      const anchor = window.location.hash.slice(1)
      const target = /^message_\d+$/.test(anchor) ? document.getElementById(anchor) : null
      if (target && this.element.contains(target)) {
        this.followBottom = false
        target.scrollIntoView({ block: "center", inline: "nearest" })
      } else {
        this.scrollToBottom()
      }
    })
  }

  disconnect() {
    this.observer?.disconnect()
    this.element.removeEventListener("scroll", this.onScroll)
  }

  nearBottom() {
    return this.element.scrollHeight - this.element.scrollTop - this.element.clientHeight < 120
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight - this.element.clientHeight
  }
}
