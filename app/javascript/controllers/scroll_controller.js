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
    window.requestAnimationFrame(() => this.scrollToBottom())
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
