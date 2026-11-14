import { Controller } from "@hotwired/stimulus"

// One-click, own-unsent-draft ONLY. One button click can authorize ONE
// paid request in development. No typing trigger, background retries, Send,
// room context, or writes. Server preflight/budget remain authoritative.
const MAX_CHARS = 5000
const MAX_BYTES = 20000
const CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
const EMAIL = /\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b/i
const TOKEN = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,})\b/i

export default class extends Controller {
  static targets = ["body", "panel", "original", "candidate", "status",
    "cost", "generate", "apply", "undo"]
  static values = { copy: Object }

  connect() {
    this.epoch = 0
    this.pending = false
    this.source = null
    this.preset = null
    this.lastApplied = null
    this.refresh()
  }

  disconnect() { ++this.epoch }

  editor() {
    return this.application.getControllerForElementAndIdentifier(this.element, "ai-draft")
  }

  valid(value) {
    return typeof value === "string" && value.trim() &&
      !CONTROL.test(value) && Array.from(value).length <= MAX_CHARS &&
      new TextEncoder().encode(value).length <= MAX_BYTES
  }

  refresh() {
    if (!this.hasGenerateTarget) return
    const original = this.bodyTarget.value
    const endpoint = this.element.dataset.quickBeautifyUrl
    this.generateTarget.disabled = this.pending || !this.valid(original) || !endpoint
    if (this.hasApplyTarget) {
      this.applyTarget.disabled = this.pending || this.source === null ||
        this.bodyTarget.value !== this.source ||
        this.preset !== this.editor()?.selectedPresetId ||
        !this.valid(this.candidateTarget.value) ||
        this.candidateTarget.value === this.source
    }
    if (this.hasUndoTarget) this.undoTarget.hidden = !(this.lastApplied &&
      this.bodyTarget.value === this.lastApplied.after &&
      this.editor()?.undoRecord?.after === this.lastApplied.after)
  }

  changed() {
    if (this.source !== null && this.bodyTarget.value !== this.source) {
      this.discard(this.copyValue.stale, true)
    }
    if (this.lastApplied && this.bodyTarget.value !== this.lastApplied.after)
      this.lastApplied = null
    this.refresh()
  }

  discard(message = "", keepNotice = false) {
    ++this.epoch
    this.source = null
    this.preset = null
    this.originalTarget.textContent = ""
    this.candidateTarget.value = ""
    this.costTarget.hidden = true
    this.costTarget.textContent = ""
    this.panelTarget.hidden = !keepNotice
    this.statusTarget.textContent = message
    this.refresh()
  }

  keepMine() {
    this.discard()
    this.bodyTarget.focus()
  }

  candidateChanged() { this.refresh() }

  async generate() {
    const editor = this.editor()
    if (this.pending || editor?.generating || !this.valid(this.bodyTarget.value)) return
    const original = this.bodyTarget.value
    const preset = editor?.selectedPresetId
    const endpoint = this.element.dataset.quickBeautifyUrl
    if (!endpoint) {
      this.discard(this.copyValue.unavailable, true)
      return
    }
    // The quick path does not guess the target language. Use advanced editor.
    if (preset === "translate_preserving_tone") {
      this.discard(this.copyValue.chooseLanguage, true)
      return
    }
    if (!["polish_clarity","professional_client_reply","friendly","concise","technical_summary"].includes(preset)) {
      this.discard(this.copyValue.unavailable, true)
      return
    }
    if (EMAIL.test(original) || TOKEN.test(original)) {
      this.discard(this.copyValue.sensitive, true)
      return
    }
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (!csrf || !globalThis.crypto?.randomUUID) {
      this.discard(this.copyValue.unavailable, true)
      return
    }

    const epoch = ++this.epoch
    this.source = original
    this.preset = preset
    this.panelTarget.hidden = false
    this.originalTarget.textContent = original
    this.candidateTarget.value = ""
    this.costTarget.hidden = true
    this.costTarget.textContent = ""
    this.statusTarget.textContent = this.copyValue.working
    this.pending = true
    editor.generating = true
    editor.updateButtons()
    this.refresh()
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        credentials: "same-origin",
        headers: {"Content-Type":"application/json","Accept":"application/json","X-CSRF-Token":csrf},
        body: JSON.stringify({draft:{
          text: original, preset_id: preset, consent:"1",
          request_id: globalThis.crypto.randomUUID()
        }})
      })
      if (!response.ok) throw new Error("request_failed")
      const payload = await response.json()
      if (!this.valid(payload.text)) throw new Error("invalid_result")
      if (epoch !== this.epoch || !this.element.isConnected ||
          this.bodyTarget.value !== original || this.editor()?.selectedPresetId !== preset) return
      this.costTarget.textContent = this.copyValue.cost +
        String(payload.cost_usd ?? this.copyValue.unknown)
      this.costTarget.hidden = false
      if (payload.text === original) {
        this.statusTarget.textContent = this.copyValue.unchanged
      } else {
        this.candidateTarget.value = payload.text
        this.statusTarget.textContent = this.copyValue.ready
      }
    } catch (_) {
      if (epoch === this.epoch) {
        this.candidateTarget.value = ""
        this.statusTarget.textContent = this.copyValue.failed
      }
    } finally {
      this.pending = false
      editor.generating = false
      editor.updateButtons()
      this.refresh()
    }
  }

  apply() {
    const editor = this.editor()
    if (!editor || this.applyTarget.disabled || this.source === null ||
        this.bodyTarget.value !== this.source ||
        editor.selectedPresetId !== this.preset) return
    const after = this.candidateTarget.value
    const before = this.source
    if (!this.valid(after) || after === before) return
    // Reuse the existing undo/source-handling logic rather than new writes.
    editor.undoRecord = {before, after}
    editor.generatedApplied = true
    this.lastApplied = {before, after}
    this.discard()
    editor.replaceMessageText(after)
    // Advanced editor starts from accepted draft next time.
    editor.sourceText = null
    editor.editorTouched = false
    editor.updateButtons()
    this.refresh()
    this.bodyTarget.focus()
  }

  undo() {
    const editor = this.editor()
    if (!editor || !this.lastApplied ||
        this.bodyTarget.value !== this.lastApplied.after ||
        editor.undoRecord?.after !== this.lastApplied.after) return
    editor.undo()
    this.lastApplied = null
    this.refresh()
  }

  submitEnd(event) {
    if (!event.detail.success) return
    this.discard()
    this.lastApplied = null
    this.refresh()
  }
}
