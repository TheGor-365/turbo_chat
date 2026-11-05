import { Controller } from "@hotwired/stimulus"

// Live, room-scoped search. The authenticated Rails endpoint remains the
// authority for room membership and result links. Drafts never leave this UI.
export default class extends Controller {
  static targets = ["input", "results", "closeButton"]
  static values = { url: String }

  connect() {
    this.sequence = 0
    this.pending = null
    this.timer = null
    this.resultsTarget.hidden = true
    this.closeButtonTarget.hidden = true
    if (this.inputTarget.value.trim().length >= 2) this.changed()
  }

  disconnect() {
    window.clearTimeout(this.timer)
    this.pending?.abort()
  }

  changed() {
    const query = this.inputTarget.value.trim()
    const sequence = ++this.sequence
    window.clearTimeout(this.timer)
    this.pending?.abort()
    this.pending = null

    if (query.length < 2) {
      this.hideResults()
      return
    }

    this.resultsTarget.hidden = false
    this.closeButtonTarget.hidden = false
    this.showFeedback("Searching…")
    // One request after the user pauses, not a request for every keystroke.
    this.timer = window.setTimeout(() => this.search(query, sequence), 500)
  }

  submit(event) {
    event.preventDefault()
    this.changed()
  }

  clear() {
    this.sequence++
    window.clearTimeout(this.timer)
    this.pending?.abort()
    this.pending = null
    this.inputTarget.value = ""
    this.hideResults()
    this.inputTarget.focus()
  }

  hideResults() {
    this.resultsTarget.replaceChildren()
    this.resultsTarget.hidden = true
    this.closeButtonTarget.hidden = true
  }

  showFeedback(message) {
    const line = document.createElement("p")
    line.className = "message-search-empty"
    line.setAttribute("role", "status")
    line.textContent = message
    this.resultsTarget.replaceChildren(line)
  }

  async search(query, sequence) {
    const controller = new AbortController()
    this.pending = controller
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)

    try {
      const response = await fetch(url, {
        credentials: "same-origin",
        cache: "no-store",
        signal: controller.signal,
        headers: {
          Accept: "text/html",
          "Turbo-Frame": "message_search_results"
        }
      })
      if (sequence !== this.sequence || controller.signal.aborted) return
      if (!response.ok) {
        this.showFeedback(response.status === 429
          ? "Search limit reached. Try again shortly."
          : "Search unavailable. Try again.")
        return
      }

      const html = await response.text()
      if (sequence !== this.sequence || controller.signal.aborted) return
      const documentFragment = new DOMParser().parseFromString(html, "text/html")
      const remoteFrame = documentFragment.querySelector("turbo-frame#message_search_results")
      if (!remoteFrame) {
        this.showFeedback("Search results could not be loaded.")
        return
      }
      this.resultsTarget.replaceChildren(
        ...Array.from(remoteFrame.childNodes, (node) => document.importNode(node, true))
      )
      this.resultsTarget.hidden = false
    } catch (error) {
      if (sequence === this.sequence && error.name !== "AbortError") {
        this.showFeedback("Search connection failed. Retry by typing.")
      }
    } finally {
      if (this.pending === controller) this.pending = null
    }
  }
}
