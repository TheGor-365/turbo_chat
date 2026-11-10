import { Controller } from "@hotwired/stimulus"

// H3e: local draft + opt-in, single-request Grok suggestion.
// Changes require Apply; sending remains a distinct user action.
const GENERATE_LABELS = Object.freeze({
  polish_clarity: "Improve with Grok",
  professional_client_reply: "Draft client reply with Grok",
  friendly: "Rewrite with Grok",
  concise: "Shorten with Grok",
  translate_preserving_tone: "Translate with Grok",
  technical_summary: "Summarize with Grok"
})
const TRANSLATION_ID = "translate_preserving_tone"
const SUPPORTED_LANGUAGES = Object.freeze(["en", "ru", "hy"])
const MAX_CHARS = 5000
const MAX_BYTES = 20000
const CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
const EMAIL = /\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b/i
const POSSIBLE_TOKEN = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,})\b/

export default class extends Controller {
  static targets = [
    "body", "toggle", "panel", "preset", "editor",
    "result", "status", "counter", "apply", "undo",
    "settingsPanel", "roomFeedback", "presetBadge", "browserName",
    "spellToggle", "spellState", "autoIndicator", "aiIndicator", "spellIndicator", "spellIndicatorLabel",
    "generateButton", "generateLabel", "comparison", "originalText",
    "editorLabel", "styleLabel", "styleDetails", "quickUndo", "backdrop", "providerCost",
    "translationControls", "targetLocale"
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
    this.boundSheetKeydown = event => this.sheetKeydown(event)
    document.addEventListener("keydown", this.boundSheetKeydown)
    this.boundPositionSheet = () => this.positionSheet()
    window.addEventListener("resize", this.boundPositionSheet)
    this.syncSheet()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundSheetKeydown)
    window.removeEventListener("resize", this.boundPositionSheet)
    window.clearTimeout(this.sheetCloseTimer)
    // Turbo navigation must never leave a modal in the browser top layer.
    for (const sheet of [this.panelTarget, this.settingsPanelTarget]) {
      if (sheet.open) sheet.close()
    }
    document.body.classList.remove("sd-ai-sheet-open")
  }

  get activeSheet() {
    if (!this.panelTarget.hidden) return this.panelTarget
    if (!this.settingsPanelTarget.hidden) return this.settingsPanelTarget
    return null
  }

  positionSheet() {
    const room = document.querySelector("#room_container")
    if (!room) return
    const bounds = room.getBoundingClientRect()
    const gutter = window.innerWidth <= 600 ? 10 : 16
    const left = Math.max(gutter, bounds.left + gutter)
    const right = Math.max(gutter, window.innerWidth - bounds.right + gutter)
    const top = Math.max(gutter, Math.min(window.innerHeight - 110, bounds.top + gutter))
    for (const sheet of [this.panelTarget, this.settingsPanelTarget]) {
      sheet.style.setProperty("--sd-ai-room-left", Math.round(left) + "px")
      sheet.style.setProperty("--sd-ai-room-right", Math.round(right) + "px")
      sheet.style.setProperty("--sd-ai-room-top", Math.round(top) + "px")
    }
  }

  syncSheet() {
    this.positionSheet()
    // A native modal dialog escapes transformed/overflow-clipped chat containers
    // via the browser top layer. Close the previous view before opening another.
    for (const sheet of [this.panelTarget, this.settingsPanelTarget]) {
      if (sheet.hidden && sheet.open) sheet.close()
    }
    const active = this.activeSheet
    if (active && !active.open) active.showModal()
    this.backdropTarget.hidden = !active
    document.body.classList.toggle("sd-ai-sheet-open", Boolean(active))
  }

  dismissOnBackdrop(event) {
    // Native ::backdrop clicks dispatch on the dialog itself; clicks within
    // the actual sheet must never discard an in-progress working copy.
    if (event.target !== event.currentTarget) return
    const bounds = event.currentTarget.getBoundingClientRect()
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) this.close()
  }

  sheetKeydown(event) {
    const sheet = this.activeSheet
    if (!sheet) return
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }
    if (event.key !== "Tab") return
    const focusable = Array.from(sheet.querySelectorAll(
      'button:not([disabled]):not([hidden]), textarea:not([disabled]), input:not([disabled]), summary, a[href]'
    )).filter(node => node.getClientRects().length && !node.closest("[hidden]"))
    if (!focusable.length) return
    const first = focusable[0], last = focusable[focusable.length - 1]
    if (!sheet.contains(document.activeElement) || (event.shiftKey && document.activeElement === first)) {
      event.preventDefault()
      ;(event.shiftKey ? last : first).focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
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
    this.syncSheet()
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.roomFeedbackTarget.textContent = ""
    this.settingsPanelTarget.querySelector("button[data-preset-id]")?.focus()
  }

  showEditor() {
    this.settingsPanelTarget.hidden = true
    this.panelTarget.hidden = false
    this.syncSheet()
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
    if (!this.panelTarget.hidden) this.setStatus("")
  }

  selectVisualState() {
    this.presetTargets.forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.presetId === this.selectedPresetId))
    })
    const active = this.presetTargets.find(button => button.dataset.presetId === this.selectedPresetId)
    const label = active?.textContent.trim() || "Polish / Clarity"
    if (this.hasStyleLabelTarget) this.styleLabelTarget.textContent = label
    if (this.hasTranslationControlsTarget) {
      const translating = this.selectedPresetId === TRANSLATION_ID
      this.translationControlsTarget.hidden = !translating
      this.targetLocaleTarget.disabled = !translating
    }
    if (this.hasGenerateLabelTarget && !this.generating) {
      this.generateLabelTarget.textContent =
        GENERATE_LABELS[this.selectedPresetId] || GENERATE_LABELS.polish_clarity
    }
  }

  changeTargetLocale() {
    // No stored locale; translation target is an explicit per-draft choice.
    this.updateButtons()
    this.setStatus("")
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
        ? ""
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
      const translationReady = this.selectedPresetId !== TRANSLATION_ID ||
        (this.hasTargetLocaleTarget && SUPPORTED_LANGUAGES.includes(this.targetLocaleTarget.value))
      this.generateButtonTarget.disabled = this.generating || this.panelTarget.hidden ||
        !validCopy || !translationReady ||
        this.sourceText === null || this.bodyTarget.value !== this.sourceText
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
    const selectedPreset = this.selectedPresetId
    const selectedLocale = selectedPreset === TRANSLATION_ID ? this.targetLocaleTarget.value : null
    if (!Object.hasOwn(GENERATE_LABELS, selectedPreset)) return
    if (selectedPreset === TRANSLATION_ID && !SUPPORTED_LANGUAGES.includes(selectedLocale)) return
    if (!this.valid(draft) || priorBody !== this.sourceText ||
      !this.element.dataset.aiDraftGenerateUrl) return

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || !globalThis.crypto?.randomUUID) {
      this.setStatus("Secure request unavailable. Original draft preserved.")
      return
    }

    this.generating = true
    if (this.hasProviderCostTarget) {
      this.providerCostTarget.hidden = true
      this.providerCostTarget.textContent = ""
    }
    this.updateButtons()
    if (this.hasGenerateLabelTarget) this.generateLabelTarget.textContent = "Working…"
    this.setStatus("Preparing suggestion…")
    try {
      const payload = {
        text: draft, preset_id: selectedPreset, consent: "1",
        request_id: globalThis.crypto.randomUUID()
      }
      if (selectedPreset === TRANSLATION_ID) payload.target_locale = selectedLocale
      const response = await fetch(this.element.dataset.aiDraftGenerateUrl, {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ draft: payload })
      })
      if (!response.ok) throw new Error("HTTP " + response.status)
      const result = await response.json()
      if (typeof result.text !== "string" || !this.valid(result.text)) {
        throw new Error("Invalid provider result")
      }
      // Human typing or changing room/preset wins over a late response.
      if (this.panelTarget.hidden || this.bodyTarget.value !== priorBody ||
        this.editorTarget.value !== draft ||
        this.selectedPresetId !== selectedPreset ||
        (selectedPreset === TRANSLATION_ID && this.targetLocaleTarget.value !== selectedLocale)) {
        this.setStatus("Suggestion arrived, but draft changed. No text was overwritten.")
        return
      }
      const reportedCost = String(result.cost_usd ?? "unknown")
      if (this.hasProviderCostTarget) {
        this.providerCostTarget.textContent = "Reported provider cost: $" + reportedCost
        this.providerCostTarget.hidden = false
      }
      if (result.text === draft) {
        // A successful billable API call does not guarantee any edit.
        // The original draft is preserved; no meaningless Apply is offered.
        this.setStatus("No changes · Not sent")
        return
      }
      this.editorTarget.value = result.text
      this.editorTouched = true
      this.originalTextTarget.textContent = draft
      this.comparisonTarget.hidden = false
      this.editorLabelTarget.textContent = "Suggested"
      this.resizeEditor()
      this.setStatus("Suggested edit · Review before Apply")
    } catch (_) {
      this.setStatus("Grok unavailable. Draft kept; do not retry automatically.")
    } finally {
      this.generating = false
      if (this.hasGenerateLabelTarget) {
        this.generateLabelTarget.textContent =
          GENERATE_LABELS[this.selectedPresetId] || GENERATE_LABELS.polish_clarity
      }
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
      this.syncSheet()
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
    if (event && ["keydown", "cancel"].includes(event.type)) event.preventDefault()
    if (this.closingSheet) return
    const active = this.activeSheet
    if (active?.open && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.closingSheet = active
      active.dataset.closing = "true"
      this.sheetCloseTimer = window.setTimeout(() => {
        delete active.dataset.closing
        this.closingSheet = null
        this.finishClose()
      }, 180)
      return
    }
    this.finishClose()
  }

  finishClose() {
    this.panelTarget.hidden = true
    this.settingsPanelTarget.hidden = true
    this.syncSheet()
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.editorTarget.value = ""
    this.sourceText = null
    this.editorTouched = false
    this.resultTarget.hidden = true
    this.counterTarget.textContent = ""
    this.clearComparison()
    this.setStatus("")
    if (this.hasProviderCostTarget) {
      this.providerCostTarget.textContent = ""
      this.providerCostTarget.hidden = true
    }
    this.updateButtons()
    this.toggleTarget.focus()
  }

  submitEnd(event) {
    if (!event.detail.success) return
    this.undoRecord = null
    this.generatedApplied = false
    this.panelTarget.hidden = true
    this.settingsPanelTarget.hidden = true
    this.syncSheet()
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
