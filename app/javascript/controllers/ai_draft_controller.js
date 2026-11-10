import { Controller } from "@hotwired/stimulus"

// H3e: local draft + opt-in, single-request Grok suggestion.
// Changes require Apply; sending remains a distinct user action.
const MAX_CHARS = 5000
const MAX_BYTES = 20000
const CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
const EMAIL = /\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b/i
const POSSIBLE_TOKEN = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,})\b/

export default class extends Controller {
  static targets = [
    "body", "toggle", "panel", "preset", "presetName", "editor",
    "result", "status", "counter", "apply", "undo",
    "settingsPanel", "roomFeedback", "presetBadge", "browserName",
    "spellToggle", "spellState", "autoIndicator", "aiIndicator", "spellIndicator", "spellIndicatorLabel",
    "generateButton", "generateLabel", "comparison", "originalText",
    "editorLabel", "styleLabel", "styleDetails", "quickUndo"
  ]

  connect() {
    this.selectedPresetId = this.presetTargets[0]?.dataset.presetId
    this.spellcheckEnabled = true
    this.storageAvailable = true
    this.restoreRoomPreferences()
    this.sourceText = null
    this.editorTouched = false
    this.internalUpdate = false
    this.undoRecord = null
    this.generating = false
    this.generatedApplied = false
    this.selectVisualState()
    this.renderRoomState()
    this.browserNameTarget.textContent = this.detectBrowser()
    this.updateButtons()
  }

  get roomPreferenceKey() {
    const user = this.element.dataset.aiDraftUserId
    const room = this.element.dataset.aiDraftRoomId
    return /^\d+$/.test(user || "") && /^\d+$/.test(room || "")
      ? `turbo-chat:writing:v1:user:${user}:room:${room}`
      : null
  }

  restoreRoomPreferences() {
    try {
      const key = this.roomPreferenceKey
      const saved = key ? JSON.parse(window.localStorage.getItem(key) || "null") : null
      if (!saved || typeof saved !== "object" || Array.isArray(saved)) return
      const allowed = this.presetTargets.map(button => button.dataset.presetId)
      if (typeof saved.preset === "string" && allowed.includes(saved.preset)) this.selectedPresetId = saved.preset
      if (typeof saved.spellcheck === "boolean") this.spellcheckEnabled = saved.spellcheck
    } catch (_) {
      this.storageAvailable = false
    }
  }

  saveRoomPreferences() {
    try {
      if (!this.roomPreferenceKey) throw new Error("Invalid room scope")
      window.localStorage.setItem(this.roomPreferenceKey,
        JSON.stringify({ preset: this.selectedPresetId, spellcheck: this.spellcheckEnabled }))
      this.storageAvailable = true
    } catch (_) {
      this.storageAvailable = false
    }
    return this.storageAvailable
  }

  renderRoomState() {
    const label = this.presetTargets.find(button => button.dataset.presetId === this.selectedPresetId)?.textContent.trim() || "Polish / Clarity"
    this.presetBadgeTarget.textContent = label
    this.presetBadgeTarget.title = "Saved writing preference: " + label +
      (this.hasGenerateButtonTarget ? ". Grok currently proofreads only." : "")
    this.spellToggleTarget.setAttribute("aria-checked", String(this.spellcheckEnabled))
    this.spellToggleTarget.setAttribute("aria-label", this.spellcheckEnabled ? "Turn spelling hints off" : "Turn spelling hints on")
    this.spellStateTarget.textContent = this.spellcheckEnabled ? "ON" : "OFF"
    this.spellIndicatorLabelTarget.textContent = this.spellcheckEnabled ? "SPELL ON" : "SPELL OFF"
    this.spellIndicatorTarget.dataset.enabled = String(this.spellcheckEnabled)
    this.spellIndicatorTarget.setAttribute("aria-label", "Browser spelling hints " + (this.spellcheckEnabled ? "on" : "off"))
    this.aiIndicatorTarget.setAttribute("aria-label", this.hasGenerateButtonTarget
      ? "Manual AI suggestion available with explicit consent" : "AI correction off: no provider")
    this.autoIndicatorTarget.setAttribute("aria-label", "Auto correction off: no provider")
    this.bodyTarget.spellcheck = this.spellcheckEnabled
    this.editorTarget.spellcheck = this.spellcheckEnabled
  }

  detectBrowser() {
    const ua = navigator.userAgent || ""
    if (/Edg\//.test(ua)) return "Edge · this device"
    if (/OPR\//.test(ua)) return "Opera · this device"
    if (/Firefox\//.test(ua)) return "Firefox · this device"
    if (/Chrome\//.test(ua)) return "Chrome · this device"
    if (/Safari\//.test(ua)) return "Safari · this device"
    return "This browser · this device"
  }

  showSettings() {
    this.panelTarget.hidden = true
    this.settingsPanelTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.roomFeedbackTarget.textContent = this.hasGenerateButtonTarget
      ? "Only style/spelling settings stay here. Manual Grok requires separate consent; AUTO remains OFF."
      : "Only style and spelling settings are stored in this browser. AI and AUTO remain OFF."
    this.settingsPanelTarget.querySelector("button[data-preset-id]")?.focus()
  }

  showEditor() {
    this.settingsPanelTarget.hidden = true
    this.panelTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    if (this.sourceText === null) this.refresh()
    else this.updateButtons()
    this.resizeEditor()
    this.editorTarget.focus()
  }

  closeSettings(event) { this.close(event) }

  toggleSpellcheck() {
    this.spellcheckEnabled = !this.spellcheckEnabled
    this.renderRoomState()
    const saved = this.saveRoomPreferences()
    this.roomFeedbackTarget.textContent = saved
      ? "Spelling hints " + (this.spellcheckEnabled ? "on" : "off") + " for this room. AI correction remains off."
      : "Spelling hints changed for now, but your browser blocked saving preferences."
  }

  autoUnavailable() {
    this.roomFeedbackTarget.textContent =
      "Automatic correction is off. Every Grok request is manually initiated."
  }

  toggle() {
    if (!this.panelTarget.hidden || !this.settingsPanelTarget.hidden) return this.close()
    this.showEditor()
  }

  choosePreset(event) {
    const selected = event.currentTarget.dataset.presetId
    if (!this.presetTargets.some(button => button.dataset.presetId === selected)) return
    this.selectedPresetId = selected
    this.selectVisualState()
    this.renderRoomState()
    this.updateButtons()
    const saved = this.saveRoomPreferences()
    if (!this.settingsPanelTarget.hidden) {
      this.roomFeedbackTarget.textContent = saved
        ? "Preset saved for this room. AI correction remains OFF."
        : "Preset changed for now, but your browser blocked saving preferences."
    }
    if (!this.panelTarget.hidden && this.hasGenerateButtonTarget && selected !== "polish_clarity") {
      this.setStatus("Preference saved. Grok still uses Polish / Clarity proofreading.")
    }
  }

  selectVisualState() {
    this.presetTargets.forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.presetId === this.selectedPresetId))
    })
    const active = this.presetTargets.find(button => button.dataset.presetId === this.selectedPresetId)
    const label = active?.textContent.trim() || "Polish / Clarity"
    if (this.hasPresetNameTarget) this.presetNameTarget.textContent = label + " · saved preference"
    if (this.hasStyleLabelTarget) this.styleLabelTarget.textContent = label
  }

  valid(text) {
    if (typeof text !== "string" || !text.trim() || CONTROL.test(text)) return false
    return Array.from(text).length <= MAX_CHARS && new TextEncoder().encode(text).length <= MAX_BYTES
  }

  draftChanged() {
    if (this.internalUpdate || this.panelTarget.hidden) return
    this.syncUndo()
    if (!this.editorTouched) {
      this.refresh()
    } else {
      this.updateButtons()
      this.setStatus(this.bodyTarget.value !== this.sourceText
        ? "Message changed while editing. Reload the copy before applying; your edits remain visible."
        : "Working copy is yours to edit; apply deliberately before sending.")
    }
  }

  refresh() {
    if (this.panelTarget.hidden) return
    const source = this.bodyTarget.value
    this.sourceText = source
    this.editorTouched = false
    this.clearComparison()
    if (!this.valid(source)) {
      this.editorTarget.value = ""
      this.resultTarget.hidden = true
      this.counterTarget.textContent = ""
      this.setStatus(!source.trim()
        ? "Type a message first. This editor reads only your own unsent text."
        : "Draft editing supports nonempty text up to 5,000 characters / 20 KB.")
      this.updateButtons()
      return
    }
    this.editorTarget.value = source
    this.resultTarget.hidden = false
    this.resizeEditor()
    this.describeWorkingCopy()
    this.updateButtons()
  }

  editWorking() {
    this.editorTouched = true
    this.resizeEditor()
    this.describeWorkingCopy()
    this.updateButtons()
  }

  resizeEditor() {
    const node = this.editorTarget
    node.style.height = "auto"
    node.style.height = Math.min(node.scrollHeight, 236) + "px"
  }

  clearComparison() {
    if (this.hasComparisonTarget) this.comparisonTarget.hidden = true
    if (this.hasOriginalTextTarget) this.originalTextTarget.textContent = ""
    if (this.hasEditorLabelTarget) this.editorLabelTarget.textContent = "Draft"
  }

  describeWorkingCopy() {
    const proposed = this.editorTarget.value
    const chars = Array.from(proposed).length
    this.counterTarget.textContent = chars + " / 5000"
    if (!this.valid(proposed)) {
      this.setStatus("Working copy must contain valid text within 5,000 characters / 20 KB.")
      return
    }
    if (this.bodyTarget.value !== this.sourceText) {
      this.setStatus("Message changed. Reload before applying to avoid overwriting newer typing.")
      return
    }
    const flags = []
    if (EMAIL.test(proposed)) flags.push("possible email")
    if (POSSIBLE_TOKEN.test(proposed)) flags.push("possible secret")
    this.setStatus(flags.length
      ? "Review before processing: " + flags.join(", ") + "."
      : "")
  }

  updateButtons() {
    const validCopy = this.valid(this.editorTarget.value)
    this.applyTarget.disabled = this.panelTarget.hidden || !validCopy ||
      this.sourceText === null || this.bodyTarget.value !== this.sourceText ||
      this.editorTarget.value === this.bodyTarget.value
    this.syncUndo()
    this.undoTarget.hidden = !this.undoRecord
    this.undoTarget.disabled = !this.undoRecord ||
      this.bodyTarget.value !== this.undoRecord.after
    if (this.hasGenerateButtonTarget) {
      this.generateButtonTarget.hidden = this.hasComparisonTarget && !this.comparisonTarget.hidden
      this.generateButtonTarget.disabled = this.generating || this.panelTarget.hidden ||
        !validCopy || this.sourceText === null || this.bodyTarget.value !== this.sourceText
    }
    if (this.hasQuickUndoTarget) {
      // Quick Undo is available whenever a reviewed edit was applied and
      // the overlay is closed. This also covers manually edited drafts.
      this.quickUndoTarget.hidden = !(this.undoRecord && this.panelTarget.hidden &&
        this.bodyTarget.value === this.undoRecord.after)
    }
  }

  syncUndo() {
    if (this.undoRecord && this.bodyTarget.value !== this.undoRecord.after) {
      // A later human edit wins. Never overwrite it with an obsolete undo.
      this.undoRecord = null
    }
  }

  async generate() {
    // The single-purpose button plus adjacent notice gives explicit,
    // request-specific approval; we do not use a persistent checkbox.
    if (!this.hasGenerateButtonTarget || this.generating ||
      this.generateButtonTarget.disabled) return
    const draft = this.editorTarget.value
    const priorBody = this.bodyTarget.value
    if (!this.valid(draft) || priorBody !== this.sourceText ||
      !this.element.dataset.aiDraftGenerateUrl) return

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || !globalThis.crypto?.randomUUID) {
      this.setStatus("Secure request unavailable. Original draft preserved.")
      return
    }

    this.generating = true
    this.updateButtons()
    if (this.hasGenerateLabelTarget) this.generateLabelTarget.textContent = "Improving…"
    this.setStatus("Improving draft…")
    try {
      const response = await fetch(this.element.dataset.aiDraftGenerateUrl, {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ draft: {
          text: draft, preset_id: "polish_clarity", consent: "1",
          request_id: globalThis.crypto.randomUUID()
        } })
      })
      if (!response.ok) throw new Error("HTTP " + response.status)
      const result = await response.json()
      if (typeof result.text !== "string" || !this.valid(result.text)) {
        throw new Error("Invalid provider result")
      }
      // Human typing or changing room/preset wins over a late response.
      if (this.panelTarget.hidden || this.bodyTarget.value !== priorBody ||
        this.editorTarget.value !== draft) {
        this.setStatus("Suggestion arrived, but draft changed. No text was overwritten.")
        return
      }
      const reportedCost = String(result.cost_usd ?? "unknown")
      if (result.text === draft) {
        // A successful billable API call does not guarantee any edit.
        // The original draft is preserved; no meaningless Apply is offered.
        this.setStatus("No changes · $" + reportedCost + " · Not sent")
        return
      }
      this.editorTarget.value = result.text
      this.editorTouched = true
      this.originalTextTarget.textContent = draft
      this.comparisonTarget.hidden = false
      this.editorLabelTarget.textContent = "Suggested"
      this.resizeEditor()
      this.setStatus("Suggested edit · $" + reportedCost + " · Review before Apply")
    } catch (_) {
      this.setStatus("Grok unavailable. Draft kept; do not retry automatically.")
    } finally {
      this.generating = false
      if (this.hasGenerateLabelTarget) this.generateLabelTarget.textContent = "Improve with Grok"
      this.updateButtons()
    }
  }

  apply() {
    const proposed = this.editorTarget.value
    if (this.panelTarget.hidden || !this.valid(proposed) ||
      this.sourceText === null || this.bodyTarget.value !== this.sourceText ||
      proposed === this.bodyTarget.value) return

    const original = this.bodyTarget.value
    const fromGrok = this.hasComparisonTarget && !this.comparisonTarget.hidden
    this.undoRecord = { before: original, after: proposed }
    this.generatedApplied = fromGrok
    this.replaceMessageText(proposed)
    this.sourceText = proposed
    this.editorTouched = false
    if (fromGrok) {
      // Clear the overlay after a reviewed AI edit; compact Undo stays near Send.
      this.panelTarget.hidden = true
      this.toggleTarget.setAttribute("aria-expanded", "false")
      this.clearComparison()
    }
    this.updateButtons()
    this.setStatus("Applied · not sent. Undo is available.")
    this.bodyTarget.focus()
  }

  undo() {
    const record = this.undoRecord
    if (!record || this.bodyTarget.value !== record.after) return
    this.undoRecord = null
    this.generatedApplied = false
    this.replaceMessageText(record.before)
    this.sourceText = record.before
    this.editorTarget.value = record.before
    this.editorTouched = false
    this.clearComparison()
    this.resizeEditor()
    this.describeWorkingCopy()
    this.updateButtons()
    this.setStatus("Restored original · not sent.")
    this.bodyTarget.focus()
  }

  replaceMessageText(text) {
    this.internalUpdate = true
    this.bodyTarget.value = text
    // Keep existing typing indicator and other listeners in sync.
    this.bodyTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.internalUpdate = false
  }

  setStatus(message) { this.statusTarget.textContent = message }

  close(event) {
    if (event && event.type === "keydown") event.preventDefault()
    this.panelTarget.hidden = true
    this.settingsPanelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.editorTarget.value = ""
    this.sourceText = null
    this.editorTouched = false
    this.resultTarget.hidden = true
    this.counterTarget.textContent = ""
    this.clearComparison()
    this.setStatus("")
    this.updateButtons()
    this.toggleTarget.focus()
  }

  submitEnd(event) {
    if (!event.detail.success) return
    this.undoRecord = null
    this.generatedApplied = false
    this.panelTarget.hidden = true
    this.settingsPanelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.editorTarget.value = ""
    this.sourceText = null
    this.editorTouched = false
    this.resultTarget.hidden = true
    this.counterTarget.textContent = ""
    this.clearComparison()
    this.setStatus("")
    this.updateButtons()
    // Canonical message-composer owns focus and all send-side mutations.
  }
}
