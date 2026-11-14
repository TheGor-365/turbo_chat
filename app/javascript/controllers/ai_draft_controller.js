import { Controller } from "@hotwired/stimulus"
import { renderDeliverablePreview, safeSourceLink } from "../lib/ai_deliverable_preview"
import { briefSessionKey, storeBrief, readBrief, discardBrief } from "../lib/ai_brief_session_cache"
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
    "briefSpendConsentRow", "briefSpendConsent",
    "taskPicker", "taskOption", "taskSummaryLabel",
    "consentSummary", "consentCount", "consentCompact", "consentMembers",
    "preview", "previewBody", "previewSources", "copyButton", "exportButton", "reviewDocumentButton", "structuredReview", "previewFeedback",
    "previewDraftButton",
    "customHint", "templateName", "templateList", "templateFeedback",
    "sourceReviewButton", "sourceReviewStatus", "sourceReviewList",
    "evidenceReview", "evidenceReviewSummary", "evidenceReviewIssues"
  ]
  static values = { copy: Object }

  aiText(key, args = {}) {
    let value = this.copyValue[key] || key
    for (const [name, text] of Object.entries(args)) value = value.replaceAll(`{${name}}`, String(text))
    return value
  }

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
    this.briefRecoveryAttempted = false
    this.restoredBriefVisible = false
    this.briefRecoveryKey = briefSessionKey(
      this.element.dataset.aiDraftUserId, this.element.dataset.aiDraftRoomId
    )
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
    this.browserNameTarget.textContent = this.aiText("device", {browser: this.detectBrowser().split(" · ")[0]})
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
    // Navigation from room-local AI Workspace prepares the editor only.
    // It never enables consent, selects sources, or dispatches a provider call.
    if (this.hasTaskSelectTarget &&
        window.location.pathname === this.element.dataset.aiDraftRoomPath &&
        new URLSearchParams(window.location.search).get("ai_task") === "client_brief") {
      this.taskSelectTarget.value = "client_brief"
      this.changeContextTask()
      this.showEditor()
      this.setStatus(this.aiText("brief_selected"))
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
      this.aiText("template_unavailable")
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
      use.textContent = this.aiText("use")
      use.setAttribute("aria-label", this.aiText("use_template", {name: entry.name}))
      use.addEventListener("click", () => this.chooseLocalTemplate(index))
      const remove = document.createElement("button")
      remove.type = "button"
      remove.textContent = this.aiText("delete")
      remove.className = "sd-ai-local-template__delete"
      remove.setAttribute("aria-label", this.aiText("delete_template", {name: entry.name}))
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
      ? this.aiText("changed")
      : this.aiText("template_empty")
  }

  chooseLocalTemplate(index) {
    const entry = this.localTemplates[index]
    if (!entry || !this.hasCustomHintTarget) return
    this.customHintTarget.value = entry.instruction
    this.clearSourceReview()
    this.templateNameTarget.value = entry.name
    this.selectedTemplateName = entry.name
    this.templateFeedbackTarget.textContent = this.aiText("loaded")
    this.customHintTarget.focus()
  }

  newLocalTemplate() {
    this.selectedTemplateName = null
    this.templateNameTarget.value = ""
    this.templateFeedbackTarget.textContent = this.aiText("new_template")
    this.templateNameTarget.focus()
  }

  saveLocalTemplate() {
    if (!this.hasCustomHintTarget || this.generating) return
    const entry = normalizedTemplate(this.templateNameTarget.value, this.customHintTarget.value)
    if (!entry) {
      this.templateFeedbackTarget.textContent =
        this.aiText("template_invalid")
      return
    }
    const existing = this.localTemplates.findIndex(e =>
      e.name.toLocaleLowerCase() === entry.name.toLocaleLowerCase())
    const selected = this.selectedTemplateName === null ? -1 :
      this.localTemplates.findIndex(e => e.name === this.selectedTemplateName)
    if (existing >= 0 && existing !== selected) {
      this.templateFeedbackTarget.textContent = this.aiText("template_duplicate")
      return
    }
    const next = [...this.localTemplates]
    if (selected >= 0) next[selected] = entry
    else if (next.length >= MAX_TEMPLATES) {
      this.templateFeedbackTarget.textContent = this.aiText("template_limit")
      return
    } else next.push(entry)
    if (!writeLocalTemplates(this.templateStorageKey, next)) {
      this.templateFeedbackTarget.textContent = this.aiText("template_save_failed")
      return
    }
    this.localTemplates = next
    this.selectedTemplateName = entry.name
    this.templateNameTarget.value = entry.name
    this.renderLocalTemplates()
    this.templateFeedbackTarget.textContent = this.aiText("saved")
  }

  deleteLocalTemplate(index) {
    const entry = this.localTemplates[index]
    if (!entry || this.generating || !window.confirm(this.aiText("confirm_template", {name: entry.name}))) return
    const next = this.localTemplates.filter((_, i) => i !== index)
    if (!writeLocalTemplates(this.templateStorageKey, next)) {
      this.templateFeedbackTarget.textContent = this.aiText("template_delete_failed")
      return
    }
    this.localTemplates = next
    if (this.selectedTemplateName === entry.name) {
      this.selectedTemplateName = null
      this.templateNameTarget.value = ""
    }
    this.renderLocalTemplates()
    this.templateFeedbackTarget.textContent =
      this.aiText("template_deleted")
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
    const label = this.presetTargets.find(button => button.dataset.presetId === this.selectedPresetId)?.querySelector(".sd-ai-preset-name")?.textContent.trim() || "Polish / Clarity"
    this.presetBadgeTarget.textContent = label
    this.presetBadgeTarget.title = this.aiText("saved_style", { label }) +
      (this.hasGenerateButtonTarget ? this.aiText("style_hint") : "")
    this.spellToggleTarget.setAttribute("aria-checked", String(this.spellcheckEnabled))
    this.spellToggleTarget.setAttribute("aria-label", this.aiText(this.spellcheckEnabled ? "spell_toggle_off" : "spell_toggle_on"))
    this.spellStateTarget.textContent = this.aiText(this.spellcheckEnabled ? "on" : "off")
    this.spellIndicatorLabelTarget.textContent = this.aiText(this.spellcheckEnabled ? "spell_on" : "spell_off")
    this.spellIndicatorTarget.dataset.enabled = String(this.spellcheckEnabled)
    this.spellIndicatorTarget.setAttribute("aria-label", this.aiText("aria_spellcheck", {state: this.aiText(this.spellcheckEnabled ? "on" : "off")}))
    this.aiIndicatorTarget.setAttribute("aria-label", this.hasGenerateButtonTarget
      ? this.aiText("aria_manual_available") : this.aiText("aria_ai_off"))
    this.autoIndicatorTarget.setAttribute("aria-label", this.aiText("aria_auto_off"))
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
      if (this.contextReady) this.restoreSavedBrief()
    } catch (_) {
      if (version !== this.consentReadVersion || this.consentUpdating) return
      this.contextReady = false
      this.contextBlockReason = null
      this.contextStatusError = true
      this.smartReplyToggleTarget.disabled = true
      this.smartReplyStatusTarget.textContent = this.aiText("consent_error")
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
    if (!this.contextReady) {
      this.forgetSavedBrief()
      if (this.restoredBriefVisible) {
        this.restoredBriefVisible = false
        this.editorTarget.value = ""
        this.sourceText = null
        this.clearComparison()
        this.resultTarget.hidden = true
        this.setStatus(this.aiText("consent_changed_clear"))
      }
    }
    this.renderConsentRoster(data)
    if (this.hasSmartReplyToggleTarget) {
      this.smartReplyToggleTarget.disabled = data.available !== true
      this.smartReplyToggleTarget.setAttribute("aria-checked", String(this.contextGranted))
      this.smartReplyStateTarget.textContent = this.aiText(this.contextGranted ? "on" : "off")
      const granted = Number(data.granted) || 0
      const members = Number(data.members) || 0
      this.smartReplyStatusTarget.textContent =
        data.reason === "not_enough_members"
          ? this.aiText("consent_need_two")
          : data.reason === "too_many_members"
            ? this.aiText("consent_too_many")
            : data.available !== true
              ? this.aiText("consent_unavailable")
              : this.contextReady
                ? this.aiText("consent_ready")
                : this.contextGranted
                  ? this.aiText("consent_wait", { granted, members })
                  : this.aiText("consent_off")
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
      ? this.aiText("count_two")
      : data.reason === "too_many_members"
        ? this.aiText("count_many")
        : data.reason === "status_error" || data.available !== true
          ? this.aiText("count_unavailable")
          : this.aiText(ready ? "count_ready" : "count_wait", { granted, count })
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
      const description = member.name + (member.id === viewer ? this.aiText("you") : "")
      const item = document.createElement("li")
      item.className = "sd-ai-member"
      const name = document.createElement("span")
      name.className = "sd-ai-member-name"
      name.textContent = description
      const state = document.createElement("span")
      state.className = member.enabled ? "sd-ai-member-state is-on" : "sd-ai-member-state is-off"
      state.textContent = (member.enabled ? "✓ " : "– ") + this.aiText(member.enabled ? "on" : "off")
      item.append(name, state)
      roster.append(item)

      const chip = document.createElement("span")
      chip.className = member.enabled ? "sd-ai-member-chip is-on" : "sd-ai-member-chip is-off"
      chip.setAttribute("role", "listitem")
      chip.setAttribute("aria-label", description + ": " + this.aiText("room_label") + " " +
        this.aiText(member.enabled ? "on" : "off"))
      chip.title = description + ": " + this.aiText("room_label") + " " + this.aiText(member.enabled ? "on" : "off")
      const glyph = document.createElement("span")
      glyph.className = "sd-ai-consent-dot"
      glyph.textContent = member.enabled ? "✓" : "–"
      glyph.setAttribute("aria-hidden", "true")
      chip.append(glyph, document.createTextNode(description))
      compact.append(chip)
    })
    if (members.length === 0) {
      const item = document.createElement("li")
      item.textContent = this.aiText("member_unavailable")
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
      this.smartReplyStatusTarget.textContent = this.aiText("consent_save_error")
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
      this.aiText("auto_off")
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
        ? this.aiText("saved_preset")
        : "Preset changed for now, but your browser blocked saving preferences."
    }
    if (!this.panelTarget.hidden) this.setStatus("")
  }

  selectVisualState() {
    this.presetTargets.forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.presetId === this.selectedPresetId))
    })
    const active = this.presetTargets.find(button => button.dataset.presetId === this.selectedPresetId)
    const label = active?.querySelector(".sd-ai-preset-name")?.textContent.trim() || "Polish / Clarity"
    if (this.hasStyleLabelTarget) this.styleLabelTarget.textContent = label
    if (this.hasRoomStyleLabelTarget) this.roomStyleLabelTarget.textContent = label
    if (this.hasTranslationControlsTarget) {
      const translating = this.selectedPresetId === TRANSLATION_ID
      this.translationControlsTarget.hidden = !translating
      this.targetLocaleTarget.disabled = !translating
    }
    if (this.hasGenerateLabelTarget && !this.generating) {
      this.generateLabelTarget.textContent =
        this.aiText({polish_clarity:"gen_polish",professional_client_reply:"gen_client",friendly:"gen_friendly",concise:"gen_concise",translate_preserving_tone:"gen_translate",technical_summary:"gen_summary"}[this.selectedPresetId] || "gen_polish")
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
        ? this.aiText("draft_changed_notice")
        : this.aiText("draft_manual_notice"))
    }
  }

  refresh() {
    if (this.panelTarget.hidden) return
    this.clearEvidenceReview()
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
        : this.aiText("draft_limit"))
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
    if (this.previewKind === "client_brief" && this.contextReady && this.briefRecoveryKey) {
      const stored = readBrief(window.sessionStorage, this.briefRecoveryKey)
      if (stored) {
        if (!this.editorTarget.value.trim()) this.forgetSavedBrief()
        else storeBrief(window.sessionStorage, this.briefRecoveryKey,
          { kind: "client_brief", text: this.editorTarget.value,
            sourceIds: stored.sourceIds, cost: stored.cost }, stored.at)
      }
    }
    this.clearSourceReview()
    this.clearEvidenceReview()
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
      this.setStatus(this.aiText("copy_limit"))
      return
    }
    if (this.bodyTarget.value !== this.sourceText) {
      this.setStatus(this.aiText("draft_changed_reload"))
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
      const briefNeedsConsent = this.taskSelectTarget.value === "client_brief" &&
        (!this.hasBriefSpendConsentTarget || !this.briefSpendConsentTarget.checked)
      this.taskButtonTarget.disabled = this.generating || !contextualCandidate ||
        !this.taskSelectTarget.value || !selectedSourcesValid || briefNeedsConsent
    }
    if (this.hasContextAvailabilityTarget) {
      this.contextAvailabilityTarget.textContent = this.contextStatusError
        ? this.aiText("context_permission_error")
        : this.contextBlockReason === "not_enough_members"
          ? this.aiText("context_needs_members")
          : this.contextBlockReason === "too_many_members"
            ? this.aiText("context_too_many")
            : !this.contextGranted
          ? this.aiText("context_switch_off")
          : !this.contextReady
            ? this.aiText("context_wait_all")
            : !contextCopySafe
              ? this.aiText("context_finish_previous")
              : this.aiText("context_ready_paid")
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
      this.setStatus(this.aiText("draft_secure_missing"))
      return
    }

    this.generating = true
    if (this.hasProviderCostTarget) {
      this.providerCostTarget.hidden = true
      this.providerCostTarget.textContent = ""
    }
    this.updateButtons()
    if (this.hasGenerateLabelTarget) this.generateLabelTarget.textContent = this.aiText("manual_working")
    this.setStatus(this.aiText("manual_preparing"))
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
        this.setStatus(this.aiText("manual_late"))
        return
      }
      const reportedCost = String(result.cost_usd ?? "unknown")
      if (this.hasProviderCostTarget) {
        this.providerCostTarget.textContent = this.aiText("reported_cost") + reportedCost
        this.providerCostTarget.hidden = false
      }
      if (result.text === draft) {
        // A successful billable API call does not guarantee any edit.
        // The original draft is preserved; no meaningless Apply is offered.
        this.setStatus(this.aiText("manual_unchanged"))
        return
      }
      this.editorTarget.value = result.text
      this.editorTouched = true
      this.originalTextTarget.textContent = draft
      this.comparisonTarget.hidden = false
      this.editorLabelTarget.textContent = "Suggested"
      this.resizeEditor()
      this.preparePreview("manual", {})
      this.setStatus(this.aiText("manual_suggested"))
    } catch (_) {
      this.setStatus(this.aiText("manual_failed"))
    } finally {
      this.generating = false
      if (this.hasGenerateLabelTarget) {
        this.generateLabelTarget.textContent =
          this.aiText({polish_clarity:"gen_polish",professional_client_reply:"gen_client",friendly:"gen_friendly",concise:"gen_concise",translate_preserving_tone:"gen_translate",technical_summary:"gen_summary"}[this.selectedPresetId] || "gen_polish")
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
    if (this.hasBriefSpendConsentRowTarget && this.hasTaskSelectTarget) {
      const isBrief = this.taskSelectTarget.value === "client_brief"
      this.briefSpendConsentRowTarget.hidden = !isBrief
      if (this.hasBriefSpendConsentTarget) this.briefSpendConsentTarget.checked = false
    }
    if (this.hasTaskSummaryLabelTarget && this.hasTaskSelectTarget) {
      const selected = this.taskSelectTarget.selectedOptions[0]
      this.taskSummaryLabelTarget.textContent =
        selected?.textContent.trim() || this.taskSelectTarget.options[0]?.textContent.trim() || ""
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
      this.aiText("source_cleared")
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
      this.sourceReviewStatusTarget.textContent = this.aiText("source_note_invalid")
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
    this.sourceReviewStatusTarget.textContent = this.aiText("source_reviewing")
    try {
      const response = await fetch(url, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ preview: { hint } })
      })
      if (!response.ok) throw new Error(response.status === 429
        ? this.aiText("source_rate_limit")
        : this.aiText("source_access_denied"))
      const data = await response.json()
      if (epoch !== this.sourceReviewEpoch || this.panelTarget.hidden || !this.contextReady ||
          this.bodyTarget.value !== bodyBefore || this.editorTarget.value !== copyBefore ||
          (this.hasCustomHintTarget && this.customHintTarget.value.trim() !== note)) return
      if (!Array.isArray(data.sources) || !data.sources.length || data.sources.length > 9 ||
          typeof data.source_token !== "string" || data.source_token.length < 1 ||
          data.source_token.length > 4096)
        throw new Error("Invalid source preview response.")
      const labels = { latest_incoming: this.aiText("source_latest_incoming"), recent_turn: this.aiText("source_recent_turn"),
        keyword_match: this.aiText("source_keyword_match"), context_fallback: this.aiText("source_context_fallback") }
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
        checkbox.setAttribute("aria-label", this.aiText("aria_source_include", {id: source.id}))
        checkbox.addEventListener("change", () => this.changeSourceSelection())
        const labelText = document.createElement("strong")
        labelText.textContent = "M" + source.id + " · " + labels[source.reason] +
          (source.truncated ? this.aiText("source_shortened") : "")
        label.append(checkbox, labelText)
        li.append(label)
        const href = safeSourceLink(source.url, this.element.dataset.aiDraftRoomPath, String(source.id))
        if (href) {
          const link = document.createElement("a")
          link.href = href
          link.target = "_blank"
          link.rel = "noopener noreferrer"
          link.dataset.turbo = "false"
          link.textContent = this.aiText("source_open")
          link.setAttribute("aria-label", this.aiText("aria_source_open", {id: source.id}))
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
      // Suggest a task only after explicit, member-consented local source review.
      // An existing manual choice wins; nothing generates or spends here.
      const workflow = data.smart_workflow
      if (this.hasTaskSelectTarget && !this.taskSelectTarget.value &&
          workflow?.version === 1 && typeof workflow.kind === "string") {
        const option = Array.from(this.taskSelectTarget.options).find(
          item => item.value && item.value === workflow.kind)
        if (option) {
          this.taskSelectTarget.value = option.value
          this.changeContextTask()
          this.sourceReviewStatusTarget.textContent += " " +
            this.aiText("workflow_suggested", {task: option.textContent.trim()})
        }
      }
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
    await this.requestContextResult({ kind: null, label: this.aiText("context_selected_reply") })
  }

  async generateContextTask() {
    if (!this.hasTaskButtonTarget || this.taskButtonTarget.disabled) return
    const kind = this.taskSelectTarget.value
    const allowed = ["conversation_summary", "action_items", "client_brief",
      "client_proposal", "content_outline"]
    if (!allowed.includes(kind)) return
    if (kind === "client_brief" &&
        (!this.hasBriefSpendConsentTarget || !this.briefSpendConsentTarget.checked)) {
      this.setStatus(this.aiText("brief_authorize_not_sent"))
      return
    }
    await this.requestContextResult({ kind, label: this.aiText("context_selected_task") })
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
      this.setStatus(this.aiText("context_secure_missing"))
      return
    }

    const priorBody = this.bodyTarget.value
    const priorCopy = this.editorTarget.value
    const customNote = this.hasCustomHintTarget ? this.customHintTarget.value : ""
    const hint = customNote.trim() || priorCopy.trim()
    const selectedTask = kind && this.taskSelectTarget.value
    if (hint && !validAuthorNote(hint)) {
      this.setStatus(this.aiText("context_note_limit"))
      return
    }

    const selectionToken = this.sourceSelectionToken
    const selectionIds = [...this.sourceSelectionIds]
    const selectionEpoch = this.sourceReviewEpoch
    if (selectionToken) {
      if (!selectionIds.length || !this.sourceReviewRows.some(row =>
          selectionIds.includes(row.id) && row.speaker !== "you")) {
        this.setStatus(this.aiText("context_select_incoming"))
        return
      }
    }
    const payload = { hint, consent: "1", request_id: globalThis.crypto.randomUUID() }
    if (selectionToken) {
      payload.source_token = selectionToken
      payload.source_ids = selectionIds
    }
    if (kind) payload.kind = kind
    // Each Client Brief authorization is strictly single-use, even if the
    // request fails, the room grant changes, or the editor is reopened.
    if (kind === "client_brief" && this.hasBriefSpendConsentTarget) {
      if (!this.briefSpendConsentTarget.checked) {
        this.setStatus(this.aiText("brief_authorize_once"))
        return
      }
      this.briefSpendConsentTarget.checked = false
    }
    this.generating = true
    this.updateButtons()
    if (kind) this.taskLabelTarget.textContent = this.aiText("manual_working")
    else this.replyLabelTarget.textContent = this.aiText("context_preparing_reply")
    this.setStatus(this.aiText("context_using"))
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
          ? this.aiText("context_source_expired")
          : this.aiText("context_check_consent"))
        if (response.status === 429) throw new Error(this.aiText("context_rate_limit"))
        if (response.status === 403) throw new Error(this.aiText("context_access_revoked"))
        if (response.status === 503) throw new Error(this.aiText("context_provider_unavailable"))
        throw new Error("AI request failed (HTTP " + response.status + ").")
      }
      const suggestion = await response.json()
      if (!this.valid(suggestion.text) ||
          (kind && suggestion.kind !== kind) ||
          !Array.isArray(suggestion.source_message_ids) ||
          !suggestion.source_message_ids.length ||
          !suggestion.source_message_ids.every(id => Number.isSafeInteger(id) && id > 0)) {
        throw new Error(this.aiText("context_invalid_result"))
      }
      if (this.panelTarget.hidden || priorBody !== this.bodyTarget.value ||
          priorCopy !== this.editorTarget.value ||
          (this.hasCustomHintTarget && customNote !== this.customHintTarget.value) ||
          selectionEpoch !== this.sourceReviewEpoch ||
          !this.contextReady ||
          (kind && this.taskSelectTarget.value !== selectedTask)) {
        this.setStatus(this.aiText("context_late_result"))
        return
      }

      this.clearSourceReview()
      this.sourceText = priorBody
      this.editorTarget.value = suggestion.text
      this.editorTouched = true
      this.resultTarget.hidden = false
      this.originalTextTarget.textContent = priorCopy || this.aiText("context_no_previous")
      this.comparisonTarget.hidden = false
      this.editorLabelTarget.textContent = label
      this.resizeEditor()
      this.counterTarget.textContent = Array.from(suggestion.text).length + " / 5000"
      this.preparePreview(kind || "reply", suggestion.source_links || {})
      if (kind === "client_brief") {
        this.saveGeneratedBrief(suggestion)
      }
      this.renderEvidenceReview(suggestion.evidence_review, suggestion.source_message_ids)
      this.renderStructuredReview(suggestion.structured_review, kind)
      if (this.hasContextSourcesTarget) {
        this.contextSourcesTarget.textContent =
          this.aiText("context_room_sources") +
          suggestion.source_message_ids.map(id => "#" + id).join(", ") +
          this.aiText("context_omitted") +
          (Number(suggestion.omitted_context_messages) || 0) + "."
        this.contextSourcesTarget.hidden = false
      }
      if (this.hasProviderCostTarget) {
        this.providerCostTarget.textContent = this.aiText("reported_cost") +
          String(suggestion.cost_usd ?? "unknown")
        this.providerCostTarget.hidden = false
      }
      this.setStatus(kind && suggestion.structured_review?.complete === false ?
        label + this.aiText("context_review_needed") :
        label + this.aiText("context_result_review"))
    } catch (error) {
      this.setStatus(error.message || this.aiText("context_failure"))
      this.loadSmartReplyStatus()
    } finally {
      this.generating = false
      if (this.hasReplyLabelTarget) this.replyLabelTarget.textContent = this.aiText("context_suggest_label")
      if (this.hasTaskLabelTarget) this.taskLabelTarget.textContent = this.aiText("context_generate_label")
      this.updateButtons()
    }
  }

  clearEvidenceReview() {
    if (!this.hasEvidenceReviewTarget) return
    this.evidenceReviewTarget.hidden = true
    this.evidenceReviewTarget.open = false
    this.evidenceReviewIssuesTarget.replaceChildren()
  }

  renderEvidenceReview(review, sourceIds) {
    this.clearEvidenceReview()
    if (!this.hasEvidenceReviewTarget || !review ||
        review.version !== 1 ||
        review.assessment !== "structural_only_not_fact_checked" ||
        !Array.isArray(review.cited_source_ids) ||
        !Array.isArray(review.issues) || review.issues.length > 20) return
    const fields = ["checked_lines", "linked_lines", "uncited_lines",
      "weak_overlap_lines", "needs_confirmation_lines"]
    if (!fields.every(field => Number.isSafeInteger(review[field]) &&
        review[field] >= 0 && review[field] <= 160) ||
        !review.cited_source_ids.every(id => Number.isSafeInteger(id) &&
          Array.isArray(sourceIds) && sourceIds.includes(id))) return

    const signals = { no_citation: "No explicit source link",
      weak_lexical_overlap: "Weak lexical overlap — inspect source",
      needs_confirmation: "Not yet confirmed" }
    const nodes = document.createDocumentFragment()
    for (const issue of review.issues) {
      if (!Number.isSafeInteger(issue?.line) || issue.line < 1 ||
          issue.line > 500 ||
          !Object.prototype.hasOwnProperty.call(signals, issue.signal)) return
      const li = document.createElement("li")
      li.textContent = "Line " + issue.line + ": " + signals[issue.signal]
      nodes.append(li)
    }
    this.evidenceReviewSummaryTarget.textContent =
      "Evidence review · " + review.linked_lines + " linked, " +
      review.uncited_lines + " uncited, " + review.weak_overlap_lines + " low-overlap" +
      (review.truncated ? " · partial" : "")
    this.evidenceReviewIssuesTarget.replaceChildren(nodes)
    this.evidenceReviewTarget.hidden = false
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

  renderStructuredReview(report, kind) {
    if (!this.hasStructuredReviewTarget) return
    const supported = ["client_brief", "client_proposal", "conversation_summary"].includes(kind)
    const box = this.structuredReviewTarget
    box.hidden = !supported
    box.replaceChildren()
    if (!supported) return
    const title = document.createElement("strong")
    const description = document.createElement("span")
    const warnings = report && Array.isArray(report.warnings) ?
      report.warnings.filter(s => typeof s === "string").slice(0, 10) : []
    if (report && report.complete === true) {
      title.textContent = "Structure ready for review · not approved"
      description.textContent = "Citations and section shape were checked. Verify meaning, scope and agreement yourself."
    } else {
      title.textContent = "Manual review required · not approved"
      description.textContent = warnings.length ?
        warnings.join(" · ").slice(0, 1100) :
        "The model output could not be validated as a complete structured document."
    }
    box.append(title, description)
  }

  saveGeneratedBrief(suggestion) {
    if (!this.contextReady || !this.briefRecoveryKey) return
    storeBrief(window.sessionStorage, this.briefRecoveryKey, {
      kind: "client_brief", text: suggestion.text,
      sourceIds: suggestion.source_message_ids,
      cost: suggestion.cost_usd
    })
  }

  forgetSavedBrief() {
    discardBrief(window.sessionStorage, this.briefRecoveryKey)
  }

  restoreSavedBrief() {
    if (this.briefRecoveryAttempted || !this.contextReady || !this.briefRecoveryKey ||
        !this.hasTaskSelectTarget || this.generating ||
        this.bodyTarget.value.trim() || this.editorTouched) return
    const saved = readBrief(window.sessionStorage, this.briefRecoveryKey)
    this.briefRecoveryAttempted = true
    if (!saved) return
    this.taskSelectTarget.value = "client_brief"
    this.changeContextTask()
    this.showEditor()
    this.editorTarget.value = saved.text
    this.sourceText = this.bodyTarget.value
    this.editorTouched = true
    this.restoredBriefVisible = true
    this.resultTarget.hidden = false
    if (this.hasOriginalTextTarget) this.originalTextTarget.textContent = "Recovered browser session"
    if (this.hasComparisonTarget) this.comparisonTarget.hidden = false
    if (this.hasEditorLabelTarget) this.editorLabelTarget.textContent = "Recovered"
    this.resizeEditor()
    this.counterTarget.textContent = Array.from(saved.text).length + " / 5000"
    // Recovered citations are displayed as text. No old authorization token
    // or source links survive; H4 Review performs fresh server-side checks.
    this.preparePreview("client_brief", {})
    if (this.hasContextSourcesTarget) {
      this.contextSourcesTarget.textContent =
        "Recovered source IDs: " + saved.sourceIds.map(id => "#" + id).join(", ") +
        " · links require fresh review."
      this.contextSourcesTarget.hidden = false
    }
    if (saved.cost && this.hasProviderCostTarget) {
      this.providerCostTarget.textContent = "Previously reported provider cost: $" + saved.cost
      this.providerCostTarget.hidden = false
    }
    this.setStatus("Recovered Client Brief from this browser tab. Not sent or approved. Review sources before use. Recovery expires 30 minutes after generation.")
    this.updateButtons()
  }

  clearPreview() {
    this.previewKind = null
    this.previewSourceLinks = {}
    if (this.hasStructuredReviewTarget) {
      this.structuredReviewTarget.hidden = true
      this.structuredReviewTarget.replaceChildren()
    }
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
    const reviewKind = ["client_brief", "client_proposal", "conversation_summary"].includes(this.previewKind)
    const current = this.valid(this.editorTarget.value) &&
      this.sourceText !== null && this.bodyTarget.value === this.sourceText &&
      this.contextReady && !this.generating && !this.panelTarget.hidden
    this.copyButtonTarget.hidden = !documentKind
    this.exportButtonTarget.hidden = !documentKind
    this.copyButtonTarget.disabled = !documentKind || !current
    this.exportButtonTarget.disabled = !documentKind || !current
    if (this.hasReviewDocumentButtonTarget) {
      this.reviewDocumentButtonTarget.hidden = !reviewKind
      this.reviewDocumentButtonTarget.disabled = !reviewKind || !current ||
        !this.element.dataset.aiDraftReviewUrl
    }
  }

  async verifiedDocumentText() {
    const snapshot = this.editorTarget.value
    const currentRoom = this.element.dataset.aiDraftRoomId
    const kind = this.previewKind
    const statusUrl = this.element.dataset.aiDraftContextStatusUrl
    if (!["client_brief", "client_proposal", "conversation_summary"].includes(kind) ||
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

  async reviewDocument() {
    if (!this.hasReviewDocumentButtonTarget || this.reviewDocumentButtonTarget.disabled) return
    const kind = this.previewKind
    const room = this.element.dataset.aiDraftRoomId
    const endpoint = this.element.dataset.aiDraftReviewUrl
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!endpoint || !csrf) {
      this.previewFeedbackTarget.textContent = "Secure review unavailable. Nothing sent."
      return
    }
    // Open a blank same-origin tab synchronously from the user's click:
    // browsers may block a popup opened only after the async ACL request.
    // This window never receives source content unless live consent passes.
    const reviewWindow = window.open("about:blank", "_blank")
    if (!reviewWindow) {
      this.previewFeedbackTarget.textContent =
        "Allow a new tab to review this document; your draft is unchanged."
      return
    }
    reviewWindow.opener = null
    reviewWindow.name = "sd_h4_review_" + room
    this.reviewDocumentButtonTarget.disabled = true
    try {
      const markdown = await this.verifiedDocumentText()
      if (kind !== this.previewKind || room !== this.element.dataset.aiDraftRoomId ||
          !this.contextReady || !this.valid(markdown)) {
        throw new Error("Document or permission changed. Review was not opened.")
      }
      // The server does not trust the kind, supplied text or citation IDs:
      // it rebuilds the authorized context and parses the document afresh.
      // A separate tab preserves the original unsent message working copy.
      const form = document.createElement("form")
      form.method = "post"
      form.action = endpoint
      form.target = reviewWindow.name
      form.hidden = true
      for (const [name, value] of [
        ["authenticity_token", csrf],
        ["deliverable[kind]", kind],
        ["deliverable[origin]", "editor"],
        ["deliverable[text]", markdown]
      ]) {
        const field = document.createElement("input")
        field.type = "hidden"
        field.name = name
        field.value = value
        form.append(field)
      }
      document.body.append(form)
      try {
        form.submit()
        this.previewFeedbackTarget.textContent =
          "Review requested in a new tab · working copy unchanged · not sent to chat."
      } finally {
        form.remove()
      }
    } catch (error) {
      reviewWindow.close()
      this.previewFeedbackTarget.textContent = error.message ||
        "Review unavailable; working copy preserved."
    } finally {
      this.syncPreviewActions()
    }
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
    this.setStatus(this.aiText("applied_not_sent"))
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
    this.setStatus(this.aiText("restored_not_sent"))
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
    this.restoredBriefVisible = false
    this.forgetSavedBrief()
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
    this.restoredBriefVisible = false
    this.forgetSavedBrief()
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
