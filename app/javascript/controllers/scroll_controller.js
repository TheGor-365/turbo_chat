import { Controller } from "@hotwired/stimulus"

// Scroll only inside the chat history pane. Native fragment navigation and
// element.scrollIntoView() can unexpectedly scroll the entire page/sidebar.
export default class extends Controller {
  static targets = ["scroller", "latestButton"]
  static values = { focusMessageId: Number, latestUrl: String }

  connect() {
    this.scroller = this.scrollerTarget
    this.focused = this.focusMessageIdValue > 0
    this.followBottom = !this.focused
    this.animating = false
    this.onScroll = () => {
      if (!this.animating) this.followBottom = !this.focused && this.nearBottom()
      this.updateJumpButton()
    }
    this.scroller.addEventListener("scroll", this.onScroll, { passive: true })

    this.observer = new MutationObserver(() => {
      if (this.followBottom && !this.focused) this.scrollToBottom()
      this.updateJumpButton()
    })
    this.observer.observe(this.scroller, { childList: true, subtree: true })

    this.onKeydown = (event) => {
      if (!this.focused || event.key !== "Escape" || event.defaultPrevented) return
      if (event.target?.closest?.("input, textarea, select, [contenteditable='true']")) return
      event.preventDefault()
      window.location.assign(this.latestUrlValue)
    }
    document.addEventListener("keydown", this.onKeydown)

    // Let layout and the media/composer widths settle before calculating
    // the inner scroll offset. No top-level element.scrollIntoView().
    this.frame = window.requestAnimationFrame(() => {
      this.frame = window.requestAnimationFrame(() => {
        if (this.focused) {
          // Legacy bookmarks may still contain the old #message_N fragment.
          // Clear it: the authorized ?focus=N parameter is now canonical.
          if (window.location.hash) {
            window.history.replaceState(window.history.state, "",
              window.location.pathname + window.location.search)
            window.scrollTo(0, 0)
          }
          this.focusOnMessage()
        } else {
          this.scrollToBottom()
        }
        this.updateJumpButton()
      })
    })
  }

  disconnect() {
    this.observer?.disconnect()
    this.scroller?.removeEventListener("scroll", this.onScroll)
    document.removeEventListener("keydown", this.onKeydown)
    window.cancelAnimationFrame(this.frame)
    window.clearTimeout(this.animationTimer)
  }

  nearBottom() {
    return this.scroller.scrollHeight - this.scroller.scrollTop -
      this.scroller.clientHeight < 120
  }

  reducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches || false
  }

  focusOnMessage() {
    const target = this.scroller.querySelector("#message_" + this.focusMessageIdValue)
    if (!target) return

    target.classList.add("message-focused")
    // The difference of bounding rectangles is relative to the overflow
    // scroller, not to document.body. Clamp the destination to valid bounds.
    const pane = this.scroller.getBoundingClientRect()
    const message = target.getBoundingClientRect()
    const centered = this.scroller.scrollTop + message.top - pane.top -
      (this.scroller.clientHeight - message.height) / 2
    const max = Math.max(0, this.scroller.scrollHeight - this.scroller.clientHeight)
    this.scroller.scrollTo({
      top: Math.max(0, Math.min(max, centered)),
      behavior: this.reducedMotion() ? "instant" : "smooth"
    })
  }

  scrollToBottom() {
    this.scroller.scrollTop = this.scroller.scrollHeight
  }

  jumpToLatest(event) {
    // An old-message window does not contain the newest messages:
    // follow the authorized room URL rather than pretending to scroll there.
    if (this.focused) return

    event.preventDefault()
    this.followBottom = true
    this.animating = true
    this.scroller.scrollTo({
      top: this.scroller.scrollHeight,
      behavior: this.reducedMotion() ? "instant" : "smooth"
    })
    window.clearTimeout(this.animationTimer)
    this.animationTimer = window.setTimeout(() => {
      this.animating = false
      this.followBottom = this.nearBottom()
      this.updateJumpButton()
    }, this.reducedMotion() ? 0 : 700)
  }

  updateJumpButton() {
    if (!this.hasLatestButtonTarget) return
    this.latestButtonTarget.hidden = !this.focused && this.nearBottom()
  }
}
