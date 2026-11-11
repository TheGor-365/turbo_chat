import { Controller } from "@hotwired/stimulus"
import { renderDeliverablePreview, safeSourceLink } from "../lib/ai_deliverable_preview"
import { localTemplateKey, validAuthorNote, normalizedTemplate, readLocalTemplates,
  writeLocalTemplates, MAX_TEMPLATES } from "../lib/local_ai_templates"

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
    "settingsPanel", "roomFeedback", "presetBadge", "browserName", "roomStyleLabel",
    "spellToggle", "spellState", "autoIndicator", "aiIndicator", "spellIndicator", "spellIndicatorLabel",
    "generateButton", "generateLabel", "comparison", "originalText",
    "editorLabel", "styleLabel", "styleDetails", "quickUndo", "backdrop", "providerCost",
    "translationControls", "targetLocale",
    "smartReplyToggle", "smartReplyState", "smartReplyStatus",
    "replyButton", "replyLabel", "contextSources",
    "taskControls", "taskSelect", "taskButton", "taskLabel", "contextAvailability",
    "taskPicker", "taskOption", "taskSummaryLabel",
    "consentSummary", "consentCount", "consentCompact", "consentMembers",
    "preview", "previewBody", "previewSources", "copyButton", "exportButton", "previewFeedback",
    "previewDraftButton",
    "customHint", "templateName", "templateList", "templateFeedback",
    "sourceReviewButton", "sourceReviewStatus", "sourceReviewList"
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
    this.contextReady = false
    this.contextGranted = false
    this.contextStatusError = false
    this.consentReadVersion = 0
    this.consentUpdating = false
    this.consentSignature = null
    this.previewKind = null
    this.previewSourceLinks = {}
    this.sourceReviewEpoch = 0
    this.reviewingSources = false
    this.sourceSelectionToken = null
    this.sourceReviewRows = []
    this.sourceSelectionIds = []
    this.selectedTemplateName = null
    this.localTemplates = []
    this.loadLocalTemplates()
    this.selectVisualState()
    this.renderRoomState()
    this.browserNameTarget.textContent = this.detectBrowser()
    if (this.hasTaskSelectTarget) this.changeContextTask()
    this.updateButtons()
    this.boundSheetKeydown = event => this.sheetKeydown(event)
    document.addEventListener("keydown", this.boundSheetKeydown)
    this.boundPositionSheet = () => this.positionSheet()
    window.addEventListener("resize", this.boundPositionSheet)
    this.syncSheet()
    if (this.hasSmartReplyToggleTarget) {
      this.loadSmartReplyStatus()
      // Authorized room metadata only; never polls message content.
      this.consentTimer = window.setInterval(() => {
        if (!document.hidden && !this.consentUpdating) this.loadSmartReplyStatus()
      }, 6000)
      this.consentVisibility = () => {
        if (!document.hidden && !this.consentUpdating) this.loadSmartReplyStatus()
      }
      document.addEventListener("visibilitychange", this.consentVisibility)
    }
  }

  disconnect() {
    this.sourceReviewEpoch += 1
    document.removeEventListener("keydown", this.boundSheetKeydown)
    window.removeEventListener("resize", this.boundPositionSheet)
    window.clearTimeout(this.sheetCloseTimer)
    window.clearInterval(this.consentTimer)
    if (this.consentVisibility) document.removeEventListener("visibilitychange", this.consentVisibility)
    this.consentReadVersion += 1
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
      if (this.hasTaskPickerTarget && this.taskPickerTarget.open &&
          this.taskPickerTarget.contains(event.target)) {
        this.taskPickerTarget.open = false
        this.taskPickerTarget.querySelector("summary")?.focus()
        return
      }
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

  get templateStorageKey() {
    return localTemplateKey(this.element.dataset.aiDraftUserId, this.element.dataset.aiDraftRoomId)
  }

  loadLocalTemplates() {
    if (!this.hasTemplateListTarget) return
    const loaded = readLocalTemplates(this.templateStorageKey)
    this.localTemplates = loaded || []
    this.renderLocalTemplates()
    if (!loaded) this.templateFeedbackTarget.textContent =
      "Local templates unavailable. You can still type an instruction for one request."
  }

  renderLocalTemplates() {
    if (!this.hasTemplateListTarget) return
    const fragment = document.createDocumentFragment()
    this.localTemplates.forEach((entry, index) => {
      const item = document.createElement("li")
      item.className = "sd-ai-local-template"
      const name = document.createElement("span")
      name.className = "sd-ai-local-template__name"
      name.textContent = entry.name
      const use = document.createElement("button")
      use.type = "button"
      use.textContent = "Use"
      use.setAttribute("aria-label", "Use template " + entry.name)
      use.addEventListener("click", () => this.chooseLocalTemplate(index))
      const remove = document.createElement("button")
      remove.type = "button"
      remove.textContent = "Delete"
      remove.className = "sd-ai-local-template__delete"
      remove.setAttribute("aria-label", "Delete template " + entry.name)
      remove.addEventListener("click", () => this.deleteLocalTemplate(index))
      item.append(name, use, remove)
      fragment.append(item)
    })
    this.templateListTarget.replaceChildren(fragment)
  }

  editCustomHint() {
    this.clearSourceReview()
    // Explicit Save is the only persistence path.
    this.templateFeedbackTarget.textContent = this.customHintTarget.value.trim()
      ? "Instruction changed locally · Not sent."
      : "No custom instruction. The working copy remains an optional author note."
  }

  chooseLocalTemplate(index) {
    const entry = this.localTemplates[index]
    if (!entry || !this.hasCustomHintTarget) return
    this.customHintTarget.value = entry.instruction
    this.clearSourceReview()
    this.templateNameTarget.value = entry.name
    this.selectedTemplateName = entry.name
    this.templateFeedbackTarget.textContent = "Loaded · edit, then Save to update. Generate is separate."
    this.customHintTarget.focus()
  }

  newLocalTemplate() {
    this.selectedTemplateName = null
    this.templateNameTarget.value = ""
    this.templateFeedbackTarget.textContent = "New template name needed; current instruction is unchanged."
    this.templateNameTarget.focus()
  }

  saveLocalTemplate() {
    if (!this.hasCustomHintTarget || this.generating) return
    const entry = normalizedTemplate(this.templateNameTarget.value, this.customHintTarget.value)
    if (!entry) {
      this.templateFeedbackTarget.textContent =
        "Name 1–60 characters; instruction 1–700 characters / 2800 bytes without emails, tokens or control characters."
      return
    }
    const existing = this.localTemplates.findIndex(e =>
      e.name.toLocaleLowerCase() === entry.name.toLocaleLowerCase())
    const selected = this.selectedTemplateName === null ? -1 :
      this.localTemplates.findIndex(e => e.name === this.selectedTemplateName)
    if (existing >= 0 && existing !== selected) {
      this.templateFeedbackTarget.textContent = "That name already exists. Select the template to edit it."
      return
    }
    const next = [...this.localTemplates]
    if (selected >= 0) next[selected] = entry
    else if (next.length >= MAX_TEMPLATES) {
      this.templateFeedbackTarget.textContent = "At most 12 templates per room on this device."
      return
    } else next.push(entry)
    if (!writeLocalTemplates(this.templateStorageKey, next)) {
      this.templateFeedbackTarget.textContent = "Could not save locally; current instruction is preserved."
      return
    }
    this.localTemplates = next
    this.selectedTemplateName = entry.name
    this.templateNameTarget.value = entry.name
    this.renderLocalTemplates()
    this.templateFeedbackTarget.textContent = "Saved on this device for this room · Not sent."
  }

  deleteLocalTemplate(index) {
    const entry = this.localTemplates[index]
    if (!entry || this.generating || !window.confirm("Delete local template “" + entry.name + "”?")) return
    const next = this.localTemplates.filter((_, i) => i !== index)
    if (!writeLocalTemplates(this.templateStorageKey, next)) {
      this.templateFeedbackTarget.textContent = "Delete failed; saved template kept."
      return
    }
    this.localTemplates = next
    if (this.selectedTemplateName === entry.name) {
      this.selectedTemplateName = null
      this.templateNameTarget.value = ""
    }
    this.renderLocalTemplates()
    this.templateFeedbackTarget.textContent =
      "Deleted locally. The current instruction is unchanged and was not sent."
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
      (this.hasGenerateButtonTarget ? ". Manual Grok uses the selected style." : "")
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
    if (this.hasSmartReplyToggleTarget) this.loadSmartReplyStatus()
    this.settingsPanelTarget.querySelector("button[data-preset-id]")?.focus()
  }

  showEditor() {
    this.settingsPanelTarget.hidden = true
    this.panelTarget.hidden = false
    this.syncSheet()
    this.toggleTarget.setAttribute("aria-expanded", "true")
    if (this.sourceText === null) this.refresh()
    else this.updateButtons()
    if (this.hasSmartReplyToggleTarget) this.loadSmartReplyStatus()
    this.resizeEditor()
    this.editorTarget.focus()
  }

  closeSettings(event) { this.close(event) }

  async loadSmartReplyStatus() {
    const url = this.element.dataset.aiDraftContextStatusUrl
    if (!url || !this.hasSmartReplyToggleTarget || this.consentUpdating) return
    const version = ++this.consentReadVersion
    try {
      const response = await fetch(url, {
        credentials: "same-origin", cache: "no-store",
        headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error("Context not available")
      const data = await response.json()
      if (version !== this.consentReadVersion || this.consentUpdating) return
      this.applySmartReplyStatus(data)
    } catch (_) {
      if (version !== this.consentReadVersion || this.consentUpdating) return
      this.contextReady = false
      this.contextBlockReason = null
      this.contextStatusError = true
      this.smartReplyToggleTarget.disabled = true
      this.smartReplyStatusTarget.textContent = "Cannot verify room permissions. Context AI is blocked until status is refreshed."
      this.renderConsentRoster({ participants: [], available: false, ready: false, reason: "status_error" })
      this.updateButtons()
      this.renderPreview()
    }
  }

  applySmartReplyStatus(data) {
    const previouslyReady = this.contextReady
    this.contextStatusError = false
    this.contextBlockReason = data.reason || null
    this.contextGranted = data.enabled === true
    this.contextReady = data.ready === true && data.available === true
    this.renderConsentRoster(data)
    if (this.hasSmartReplyToggleTarget) {
      this.smartReplyToggleTarget.disabled = data.available !== true
      this.smartReplyToggleTarget.setAttribute("aria-checked", String(this.contextGranted))
      this.smartReplyStateTarget.textContent = this.contextGranted ? "ON" : "OFF"
      const granted = Number(data.granted) || 0
      const members = Number(data.members) || 0
      this.smartReplyStatusTarget.textContent =
        data.reason === "not_enough_members"
          ? "At least two current members are required. Invite a participant and wait for acceptance."
          : data.reason === "too_many_members"
            ? "Context AI supports private rooms with at most ten members."
            : data.available !== true
              ? "Context AI is unavailable in this environment."
              : this.contextReady
                ? "Ready. Only your explicit request may send approved context to xAI."
                : this.contextGranted
                  ? "Awaiting other participants (" + granted + " / " + members + ")."
                  : "Off. Your messages cannot be sent as contextual AI evidence."
    }
    this.updateButtons()
    if (previouslyReady !== this.contextReady) {
      this.clearSourceReview()
      this.renderPreview()
    }
  }

  renderConsentRoster(data) {
    if (!this.hasConsentCountTarget || !this.hasConsentMembersTarget ||
        !this.hasConsentCompactTarget || !this.hasConsentSummaryTarget) return

    const raw = Array.isArray(data.participants) ? data.participants : []
    const members = raw.filter(member =>
      member && Number.isSafeInteger(member.id) && member.id > 0 &&
      typeof member.name === "string" && typeof member.enabled === "boolean"
    )
    const count = Number(data.members) || members.length
    const granted = Number(data.granted) || 0
    const ready = data.ready === true && data.available === true
    this.consentCountTarget.textContent = data.reason === "not_enough_members"
      ? "AI context · needs 2 members"
      : data.reason === "too_many_members"
        ? "AI context · too many members"
        : data.reason === "status_error" || data.available !== true
          ? "AI context · unavailable"
          : "AI context · " + granted + "/" + count + (ready ? " ready" : " waiting")
    this.consentSummaryTarget.dataset.ready = String(ready)

    // Use only textContent; other members' profile labels are not trusted HTML.
    const signature = JSON.stringify(members.map(member =>
      [member.id, member.name, member.enabled]))
    if (signature === this.consentSignature) return
    this.consentSignature = signature
    const roster = document.createDocumentFragment()
    const compact = document.createDocumentFragment()
    const viewer = Number(this.element.dataset.aiDraftUserId)
    members.forEach(member => {
      const description = member.name + (member.id === viewer ? " (you)" : "")
      const item = document.createElement("li")
      item.className = "sd-ai-member"
      const name = document.createElement("span")
      name.className = "sd-ai-member-name"
      name.textContent = description
      const state = document.createElement("span")
      state.className = member.enabled ? "sd-ai-member-state is-on" : "sd-ai-member-state is-off"
      state.textContent = member.enabled ? "✓ ON" : "– OFF"
      item.append(name, state)
      roster.append(item)

      const chip = document.createElement("span")
      chip.className = member.enabled ? "sd-ai-member-chip is-on" : "sd-ai-member-chip is-off"
      chip.setAttribute("role", "listitem")
      chip.setAttribute("aria-label", description + ": AI room context " +
        (member.enabled ? "ON" : "OFF"))
      chip.title = description + ": AI room context " + (member.enabled ? "ON" : "OFF")
      const glyph = document.createElement("span")
      glyph.className = "sd-ai-consent-dot"
      glyph.textContent = member.enabled ? "✓" : "–"
      glyph.setAttribute("aria-hidden", "true")
      chip.append(glyph, document.createTextNode(description))
      compact.append(chip)
    })
    if (members.length === 0) {
      const item = document.createElement("li")
      item.textContent = "Member states unavailable. Context AI remains blocked."
      roster.append(item)
    }
    this.consentMembersTarget.replaceChildren(roster)
    this.consentCompactTarget.replaceChildren(compact)
  }

  async toggleSmartReplies() {
    if (!this.hasSmartReplyToggleTarget || this.smartReplyToggleTarget.disabled) return
    const url = this.element.dataset.aiDraftContextConsentUrl
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!url || !csrf) return
    this.smartReplyToggleTarget.disabled = true
    this.consentUpdating = true
    this.consentReadVersion += 1
    try {
      const response = await fetch(url, {
        method: "PATCH", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ consent: { enabled: this.contextGranted ? "0" : "1" } })
      })
      if (!response.ok) throw new Error("Consent update rejected")
      const responseData = await response.json()
      this.consentUpdating = false
      this.applySmartReplyStatus(responseData)
    } catch (_) {
      this.consentUpdating = false
      this.smartReplyStatusTarget.textContent = "Couldn't save permission. Rechecking your actual room status."
      this.smartReplyToggleTarget.disabled = true
      await this.loadSmartReplyStatus()
    }
  }

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
    if (this.hasRoomStyleLabelTarget) this.roomStyleLabelTarget.textContent = label
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
    this.clearSourceReview()
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
    this.clearSourceReview()
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
    this.clearSourceReview()
    this.editorTouched = true
    this.resizeEditor()
    this.describeWorkingCopy()
    this.updateButtons()
    this.renderPreview()
  }

  resizeEditor() {
    const node = this.editorTarget
    node.style.height = "auto"
    node.style.height = Math.min(node.scrollHeight, 236) + "px"
  }

  clearComparison() {
    this.clearPreview()
    if (this.hasComparisonTarget) this.comparisonTarget.hidden = true
    if (this.hasOriginalTextTarget) this.originalTextTarget.textContent = ""
    if (this.hasEditorLabelTarget) this.editorLabelTarget.textContent = "Draft"
    if (this.hasContextSourcesTarget) {
      this.contextSourcesTarget.textContent = ""
      this.contextSourcesTarget.hidden = true
    }
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
    if (this.hasPreviewDraftButtonTarget) {
      this.previewDraftButtonTarget.disabled = this.panelTarget.hidden || !validCopy
    }
    this.applyTarget.disabled = this.panelTarget.hidden || !validCopy ||
      this.sourceText === null || this.bodyTarget.value !== this.sourceText ||
      this.editorTarget.value === this.bodyTarget.value
    this.syncUndo()
    this.syncPreviewActions()
    this.undoTarget.hidden = !this.undoRecord
    this.undoTarget.disabled = !this.undoRecord ||
      this.bodyTarget.value !== this.undoRecord.after
    if (this.hasGenerateButtonTarget) {
      // A reviewed contextual suggestion can be refined with another,
      // separately authorized own-draft Grok request before Apply.
      this.generateButtonTarget.hidden = false
      const translationReady = this.selectedPresetId !== TRANSLATION_ID ||
        (this.hasTargetLocaleTarget && SUPPORTED_LANGUAGES.includes(this.targetLocaleTarget.value))
      this.generateButtonTarget.disabled = this.generating || this.panelTarget.hidden ||
        !validCopy || !translationReady ||
        this.sourceText === null || this.bodyTarget.value !== this.sourceText
    }
    const contextCopySafe = this.sourceText !== null &&
      this.bodyTarget.value === this.sourceText &&
      (this.hasComparisonTarget ? this.comparisonTarget.hidden : true)
    const contextualCandidate = this.contextReady && !this.panelTarget.hidden &&
      contextCopySafe && !this.reviewingSources
    if (this.hasSourceReviewButtonTarget) {
      this.sourceReviewButtonTarget.disabled =
        this.generating || this.reviewingSources || !this.contextReady ||
        this.panelTarget.hidden || !contextCopySafe
      this.sourceReviewListTarget.querySelectorAll("input[type=checkbox]").forEach(input => {
        input.disabled = this.generating || !this.contextReady || this.panelTarget.hidden
      })
    }
    const selectedSourcesValid = !this.sourceSelectionToken ||
      (this.sourceSelectionIds.length > 0 &&
        this.sourceReviewRows.some(row => this.sourceSelectionIds.includes(row.id) &&
          row.speaker !== "you"))
    // Expose controls in their disabled state; the server always rechecks consent.
    if (this.hasReplyButtonTarget) {
      this.replyButtonTarget.disabled = this.generating || !contextualCandidate || !selectedSourcesValid
    }
    if (this.hasTaskControlsTarget) {
      this.taskButtonTarget.disabled = this.generating || !contextualCandidate ||
        !this.taskSelectTarget.value || !selectedSourcesValid
    }
    if (this.hasContextAvailabilityTarget) {
      this.contextAvailabilityTarget.textContent = this.contextStatusError
        ? "Cannot check room permission. Requests are blocked; reopen Room settings to retry."
        : this.contextBlockReason === "not_enough_members"
          ? "Private conversation requires at least two members. Invite someone and wait for acceptance."
          : this.contextBlockReason === "too_many_members"
            ? "Private conversation exceeds the ten-member AI context limit."
            : !this.contextGranted
          ? "Smart replies OFF. Open Room settings to allow use of your messages."
          : !this.contextReady
            ? "Awaiting consent from every current participant. Check Room settings."
            : !contextCopySafe
              ? "Review, Apply or Reload the current suggestion before another context request."
              : "Context ready. Each Grok action is paid; nothing is sent automatically."
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
    // The single-purpose button gives request-specific approval; cost and
    // data disclosure are in Details. No persistent spend consent exists.
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
      this.preparePreview("manual", {})
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

  chooseContextTask(event) {
    if (this.generating || !this.hasTaskSelectTarget || !this.hasTaskPickerTarget) return
    const selected = event.currentTarget.dataset.taskKind
    if (!Array.from(this.taskSelectTarget.options).some(option =>
      option.value === selected && selected !== "")) return
    this.taskSelectTarget.value = selected
    this.changeContextTask()
    this.taskPickerTarget.open = false
    this.taskPickerTarget.querySelector("summary")?.focus()
  }

  changeContextTask() {
    if (this.hasTaskSummaryLabelTarget && this.hasTaskSelectTarget) {
      const selected = this.taskSelectTarget.selectedOptions[0]
      this.taskSummaryLabelTarget.textContent =
        selected && selected.value ? selected.textContent.trim() : "Choose a task"
    }
    if (this.hasTaskOptionTarget) {
      this.taskOptionTargets.forEach(button => {
        button.setAttribute("aria-pressed",
          String(button.dataset.taskKind === this.taskSelectTarget.value))
      })
    }
    this.updateButtons()
    this.setStatus("")
  }

  clearSourceReview() {
    this.sourceReviewEpoch += 1
    this.sourceSelectionToken = null
    this.sourceSelectionIds = []
    this.sourceReviewRows = []
    if (!this.hasSourceReviewListTarget) return
    this.sourceReviewListTarget.replaceChildren()
    this.sourceReviewStatusTarget.textContent =
      "Snapshot cleared. Review sources again to inspect the current permitted context."
  }

  changeSourceSelection() {
    if (!this.sourceSelectionToken || this.generating) return
    const ids = Array.from(this.sourceReviewListTarget.querySelectorAll("input[type=checkbox]:checked"))
      .map(input => Number(input.dataset.sourceId))
    this.sourceSelectionIds = ids
    const hasIncoming = this.sourceReviewRows.some(row =>
      ids.includes(row.id) && row.speaker !== "you")
    this.sourceReviewStatusTarget.textContent =
      ids.length + " of " + this.sourceReviewRows.length + " sources selected for a future manual Grok request. " +
      (hasIncoming ? "Only checked excerpts will be sent, after fresh room checks. Not sent." :
        "Include at least one incoming message to enable Generate.")
    this.updateButtons()
  }

  async reviewSources() {
    if (!this.hasSourceReviewButtonTarget || this.sourceReviewButtonTarget.disabled ||
        this.generating || !this.contextReady) return
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const url = this.element.dataset.aiDraftContextPreviewUrl
    const note = this.hasCustomHintTarget ? this.customHintTarget.value.trim() : ""
    const hint = note || this.editorTarget.value.trim()
    if (hint && !validAuthorNote(hint)) {
      this.sourceReviewStatusTarget.textContent = "Author note is invalid or contains private details."
      return
    }
    if (!csrf || !url) return
    const epoch = ++this.sourceReviewEpoch
    const bodyBefore = this.bodyTarget.value, copyBefore = this.editorTarget.value
    this.reviewingSources = true
    this.sourceSelectionToken = null
    this.sourceSelectionIds = []
    this.sourceReviewRows = []
    this.sourceReviewListTarget.replaceChildren()
    this.updateButtons()
    this.sourceReviewStatusTarget.textContent = "Reviewing selected sources locally…"
    try {
      const response = await fetch(url, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ preview: { hint } })
      })
      if (!response.ok) throw new Error(response.status === 429
        ? "Source preview rate limit reached. Nothing was sent to Grok."
        : "Source preview denied or unavailable. Verify consent and access.")
      const data = await response.json()
      if (epoch !== this.sourceReviewEpoch || this.panelTarget.hidden || !this.contextReady ||
          this.bodyTarget.value !== bodyBefore || this.editorTarget.value !== copyBefore ||
          (this.hasCustomHintTarget && this.customHintTarget.value.trim() !== note)) return
      if (!Array.isArray(data.sources) || !data.sources.length || data.sources.length > 9 ||
          typeof data.source_token !== "string" || data.source_token.length < 1 ||
          data.source_token.length > 4096)
        throw new Error("Invalid source preview response.")
      const labels = { latest_incoming: "Latest incoming", recent_turn: "Recent turn",
        keyword_match: "Older keyword match", context_fallback: "Context fallback" }
      const nodes = document.createDocumentFragment()
      for (const source of data.sources) {
        if (!Number.isSafeInteger(source.id) || source.id < 1 || typeof source.text !== "string" ||
            source.text.length > 420 || !Object.prototype.hasOwnProperty.call(labels, source.reason))
          throw new Error("Invalid source preview response.")
        if (source.speaker !== "you" &&
            !(typeof source.speaker === "string" && /^participant_[1-9]\d*$/.test(source.speaker)))
          throw new Error("Invalid source preview speaker.")
        const li = document.createElement("li")
        const label = document.createElement("label")
        label.className = "sd-ai-source-review__choice"
        const checkbox = document.createElement("input")
        checkbox.type = "checkbox"
        checkbox.checked = source.reason !== "context_fallback"
        checkbox.dataset.sourceId = String(source.id)
        checkbox.setAttribute("aria-label", "Include source M" + source.id + " in AI request")
        checkbox.addEventListener("change", () => this.changeSourceSelection())
        const labelText = document.createElement("strong")
        labelText.textContent = "M" + source.id + " · " + labels[source.reason] +
          (source.truncated ? " · shortened" : "")
        label.append(checkbox, labelText)
        li.append(label)
        const href = safeSourceLink(source.url, this.element.dataset.aiDraftRoomPath, String(source.id))
        if (href) {
          const link = document.createElement("a")
          link.href = href
          link.target = "_blank"
          link.rel = "noopener noreferrer"
          link.dataset.turbo = "false"
          link.textContent = "Open"
          link.setAttribute("aria-label", "Open source M" + source.id + " in a new tab")
          li.append(link)
        }
        const excerpt = document.createElement("p")
        excerpt.textContent = source.text
        li.append(excerpt)
        nodes.append(li)
      }
      const ids = data.sources.map(row => row.id)
      if (new Set(ids).size !== ids.length)
        throw new Error("Duplicate source IDs in preview.")
      this.sourceSelectionToken = data.source_token
      this.sourceReviewRows = data.sources.map(row => ({ id: row.id, speaker: row.speaker }))
      this.sourceSelectionIds = data.sources.filter(row => row.reason !== "context_fallback")
        .map(row => row.id)
      this.sourceReviewListTarget.replaceChildren(nodes)
      this.changeSourceSelection()
      this.sourceReviewStatusTarget.textContent +=
        " Low-relevance context fallback messages are unchecked by default. " +
        "Selection expires after ten minutes; review again if context changes. " +
        "Lexical matching is not fact-checking."
    } catch (error) {
      if (epoch === this.sourceReviewEpoch) {
        this.sourceReviewListTarget.replaceChildren()
        this.sourceSelectionToken = null
        this.sourceSelectionIds = []
        this.sourceReviewRows = []
        this.sourceReviewStatusTarget.textContent = error.message || "Preview unavailable."
      }
    } finally {
      this.reviewingSources = false
      this.updateButtons()
    }
  }

  async suggestReply() {
    if (!this.hasReplyButtonTarget || this.replyButtonTarget.disabled) return
    await this.requestContextResult({ kind: null, label: "Suggested reply" })
  }

  async generateContextTask() {
    if (!this.hasTaskButtonTarget || this.taskButtonTarget.disabled) return
    const kind = this.taskSelectTarget.value
    const allowed = ["conversation_summary", "action_items", "client_brief",
      "client_proposal", "content_outline"]
    if (!allowed.includes(kind)) return
    await this.requestContextResult({ kind, label: "Context task" })
  }

  async requestContextResult({ kind, label }) {
    // One real user click permits one billable request. Never publish chat
    // messages or retry automatically. The server checks each member's grant.
    if (!this.contextReady || this.generating ||
        this.panelTarget.hidden || this.sourceText === null ||
        this.bodyTarget.value !== this.sourceText ||
        (this.hasComparisonTarget && !this.comparisonTarget.hidden)) return
    const url = kind ? this.element.dataset.aiDraftContextTaskUrl :
      this.element.dataset.aiDraftContextReplyUrl
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!url || !csrf || !globalThis.crypto?.randomUUID) {
      this.setStatus("Secure request unavailable. Nothing sent.")
      return
    }

    const priorBody = this.bodyTarget.value
    const priorCopy = this.editorTarget.value
    const customNote = this.hasCustomHintTarget ? this.customHintTarget.value : ""
    const hint = customNote.trim() || priorCopy.trim()
    const selectedTask = kind && this.taskSelectTarget.value
    if (hint && !validAuthorNote(hint)) {
      this.setStatus("Author note must be at most 700 characters / 2800 bytes without detected private details.")
      return
    }

    const selectionToken = this.sourceSelectionToken
    const selectionIds = [...this.sourceSelectionIds]
    const selectionEpoch = this.sourceReviewEpoch
    if (selectionToken) {
      if (!selectionIds.length || !this.sourceReviewRows.some(row =>
          selectionIds.includes(row.id) && row.speaker !== "you")) {
        this.setStatus("Select at least one incoming message before a paid request.")
        return
      }
    }
    const payload = { hint, consent: "1", request_id: globalThis.crypto.randomUUID() }
    if (selectionToken) {
      payload.source_token = selectionToken
      payload.source_ids = selectionIds
    }
    if (kind) payload.kind = kind
    this.generating = true
    this.updateButtons()
    if (kind) this.taskLabelTarget.textContent = "Working…"
    else this.replyLabelTarget.textContent = "Preparing reply…"
    this.setStatus("Using permitted room context…")
    if (this.hasProviderCostTarget) {
      this.providerCostTarget.hidden = true
      this.providerCostTarget.textContent = ""
    }
    try {
      const response = await fetch(url, {
        method: "POST", credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify(kind ? { task: payload } : { reply: payload })
      })
      if (!response.ok) {
        if (response.status === 422) throw new Error(selectionToken
          ? "Source review expired, context changed or consent withdrawn. Review sources again before Generate."
          : "Check participant consent and the requested task.")
        if (response.status === 429) throw new Error("AI request or spending limit reached. Do not retry automatically.")
        if (response.status === 403) throw new Error("You no longer have access to this room.")
        if (response.status === 503) throw new Error("Context AI is disabled or the xAI provider is unavailable.")
        throw new Error("AI request failed (HTTP " + response.status + ").")
      }
      const suggestion = await response.json()
      if (!this.valid(suggestion.text) ||
          (kind && suggestion.kind !== kind) ||
          !Array.isArray(suggestion.source_message_ids) ||
          !suggestion.source_message_ids.length ||
          !suggestion.source_message_ids.every(id => Number.isSafeInteger(id) && id > 0)) {
        throw new Error("Unusable response from AI provider.")
      }
      if (this.panelTarget.hidden || priorBody !== this.bodyTarget.value ||
          priorCopy !== this.editorTarget.value ||
          (this.hasCustomHintTarget && customNote !== this.customHintTarget.value) ||
          selectionEpoch !== this.sourceReviewEpoch ||
          !this.contextReady ||
          (kind && this.taskSelectTarget.value !== selectedTask)) {
        this.setStatus("Response arrived after an edit. Your text was not overwritten.")
        return
      }

      this.clearSourceReview()
      this.sourceText = priorBody
      this.editorTarget.value = suggestion.text
      this.editorTouched = true
      this.resultTarget.hidden = false
      this.originalTextTarget.textContent = priorCopy || "No previous draft"
      this.comparisonTarget.hidden = false
      this.editorLabelTarget.textContent = label
      this.resizeEditor()
      this.counterTarget.textContent = Array.from(suggestion.text).length + " / 5000"
      this.preparePreview(kind || "reply", suggestion.source_links || {})
      if (this.hasContextSourcesTarget) {
        this.contextSourcesTarget.textContent =
          "Source messages in this room: " +
          suggestion.source_message_ids.map(id => "#" + id).join(", ") +
          ". Omitted among scanned messages: " +
          (Number(suggestion.omitted_context_messages) || 0) + "."
        this.contextSourcesTarget.hidden = false
      }
      if (this.hasProviderCostTarget) {
        this.providerCostTarget.textContent = "Reported provider cost: $" +
          String(suggestion.cost_usd ?? "unknown")
        this.providerCostTarget.hidden = false
      }
      this.setStatus(label + " · review or edit, Apply, then Send manually.")
    } catch (error) {
      this.setStatus(error.message || "Context AI unavailable; nothing was sent.")
      this.loadSmartReplyStatus()
    } finally {
      this.generating = false
      if (this.hasReplyLabelTarget) this.replyLabelTarget.textContent = "Suggest reply with Grok"
      if (this.hasTaskLabelTarget) this.taskLabelTarget.textContent = "Generate with Grok"
      this.updateButtons()
    }
  }

  previewLocalDraft() {
    if (this.panelTarget.hidden || !this.valid(this.editorTarget.value)) return
    if (this.previewKind) {
      this.previewTarget.open = true
      this.renderPreview()
    } else {
      this.preparePreview("draft", {})
    }
    this.setStatus("Local formatted preview · Not sent. Apply and Send are separate.")
  }

  clearPreview() {
    this.previewKind = null
    this.previewSourceLinks = {}
    if (!this.hasPreviewTarget) return
    this.previewTarget.hidden = true
    this.previewTarget.open = false
    this.previewBodyTarget.replaceChildren()
    this.previewSourcesTarget.replaceChildren()
    this.previewSourcesTarget.hidden = true
    this.previewFeedbackTarget.textContent = ""
    this.syncPreviewActions()
  }

  preparePreview(kind, sourceLinks) {
    if (!this.hasPreviewTarget) return
    this.previewKind = kind
    this.previewSourceLinks = sourceLinks && typeof sourceLinks === "object" &&
      !Array.isArray(sourceLinks) ? sourceLinks : {}
    this.previewTarget.hidden = false
    this.previewTarget.open = true
    this.previewFeedbackTarget.textContent = ""
    this.renderPreview()
  }

  renderPreview() {
    if (!this.previewKind || !this.hasPreviewTarget) return
    // A revoked grant or lost membership must not leave actionable source URLs.
    const links = this.contextReady ? this.previewSourceLinks : {}
    renderDeliverablePreview(this.previewBodyTarget, this.previewSourcesTarget,
      this.editorTarget.value, links, this.element.dataset.aiDraftRoomPath)
    this.syncPreviewActions()
  }

  syncPreviewActions() {
    if (!this.hasCopyButtonTarget || !this.hasExportButtonTarget) return
    const documentKind = ["client_brief", "client_proposal"].includes(this.previewKind)
    const valid = documentKind && this.valid(this.editorTarget.value) &&
      this.sourceText !== null && this.bodyTarget.value === this.sourceText &&
      this.contextReady && !this.generating && !this.panelTarget.hidden
    this.copyButtonTarget.hidden = !documentKind
    this.exportButtonTarget.hidden = !documentKind
    this.copyButtonTarget.disabled = !valid
    this.exportButtonTarget.disabled = !valid
  }

  async verifiedDocumentText() {
    const snapshot = this.editorTarget.value
    const currentRoom = this.element.dataset.aiDraftRoomId
    const kind = this.previewKind
    const statusUrl = this.element.dataset.aiDraftContextStatusUrl
    if (!["client_brief", "client_proposal"].includes(kind) ||
        !statusUrl || !this.contextReady || !this.valid(snapshot) ||
        this.bodyTarget.value !== this.sourceText || this.panelTarget.hidden) {
      throw new Error("Document is unavailable or draft changed. Nothing copied or exported.")
    }
    // Fresh server permission check: a removed member or revoked grant cannot
    // export a previously prepared private context result from this tab.
    const response = await fetch(statusUrl, {
      credentials: "same-origin", cache: "no-store",
      headers: { Accept: "application/json" }
    })
    if (!response.ok) throw new Error("Room access could not be verified. Nothing exported.")
    const status = await response.json()
    this.applySmartReplyStatus(status)
    if (!this.contextReady || this.element.dataset.aiDraftRoomId !== currentRoom ||
        this.previewKind !== kind || this.panelTarget.hidden ||
        this.editorTarget.value !== snapshot ||
        this.bodyTarget.value !== this.sourceText) {
      throw new Error("Permission or draft changed. Nothing copied or exported.")
    }
    return snapshot
  }

  async copyDocument() {
    if (!this.hasCopyButtonTarget || this.copyButtonTarget.disabled) return
    this.copyButtonTarget.disabled = true
    try {
      const text = await this.verifiedDocumentText()
      if (!navigator.clipboard?.writeText) throw new Error("Clipboard unavailable.")
      await navigator.clipboard.writeText(text)
      this.previewFeedbackTarget.textContent = "Copied reviewed Markdown · Not sent."
    } catch (error) {
      this.previewFeedbackTarget.textContent = error.message || "Copy failed; draft preserved."
    } finally {
      this.syncPreviewActions()
    }
  }

  async exportDocument() {
    if (!this.hasExportButtonTarget || this.exportButtonTarget.disabled) return
    this.exportButtonTarget.disabled = true
    try {
      const text = await this.verifiedDocumentText()
      const name = this.previewKind === "client_brief" ? "client-brief.md" : "client-proposal.md"
      const blob = new Blob([text], { type: "text/markdown;charset=utf-8" })
      const objectUrl = URL.createObjectURL(blob)
      try {
        const anchor = document.createElement("a")
        anchor.href = objectUrl
        anchor.download = name
        anchor.style.display = "none"
        document.body.append(anchor)
        anchor.click()
        anchor.remove()
      } finally {
        window.setTimeout(() => URL.revokeObjectURL(objectUrl), 1000)
      }
      this.previewFeedbackTarget.textContent = "Local Markdown export started · Not sent."
    } catch (error) {
      this.previewFeedbackTarget.textContent = error.message || "Export failed; draft preserved."
    } finally {
      this.syncPreviewActions()
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
