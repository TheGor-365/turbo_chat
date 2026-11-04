import { Controller } from "@hotwired/stimulus"

// Redis/ActionCable is the primary live transport. When a browser loses
// its stream subscription (e.g. an app container is replaced), a bounded
// membership-checked HTTP request reconciles missed messages without F5.
// Offline HTTP sync is explicitly labelled as degraded, not "realtime".
export default class extends Controller {
  static targets = ["status", "syncButton"]
  static values = { syncUrl: String }

  connect() {
    this.source = this.element.querySelector('turbo-cable-stream-source[channel="RoomMessagesChannel"]')
    this.lastConnected = false
    this.syncing = false
    this.suspended = false
    this.observer = null
    this.onVisibility = () => {
      if (document.visibilityState === "visible") this.sync()
    }
    document.addEventListener("visibilitychange", this.onVisibility)

    if (this.source) {
      this.observer = new MutationObserver(() => this.checkConnection())
      this.observer.observe(this.source, { attributes: true, attributeFilter: ["connected"] })
    }

    // Some browser tabs remain stale when a development container restarts.
    // A disconnected tab refreshes only its message list, not the whole page
    // or a composed draft. Hidden tabs catch up upon becoming visible.
    this.checkConnection()
    this.timer = window.setInterval(() => {
      if (document.visibilityState === "visible" && !this.isConnected()) this.sync()
    }, 12000)
  }

  disconnect() {
    this.suspended = true
    this.observer?.disconnect()
    document.removeEventListener("visibilitychange", this.onVisibility)
    if (this.timer) window.clearInterval(this.timer)
  }

  isConnected() {
    return Boolean(this.source?.isConnected && this.source.hasAttribute("connected"))
  }

  checkConnection() {
    const connected = this.isConnected()
    this.statusTarget.textContent = connected
      ? "Live · WebSocket connected"
      : "Reconnecting · HTTP catch-up available"

    if (connected && !this.lastConnected) this.sync()
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

  async sync() {
    if (this.suspended || this.syncing || !this.hasSyncUrlValue) return
    this.syncing = true
    this.syncButtonTarget.disabled = true
    try {
      let cursor = this.lastMessageId()
      // At most 250 messages per sync; subsequent cycles resume at the
      // highest rendered id. Never expose an unrestricted history endpoint.
      for (let batch = 0; batch < 5; batch++) {
        const url = new URL(this.syncUrlValue, window.location.origin)
        url.searchParams.set("after_id", String(cursor))
        const response = await fetch(url, {
          credentials: "same-origin",
          cache: "no-store",
          headers: { Accept: "text/vnd.turbo-stream.html" }
        })
        if (!response.ok) throw new Error("Sync HTTP " + response.status)

        const html = await response.text()
        if (this.suspended) return
        if (html.trim()) await window.Turbo.renderStreamMessage(html)

        const next = Number(response.headers.get("X-Chat-Last-Id"))
        if (response.headers.get("X-Chat-More") !== "1" || !Number.isSafeInteger(next) || next <= cursor) break
        cursor = next
      }
      if (!this.isConnected()) this.statusTarget.textContent = "Reconnecting · messages synced by HTTP"
    } catch (_) {
      if (!this.suspended) this.statusTarget.textContent = "Live updates unavailable · sync failed"
    } finally {
      this.syncing = false
      if (!this.suspended && this.hasSyncButtonTarget) this.syncButtonTarget.disabled = false
    }
  }
}
