import { Controller } from "@hotwired/stimulus"

// Configuration and deterministic local preview only. No model call, auto Send
// or scheduling. Both reply modes remain unactivated until backend gates exist.
const PREVIEW_KINDS = ["conversation_summary", "client_brief"]
const REPLIES = ["off", "review", "full_auto"]
const SUMMARY_MODES = ["off", "manual", "after_messages", "daily"]
const SUMMARY_KINDS = ["conversation_summary", "action_items", "client_brief", "open_questions"]

export default class extends Controller {
  static targets = ["replyMode", "delay", "summaryMode", "kind", "count",
    "save", "disable", "preview", "reload", "check", "outcomes", "status", "result"]
  static values = {url: String, previewUrl: String, outcomesUrl: String, copy: Object}

  connect() {
    this.revision = 0
    this.configured = false
    this.loaded = false
    this.busy = false
    this.conflict = false
    this.dirty = false
    this.saved = null
    this.requestVersion = 0
    this.refresh()
    this.load()
  }

  disconnect() { this.requestVersion++ }

  choices() {
    return { reply_mode: this.replyModeTarget.value,
      reply_delay_seconds: Number(this.delayTarget.value),
      summary_mode: this.summaryModeTarget.value,
      summary_kind: this.kindTarget.value,
      summary_after_messages: Number(this.countTarget.value) }
  }

  valid(x = this.choices()) {
    return REPLIES.includes(x.reply_mode) &&
      SUMMARY_MODES.includes(x.summary_mode) &&
      SUMMARY_KINDS.includes(x.summary_kind) &&
      Number.isSafeInteger(x.reply_delay_seconds) &&
      x.reply_delay_seconds >= 10 && x.reply_delay_seconds <= 600 &&
      Number.isSafeInteger(x.summary_after_messages) &&
      x.summary_after_messages >= 5 && x.summary_after_messages <= 200
  }

  changed() {
    this.dirty = true
    this.resultTarget.hidden = true
    this.resultTarget.textContent = ""
    if (!this.conflict) this.statusTarget.textContent = this.copyValue.unsaved
    this.refresh()
  }

  refresh() {
    const values = this.choices()
    const same = this.saved && JSON.stringify(values) === JSON.stringify(this.saved)
    this.saveTarget.disabled = this.busy || !this.loaded || !this.valid(values) ||
      this.conflict || (this.configured && same)
    this.disableTarget.disabled = this.busy || !this.loaded || this.conflict ||
      !this.configured || (this.saved?.reply_mode === "off" && this.saved?.summary_mode === "off")
    this.previewTarget.disabled = this.busy || !this.loaded || this.conflict ||
      !PREVIEW_KINDS.includes(values.summary_kind)
    this.reloadTarget.hidden = !this.conflict
    this.checkTarget.disabled = this.busy || !this.loaded
  }

  applyPolicy(response) {
    if (!Number.isSafeInteger(response.current_revision) ||
        response.current_revision < 0) throw new Error("invalid_revision")
    this.revision = response.current_revision
    this.configured = response.configured === true
    this.saved = this.configured ? {
      reply_mode: response.policy.reply_mode,
      reply_delay_seconds: response.policy.reply_delay_seconds,
      summary_mode: response.policy.summary_mode,
      summary_kind: response.policy.summary_kind,
      summary_after_messages: response.policy.summary_after_messages
    } : null
    if (!this.dirty && this.saved) {
      this.replyModeTarget.value = this.saved.reply_mode
      this.delayTarget.value = this.saved.reply_delay_seconds
      this.summaryModeTarget.value = this.saved.summary_mode
      this.kindTarget.value = this.saved.summary_kind
      this.countTarget.value = this.saved.summary_after_messages
    }
    this.loaded = true
  }

  async load() {
    const seq = ++this.requestVersion
    this.busy = true
    this.refresh()
    try {
      const response = await fetch(this.urlValue, {
        credentials: "same-origin", cache: "no-store", headers: {Accept: "application/json"}
      })
      if (!response.ok) throw new Error("load_failed")
      const data = await response.json()
      if (seq !== this.requestVersion || !this.element.isConnected) return
      this.applyPolicy(data)
      this.conflict = false
      this.statusTarget.textContent = this.configured ? this.copyValue.loaded : this.copyValue.none
    } catch (_) {
      if (seq === this.requestVersion) this.statusTarget.textContent = this.copyValue.load_error
    } finally {
      if (seq === this.requestVersion) { this.busy = false; this.refresh() }
    }
  }

  reload() {
    this.dirty = false
    this.conflict = false
    this.load()
  }

  save() {
    if (this.saveTarget.disabled) return
    this.write("PATCH", {policy: {base_revision: this.revision, ...this.choices()}})
  }

  disable() {
    if (this.disableTarget.disabled) return
    this.write("DELETE", {policy: {base_revision: this.revision}})
  }

  async write(method, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token || this.busy) return
    this.busy = true
    this.refresh()
    try {
      const response = await fetch(this.urlValue, {
        method, credentials: "same-origin",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": token},
        body: JSON.stringify(body)
      })
      if (response.status === 409) {
        this.conflict = true
        this.statusTarget.textContent = this.copyValue.conflict
        return
      }
      if (!response.ok) throw new Error("save_failed")
      const data = await response.json()
      this.dirty = false
      this.applyPolicy(data)
      if (method === "DELETE") {
        this.replyModeTarget.value = "off"
        this.summaryModeTarget.value = "off"
      }
      this.statusTarget.textContent = this.replyModeTarget.value === "full_auto"
        ? this.copyValue.full_auto_stored
        : this.copyValue.saved
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.save_error
    } finally { this.busy = false; this.refresh() }
  }

  async checkOutcomes() {
    if (this.busy || !this.loaded || !this.outcomesUrlValue) return
    this.checkTarget.disabled = true
    this.outcomesTarget.textContent = this.copyValue.outcomes_loading
    try {
      const response = await fetch(this.outcomesUrlValue, {
        credentials: "same-origin", cache: "no-store",
        headers: {Accept: "application/json"}
      })
      if (!response.ok) throw new Error("status_unavailable")
      const data = await response.json()
      if (!Number.isSafeInteger(data.completed) || data.completed < 0 ||
          !Number.isSafeInteger(data.pending) || data.pending < 0) {
        throw new Error("invalid_status")
      }
      const template = data.completed > 0
        ? this.copyValue.outcomes_ready : this.copyValue.outcomes_empty
      this.outcomesTarget.textContent = template
        .replace("{count}", String(data.completed))
        .replace("{pending}", String(data.pending))
    } catch (_) {
      this.outcomesTarget.textContent = this.copyValue.outcomes_error
    } finally {
      this.checkTarget.disabled = false
    }
  }

  async preview() {
    if (this.previewTarget.disabled) return
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) return
    this.busy = true
    this.resultTarget.hidden = true
    this.resultTarget.textContent = ""
    this.statusTarget.textContent = this.copyValue.preview_loading
    this.refresh()
    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST", credentials: "same-origin",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": token},
        body: JSON.stringify({preview: {kind: this.kindTarget.value}})
      })
      if (!response.ok) throw new Error("preview_failed")
      const data = await response.json()
      if (data.provider_called !== false || data.saved !== false ||
          data.kind !== this.kindTarget.value || typeof data.text !== "string") {
        throw new Error("invalid_preview")
      }
      this.resultTarget.textContent = data.text
      this.resultTarget.hidden = false
      this.statusTarget.textContent = this.copyValue.preview_ready
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.preview_error
    } finally { this.busy = false; this.refresh() }
  }
}
