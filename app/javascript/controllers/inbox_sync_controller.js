import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// Server-authoritative inbox refresh. WebSocket events carry only invalidation,
// not private message content or user-selected identifiers.
export default class extends Controller {
  static values = { url: String, filter: String }

  connect() {
    this.stopped = false
    this.version = 0
    this.request = null
    this.timer = null
    this.subscriptionRejected = false

    // No background polling while ActionCable is healthy. If the socket is
    // unavailable in a visible tab, a bounded HTTP snapshot recovers missed
    // unread badges and notification counts without a reload or new focus.
    this.fallbackPoller = window.setInterval(() => {
      if (this.element.dataset.inboxSyncConnected !== "true" &&
          !this.subscriptionRejected && navigator.onLine !== false) this.schedule(0)
    }, 12000)

    this.onOnline = () => this.schedule(0)
    window.addEventListener("online", this.onOnline)

    this.onVisibility = () => {
      if (document.visibilityState === "visible") this.schedule(0)
    }
    this.onFocus = () => this.schedule(0)
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("focus", this.onFocus)

    this.subscription = consumer.subscriptions.create(
      { channel: "RoomInboxChannel" },
      {
        connected: () => {
          this.subscriptionRejected = false
          this.element.dataset.inboxSyncConnected = "true"
          this.schedule(0)
        },
        disconnected: () => {
          this.element.dataset.inboxSyncConnected = "false"
        },
        rejected: () => {
          // Rejected subscriptions should not continuously poll a potentially
          // unauthorized inbox. A fresh authenticated page reconnects normally.
          this.subscriptionRejected = true
          this.element.dataset.inboxSyncConnected = "false"
        },
        received: (payload) => {
          if (payload?.type === "changed") this.schedule(150)
        }
      }
    )
  }

  disconnect() {
    this.stopped = true
    this.version++
    window.clearTimeout(this.timer)
    window.clearInterval(this.fallbackPoller)
    this.request?.abort()
    this.subscription?.unsubscribe()
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("focus", this.onFocus)
    window.removeEventListener("online", this.onOnline)
    delete this.element.dataset.inboxSyncConnected
  }

  schedule(delay = 150) {
    if (this.stopped || document.visibilityState !== "visible" || navigator.onLine === false) return
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => this.refresh(), delay)
  }

  async refresh() {
    if (this.stopped || document.visibilityState !== "visible") return
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    const version = ++this.version
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("inbox", this.filterValue)

    try {
      const response = await fetch(url, {
        credentials: "same-origin",
        cache: "no-store",
        signal: request.signal,
        headers: { Accept: "application/json" }
      })
      if (!response.ok) return

      const snapshot = await response.json()
      if (this.stopped || version !== this.version || request.signal.aborted) return
      if (typeof snapshot.direct !== "string" || typeof snapshot.public !== "string") return

      this.replaceInbox("direct-rooms", snapshot.direct)
      this.replaceInbox("rooms", snapshot.public)
      if (typeof snapshot.directory === "string") {
        this.replaceInbox("public-room-directory", snapshot.directory)
      }
      if (typeof snapshot.notifications === "string") {
        this.replaceInbox("notifications-nav", snapshot.notifications)
      }
    } catch (error) {
      // Keep the existing list if offline. Reconnect/visibility will reconcile.
      if (error.name !== "AbortError") this.element.dataset.inboxSyncStale = "true"
    } finally {
      if (this.request === request) this.request = null
    }
  }

  replaceInbox(id, html) {
    const target = this.element.querySelector("#" + id)
    if (!target) return
    const parsed = new DOMParser().parseFromString(html, "text/html")
    target.replaceChildren(...Array.from(parsed.body.childNodes, (node) => document.importNode(node, true)))
    delete this.element.dataset.inboxSyncStale
  }
}
