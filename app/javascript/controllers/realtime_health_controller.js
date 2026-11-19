import { Controller } from "@hotwired/stimulus"

// ActionCable is the primary stream; bounded, membership-checked HTTP
// catch-up is explicitly labeled as degraded, never as a live connection.
// Browser offline events are an additional hint, not proof of server reachability.
export default class extends Controller {
  static targets = ["status", "syncButton"]
  static values = { syncUrl: String }

  connect() {
    this.source = this.element.querySelector('turbo-cable-stream-source[channel="RoomMessagesChannel"]')
    this.lastConnected = false
    this.everConnected = false
    this.syncing = false
    this.suspended = false
    this.request = null

    this.onVisibility = () => {
      if (document.visibilityState === "visible") {
        this.checkConnection()
        if (navigator.onLine !== false) this.sync()
      }
    }
    this.onOffline = () => {
      this.request?.abort()
      this.setStatus("offline")
    }
    this.onOnline = () => {
      this.checkConnection()
      this.sync()
    }
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("offline", this.onOffline)
    window.addEventListener("online", this.onOnline)

    if (this.source) {
      this.observer = new MutationObserver(() => this.checkConnection())
      this.observer.observe(this.source, { attributes: true, attributeFilter: ["connected"] })
    }

    this.setStatus(navigator.onLine === false ? "offline" : "connecting")
    this.checkConnection()
    // A missing initial subscription becomes "reconnecting" instead of
    // staying in a misleading "connecting" state indefinitely.
    this.connectionProbe = window.setTimeout(() => {
      if (!this.suspended && !this.isConnected() && navigator.onLine !== false) {
        this.setStatus("reconnecting")
      }
    }, 5000)

    // A stale but visible tab can recover messages while sockets reconnect.
    this.timer = window.setInterval(() => {
      if (document.visibilityState === "visible" && !this.isConnected() && navigator.onLine !== false) {
        this.sync()
      }
    }, 12000)
  }

  disconnect() {
    this.suspended = true
    this.observer?.disconnect()
    this.request?.abort()
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("offline", this.onOffline)
    window.removeEventListener("online", this.onOnline)
    window.clearInterval(this.timer)
    window.clearTimeout(this.connectionProbe)
  }

  setStatus(state) {
    if (this.suspended) return
    const labels = {
      connecting: "Connecting to live messages…",
      live: "Live · WebSocket connected",
      reconnecting: "Reconnecting · HTTP catch-up available",
      "http-synced": "Reconnecting · messages synced by HTTP",
      offline: "Offline · will retry when connected",
      "sync-failed": "Reconnecting · HTTP sync failed"
    }
    this.element.dataset.realtimeHealthState = state
    if (this.hasStatusTarget) this.statusTarget.textContent = labels[state] || labels.reconnecting
    if (this.hasSyncButtonTarget) this.syncButtonTarget.disabled = this.syncing || state === "offline"
  }

  isConnected() {
    return Boolean(this.source?.isConnected && this.source.hasAttribute("connected"))
  }

  checkConnection() {
    if (this.suspended) return
    if (navigator.onLine === false) {
      this.setStatus("offline")
      return
    }

    const connected = this.isConnected()
    if (connected) {
      this.everConnected = true
      this.setStatus("live")
      if (!this.lastConnected) this.sync()
    } else {
      this.setStatus(this.everConnected ? "reconnecting" : "connecting")
    }
    this.lastConnected = connected
  }

  lastMessageId() {
    let max = 0
    this.element.querySelectorAll('#messages-container > [id^="message_"]').forEach((node) => {
      const id = Number(node.id.slice(8))
      if (Number.isSafeInteger(id) && id > max) max = id
    })
    return max
  }

  // Versioned IDs from the currently rendered room only. The server scopes
  // every lookup to the authenticated room and caps the set to 30 entries.
  // No message text or attachment data is sent in the reconciliation request.
  recheckSnapshot() {
    return Array.from(this.element.querySelectorAll(
      '#messages-container > [id^="message_"][data-message-sync-version]'
    )).slice(-30).map((node) => {
      const id = node.id.slice(8)
      const version = node.dataset.messageSyncVersion
      if (!/^[1-9]\d{0,17}$/.test(id) || !/^[1-9]\d{0,17}$/.test(version)) return null
      return `${id}:${version}`
    }).filter(Boolean).join(",")
  }

  async sync() {
    if (this.suspended || this.syncing || !this.hasSyncUrlValue || navigator.onLine === false) return
    this.syncing = true
    const request = new AbortController()
    this.request = request
    if (this.hasSyncButtonTarget) this.syncButtonTarget.disabled = true
    try {
      let cursor = this.lastMessageId()
      // At most 250 messages per request cycle. Cursor never reaches across
      // rooms; the Rails endpoint still checks current room membership.
      for (let batch = 0; batch < 5; batch++) {
        const url = new URL(this.syncUrlValue, window.location.origin)
        url.searchParams.set("after_id", String(cursor))
        // Only the first batch rechecks existing DOM: later batches only
        // append newer messages and cannot overwrite paginated history.
        if (batch === 0) {
          const recheck = this.recheckSnapshot()
          if (recheck) url.searchParams.set("recheck", recheck)
        }
        const response = await fetch(url, {
          credentials: "same-origin",
          cache: "no-store",
          signal: request.signal,
          headers: { Accept: "text/vnd.turbo-stream.html" }
        })
        if (!response.ok) throw new Error("Sync HTTP " + response.status)

        const html = await response.text()
        if (this.suspended || request.signal.aborted) return
        if (html.trim()) await window.Turbo.renderStreamMessage(html)

        const next = Number(response.headers.get("X-Chat-Last-Id"))
        if (response.headers.get("X-Chat-More") !== "1" || !Number.isSafeInteger(next) || next <= cursor) break
        cursor = next
      }
      this.setStatus(this.isConnected() ? "live" : "http-synced")
    } catch (_) {
      if (this.suspended) return
      this.setStatus(navigator.onLine === false ? "offline"
        : this.isConnected() ? "live" : "sync-failed")
    } finally {
      this.syncing = false
      if (this.request === request) this.request = null
      if (!this.suspended && this.hasSyncButtonTarget) {
        this.syncButtonTarget.disabled = navigator.onLine === false
      }
    }
  }
}
