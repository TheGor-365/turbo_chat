import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// Truthful presence for this private conversation only. The authenticated
// server decides whose status is visible; no client-supplied peer identity.
export default class extends Controller {
  static targets = ["dot", "label"]
  static values = { url: String, roomId: Number }

  connect() {
    this.ready = false
    this.stopped = false
    this.request = null
    this.render("unavailable")

    this.onVisibility = () => {
      this.heartbeat()
      if (document.visibilityState === "visible") this.refresh()
    }
    this.onFocus = () => {
      this.heartbeat()
      this.refresh()
    }
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("focus", this.onFocus)
    // Full-page navigation does not reliably call Stimulus disconnect before
    // the socket closes. Try to unsubscribe while the transport is still live;
    // Redis TTL remains authoritative if the browser is killed abruptly.
    this.onPageHide = () => this.subscription?.unsubscribe()
    window.addEventListener("pagehide", this.onPageHide)

    this.subscription = consumer.subscriptions.create(
      { channel: "RoomPresenceChannel", room_id: this.roomIdValue },
      {
        connected: () => {
          this.ready = true
          this.element.dataset.peerPresenceConnected = "true"
          this.heartbeat()
          this.refresh()
          window.clearInterval(this.heartbeatTimer)
          window.clearInterval(this.pollTimer)
          this.heartbeatTimer = window.setInterval(() => this.heartbeat(), 12000)
          this.pollTimer = window.setInterval(() => this.refresh(), 15000)
        },
        disconnected: () => {
          this.ready = false
          this.element.dataset.peerPresenceConnected = "false"
          window.clearInterval(this.heartbeatTimer)
          window.clearInterval(this.pollTimer)
          this.request?.abort()
          this.render("unavailable")
        },
        rejected: () => {
          this.ready = false
          this.element.dataset.peerPresenceConnected = "false"
          this.render("unavailable")
        },
        received: (data) => {
          if (data?.type === "presence_changed") this.refresh()
        }
      }
    )
  }

  disconnect() {
    this.stopped = true
    this.ready = false
    window.clearInterval(this.heartbeatTimer)
    window.clearInterval(this.pollTimer)
    this.request?.abort()
    this.subscription?.unsubscribe()
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("focus", this.onFocus)
    window.removeEventListener("pagehide", this.onPageHide)
    delete this.element.dataset.peerPresenceConnected
  }

  heartbeat() {
    if (!this.ready || this.stopped) return
    this.subscription?.perform("heartbeat", { active: document.visibilityState === "visible" })
  }

  async refresh() {
    if (!this.ready || this.stopped || document.visibilityState !== "visible") return
    this.request?.abort()
    const request = new AbortController()
    this.request = request

    try {
      const response = await fetch(this.urlValue, {
        credentials: "same-origin",
        cache: "no-store",
        signal: request.signal,
        headers: { Accept: "application/json" }
      })
      if (request.signal.aborted || this.stopped) return
      if (!response.ok) {
        this.render("unavailable")
        return
      }

      const payload = await response.json()
      if (!request.signal.aborted && !this.stopped) this.render(payload.status)
    } catch (error) {
      if (error.name !== "AbortError" && !this.stopped) this.render("unavailable")
    } finally {
      if (this.request === request) this.request = null
    }
  }

  render(status) {
    const labels = {
      online: "Online in this chat",
      away: "Away from this chat",
      offline: "Offline",
      unavailable: "Presence unavailable"
    }
    const safe = Object.hasOwn(labels, status) ? status : "unavailable"
    if (this.hasDotTarget) this.dotTarget.dataset.presenceState = safe
    if (this.hasLabelTarget) this.labelTarget.textContent = labels[safe]
    this.element.dataset.peerPresenceStatus = safe
  }
}
