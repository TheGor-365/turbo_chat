import { Controller } from "@hotwired/stimulus"

// Gate 2B.2 — read-only presentation of the author's own unsent draft.
// Never sends data, calls fetch(), writes storage or changes the message form.
// Rails remains authoritative when the actual message is submitted.
const MAX_CHARS = 5000
const MAX_BYTES = 20000
const CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
const EMAIL = /\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b/i
const POSSIBLE_TOKEN = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,})\b/

export default class extends Controller {
  static targets = [
    "body", "toggle", "panel", "preset", "presetName", "snapshot",
    "result", "status", "counter"
  ]

  connect() {
    this.activePreset = this.presetTargets.find(button => button.getAttribute("aria-pressed") === "true") || this.presetTargets[0]
    this.selectVisualState()
  }

  toggle() {
    if (this.panelTarget.hidden) {
      this.panelTarget.hidden = false
      this.toggleTarget.setAttribute("aria-expanded", "true")
      this.refresh()
    } else {
      this.close()
    }
  }

  choosePreset(event) {
    this.activePreset = event.currentTarget
    this.selectVisualState()
    this.invalidatePreview("Preset changed. Review the draft again.")
  }

  selectVisualState() {
    this.presetTargets.forEach(button => {
      button.setAttribute("aria-pressed", button === this.activePreset ? "true" : "false")
    })
    if (this.activePreset && this.hasPresetNameTarget) {
      this.presetNameTarget.textContent = this.activePreset.textContent.trim() + " · v1"
    }
  }

  draftChanged() {
    if (!this.panelTarget.hidden) this.invalidatePreview("Draft changed. Review again to update the preview.")
  }

  refresh() {
    if (this.panelTarget.hidden) return
    let text = this.bodyTarget.value
    if (typeof text !== "string" || !text.trim()) {
      this.invalidatePreview("Enter your own message text to preview it here.")
      return
    }
    try {
      text = text.replace(/\r\n?/g, "\n").normalize("NFC")
    } catch (_) {
      this.invalidatePreview("Unable to review this draft.")
      return
    }
    const length = Array.from(text).length
    const bytes = new TextEncoder().encode(text).length
    if (!length || length > MAX_CHARS || bytes > MAX_BYTES || CONTROL.test(text)) {
      this.invalidatePreview("Draft review supports up to 5,000 characters / 20 KB of valid text.")
      return
    }
    // Deliberately no innerHTML, no raw content in logs or network calls.
    this.snapshotTarget.textContent = text
    this.resultTarget.hidden = false
    this.counterTarget.textContent = length + " characters · own draft only"
    const flags = []
    if (EMAIL.test(text)) flags.push("possible email")
    if (POSSIBLE_TOKEN.test(text)) flags.push("possible secret")
    this.statusTarget.textContent = flags.length
      ? "Local preview. Review flags: " + flags.join(", ") + ". Nothing sent or generated."
      : "Local preview only. Nothing sent, saved as an AI request or generated."
  }

  invalidatePreview(message) {
    this.snapshotTarget.textContent = ""
    this.resultTarget.hidden = true
    this.counterTarget.textContent = ""
    this.statusTarget.textContent = message
  }

  close(event) {
    if (event && event.type === "keydown") event.preventDefault()
    this.panelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.invalidatePreview("")
    this.toggleTarget.focus()
  }

  submitEnd(event) {
    if (!event.detail.success) return
    this.panelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.invalidatePreview("")
    // Do not steal focus from the canonical message-composer success handler.
  }
}
