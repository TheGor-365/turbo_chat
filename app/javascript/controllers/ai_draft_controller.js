import { Controller } from "@hotwired/stimulus"

// Gate 2B.3 — browser-local working copy of the author's unsent message.
// Explicit Apply/Undo is the only draft mutation; no AI inference or network.
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
    "generateButton", "consent"
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
    this.presetBadgeTarget.title = "Selected for this room: " + label + " (no AI processing)"
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
      "AUTO OFF: no AI provider, room consent or spending limits. No text is corrected automatically."
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
    if (!this.panelTarget.hidden) {
      this.setStatus(this.hasGenerateButtonTarget
        ? "Preset saved. Only Polish / Clarity currently supports manual Grok generation."
        : "Preset saved locally for this room. No model is connected; use manual editing or spelling hints.")
    }
  }

  selectVisualState() {
    this.presetTargets.forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.presetId === this.selectedPresetId))
    })
    if (this.hasPresetNameTarget) {
      const active = this.presetTargets.find(button => button.dataset.presetId === this.selectedPresetId)
      this.presetNameTarget.textContent = (active?.textContent.trim() || "Polish / Clarity") + " · planned AI rule"
    }
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
    this.describeWorkingCopy()
    this.updateButtons()
  }

  editWorking() {
    this.editorTouched = true
    this.describeWorkingCopy()
    this.updateButtons()
  }

  describeWorkingCopy() {
    const proposed = this.editorTarget.value
    const chars = Array.from(proposed).length
    this.counterTarget.textContent = chars + " / 5000 characters · local working copy"
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
      ? "Review flags: " + flags.join(", ") + ". Local only; not generated or sent."
      : "Live local editing. Browser spellcheck is available; AI correction is not yet connected.")
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
      this.generateButtonTarget.disabled = this.generating || this.panelTarget.hidden ||
        !this.hasConsentTarget || !this.consentTarget.checked ||
        this.selectedPresetId !== "polish_clarity" || !validCopy ||
        this.sourceText === null || this.bodyTarget.value !== this.sourceText
    }
  }

  syncUndo() {
    if (this.undoRecord && this.bodyTarget.value !== this.undoRecord.after) {
      // A later human edit wins. Never overwrite it with an obsolete undo.
      this.undoRecord = null
    }
  }

  consentChanged() {
    this.updateButtons()
  }

  async generate() {
    if (!this.hasGenerateButtonTarget || !this.hasConsentTarget || this.generating ||
      this.generateButtonTarget.disabled || !this.consentTarget.checked) return
    const draft = this.editorTarget.value
    const priorBody = this.bodyTarget.value
    const preset = this.selectedPresetId
    if (!this.valid(draft) || priorBody !== this.sourceText ||
      preset !== "polish_clarity" || !this.element.dataset.aiDraftGenerateUrl) return

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || !globalThis.crypto?.randomUUID) {
      this.setStatus("Secure request unavailable. Original draft preserved.")
      return
    }

    this.generating = true
    this.updateButtons()
    this.generateButtonTarget.textContent = "Generating…"
    this.setStatus("Sending only this draft to xAI Grok 4.3. Nothing will be posted to the chat.")
    try {
      const response = await fetch(this.element.dataset.aiDraftGenerateUrl, {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ draft: {
          text: draft, preset_id: preset, consent: "1",
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
        this.editorTarget.value !== draft || this.selectedPresetId !== preset) {
        this.setStatus("Suggestion arrived, but draft changed. No text was overwritten.")
        return
      }
      this.editorTarget.value = result.text
      this.editorTouched = true
      this.describeWorkingCopy()
      this.setStatus("Grok suggestion received · cost $" +
        String(result.cost_usd || "unknown") + ". Review and click Apply; no message sent.")
    } catch (_) {
      this.setStatus("Grok request unavailable or declined. Draft retained. Check budget/provider status.")
    } finally {
      this.generating = false
      this.generateButtonTarget.textContent = "Generate suggestion"
      this.consentTarget.checked = false
      this.updateButtons()
    }
  }

  apply() {
    const proposed = this.editorTarget.value
    if (this.panelTarget.hidden || !this.valid(proposed) ||
      this.sourceText === null || this.bodyTarget.value !== this.sourceText ||
      proposed === this.bodyTarget.value) return

    const original = this.bodyTarget.value
    this.undoRecord = { before: original, after: proposed }
    this.replaceMessageText(proposed)
    this.sourceText = proposed
    this.editorTouched = false
    this.updateButtons()
    this.setStatus("Applied to the message. Nothing sent. Undo is available until you type again.")
    this.bodyTarget.focus()
  }

  undo() {
    const record = this.undoRecord
    if (!record || this.bodyTarget.value !== record.after) return
    this.undoRecord = null
    this.replaceMessageText(record.before)
    this.sourceText = record.before
    this.editorTarget.value = record.before
    this.editorTouched = false
    this.describeWorkingCopy()
    this.updateButtons()
    this.setStatus("Original wording restored. The message has not been sent.")
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
    this.setStatus("")
    this.updateButtons()
    this.toggleTarget.focus()
  }

  submitEnd(event) {
    if (!event.detail.success) return
    this.undoRecord = null
    this.panelTarget.hidden = true
    this.settingsPanelTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.editorTarget.value = ""
    this.sourceText = null
    this.editorTouched = false
    this.resultTarget.hidden = true
    this.counterTarget.textContent = ""
    this.setStatus("")
    this.updateButtons()
    // Canonical message-composer owns focus and all send-side mutations.
  }
}
