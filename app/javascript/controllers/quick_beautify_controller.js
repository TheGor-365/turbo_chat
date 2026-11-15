import { Controller } from "@hotwired/stimulus"

// Each arrow sends exactly one version through the canonical message form.
// Only Beautify makes one explicit paid request; neither Send invokes Grok.
const MAX_CHARS = 5000
const MAX_BYTES = 20000
const CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
const EMAIL = /\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b/i
const TOKEN = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,})\b/i
const PRESETS = ["polish_clarity", "professional_client_reply", "friendly", "concise", "technical_summary"]

export default class extends Controller {
  static targets = ["body", "panel", "candidate", "status", "cost",
    "generate", "sendAi", "aiRow", "regenerate", "settingsToggle", "settingsPanel",
    "presetSelect", "languageSelect", "toneSelect", "settingsStatus"]
  static values = { copy: Object }

  connect() {
    this.epoch = 0
    this.pending = false
    this.sending = false
    this.source = null
    this.preset = null
    this.lastGenerated = null
    this.manualOverrides = false
    this.manualOptions = null
    this.modelText = null
    this.provenance = null
    this.aiSubmission = null
    this.aiCustomHeight = false
    this.form = this.element.querySelector("form.message-composer")
    this.boundFormData = event => this.formData(event)
    this.boundResize = () => this.resizeEditors()
    this.form?.addEventListener("formdata", this.boundFormData)
    window.addEventListener("resize", this.boundResize)
    this.refresh()
  }

  disconnect() {
    ++this.epoch
    this.form?.removeEventListener("formdata", this.boundFormData)
    window.removeEventListener("resize", this.boundResize)
  }

  editor() {
    return this.application.getControllerForElementAndIdentifier(this.element, "ai-draft")
  }

  composer() {
    return this.application.getControllerForElementAndIdentifier(this.form, "message-composer")
  }

  valid(value) {
    return typeof value === "string" && value.trim() && !CONTROL.test(value) &&
      Array.from(value).length <= MAX_CHARS && new TextEncoder().encode(value).length <= MAX_BYTES
  }

  // Explicit, one-message options, never persisted as room/account defaults.
  currentOptions() {
    if (this.manualOverrides && this.manualOptions) return {...this.manualOptions}
    const editor = this.editor()
    return {preset: editor?.selectedPresetId || "polish_clarity",
      language: editor?.selectedLanguage || "auto",
      tone: editor?.selectedTone || "neutral"}
  }

  optionsKey(options = this.currentOptions()) {
    return JSON.stringify([options.preset, options.language, options.tone])
  }

  canRegenerate() {
    const current = this.currentOptions()
    return this.lastGenerated !== null && !this.pending && !this.sending &&
      !this.editor()?.generating && this.valid(this.bodyTarget.value) &&
      this.bodyTarget.value === this.source &&
      this.optionsKey(current) !== this.optionsKey(this.lastGenerated) &&
      PRESETS.includes(current.preset) && Boolean(this.element.dataset.quickBeautifyUrl)
  }

  syncSettingsControls() {
    const options = this.currentOptions()
    this.presetSelectTarget.value = options.preset
    this.languageSelectTarget.value = options.language
    this.toneSelectTarget.value = options.tone
  }

  toggleSettings() {
    if (this.pending || this.sending) return
    if (this.settingsPanelTarget.hidden) this.syncSettingsControls()
    this.settingsPanelTarget.hidden = !this.settingsPanelTarget.hidden
    this.settingsToggleTarget.setAttribute("aria-expanded", String(!this.settingsPanelTarget.hidden))
    if (!this.settingsPanelTarget.hidden) this.presetSelectTarget.focus()
  }

  settingsChanged() {
    this.manualOverrides = true
    this.manualOptions = {
      preset: this.presetSelectTarget.value,
      language: this.languageSelectTarget.value,
      tone: this.toneSelectTarget.value
    }
    this.settingsStatusTarget.textContent = this.canRegenerate()
      ? this.copyValue.changedSettings : this.copyValue.sameSettings
    this.refresh()
  }

  async regenerate() {
    if (!this.canRegenerate()) return
    await this.performGeneration(true)
  }

  canAiSend() {
    return !this.pending && !this.sending && this.source !== null &&
      this.source === this.bodyTarget.value &&
      this.lastGenerated !== null &&
      this.optionsKey() === this.optionsKey(this.lastGenerated) &&
      this.modelText !== null && typeof this.provenance === "string" &&
      this.provenance.length > 20 && this.valid(this.candidateTarget.value) &&
      this.candidateTarget.value !== this.bodyTarget.value
  }

  refresh() {
    if (!this.hasGenerateTarget) return
    this.generateTarget.disabled = this.pending || this.sending ||
      this.lastGenerated !== null || this.editor()?.generating ||
      !PRESETS.includes(this.currentOptions().preset) || !this.valid(this.bodyTarget.value) ||
      !this.element.dataset.quickBeautifyUrl
    if (this.hasRegenerateTarget) this.regenerateTarget.disabled = !this.canRegenerate()
    this.sendAiTarget.disabled = !this.canAiSend()
  }

  changed() {
    if (this.source !== null && this.bodyTarget.value !== this.source) {
      this.discard(this.copyValue.stale, true)
    }
    this.refresh()
  }

  presetChanged() {
    if (!this.manualOverrides && !this.settingsPanelTarget.hidden) this.syncSettingsControls()
    this.refresh()
  }

  discard(message = "", keepNotice = false) {
    ++this.epoch
    this.source = null
    this.preset = null
    this.lastGenerated = null
    this.manualOverrides = false
    this.manualOptions = null
    this.modelText = null
    this.provenance = null
    this.candidateTarget.value = ""
    this.candidateTarget.hidden = true
    this.costTarget.hidden = true
    this.costTarget.textContent = ""
    this.panelTarget.hidden = !keepNotice
    this.settingsPanelTarget.hidden = true
    this.settingsToggleTarget.setAttribute("aria-expanded", "false")
    this.statusTarget.textContent = message
    this.statusTarget.hidden = !message
    this.element.classList.toggle("sd-quick-beautify-active", keepNotice)
    this.composer()?.resizeBody()
    this.refresh()
  }

  close() {
    this.discard()
    this.bodyTarget.focus()
  }

  candidateChanged() {
    this.resizeAi()
    this.refresh()
  }

  resizeAi() {
    if (this.candidateTarget.hidden || this.aiCustomHeight) return
    const field = this.candidateTarget
    field.style.height = "auto"
    // Auto-layout leaves room for the AI toolbar, original and Send.
    // User-controlled expansion still reaches 46% viewport.
    field.style.height = Math.min(Math.max(field.scrollHeight, 60),
      Math.max(90, window.innerHeight * .32)) + "px"
  }

  resizeEditors() {
    this.resizeAi()
    this.composer()?.resizeBody()
    this.alignEditors()
  }

  // Align both textarea edges, Send button centers and grip midpoints
  // against the existing canonical human composer, without hiding its tools.
  alignEditors() {
    if (this.panelTarget.hidden || this.candidateTarget.hidden || !this.hasAiRowTarget) return
    const manualSend = this.form?.querySelector("button.composer-send")
    if (!manualSend) return
    const row = this.aiRowTarget
    row.style.marginRight = "0px"
    const rightDelta = manualSend.getBoundingClientRect().right -
      this.sendAiTarget.getBoundingClientRect().right
    row.style.marginRight = -rightDelta + "px"

    const rowLeft = row.getBoundingClientRect().left
    const gap = parseFloat(window.getComputedStyle(row).columnGap) || 2
    const desired = this.bodyTarget.getBoundingClientRect().left - rowLeft - gap
    const minEditorWidth = 120
    const available = Math.max(0, row.clientWidth -
      this.sendAiTarget.getBoundingClientRect().width - 2 * gap - minEditorWidth)
    row.style.setProperty("--sd-quick-ai-label-width",
      Math.min(Math.max(0, desired), available) + "px")
  }

  editorForGrip(grip) {
    return grip.dataset.resizeEditor === "ai" ? this.candidateTarget : this.bodyTarget
  }

  setEditorHeight(field, requested) {
    const max = Math.max(90, window.innerHeight * .46)
    field.style.height = Math.min(max, Math.max(60, requested)) + "px"
    if (field === this.candidateTarget) this.aiCustomHeight = true
    else field.dataset.manualHeight = "true"
  }

  beginResize(event) {
    if (event.button !== 0) return
    const grip = event.currentTarget
    const field = this.editorForGrip(grip)
    if (field.hidden || this.panelTarget.hidden) return
    event.preventDefault()
    this.drag = { id:event.pointerId, field,
      y:event.clientY, height:field.getBoundingClientRect().height }
    grip.setPointerCapture(event.pointerId)
  }

  dragResize(event) {
    if (!this.drag || this.drag.id !== event.pointerId) return
    // Handles sit on the top edge: moving UP increases height.
    this.setEditorHeight(this.drag.field, this.drag.height + this.drag.y - event.clientY)
  }

  endResize(event) {
    if (!this.drag || this.drag.id !== event.pointerId) return
    const grip = event.currentTarget
    if (grip.hasPointerCapture(event.pointerId)) grip.releasePointerCapture(event.pointerId)
    this.drag = null
  }

  resizeWithKeyboard(event) {
    if (!["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key)) return
    const field = this.editorForGrip(event.currentTarget)
    if (field.hidden || this.panelTarget.hidden) return
    event.preventDefault()
    const current = field.getBoundingClientRect().height
    const wanted = event.key === "Home" ? 60 : event.key === "End"
      ? window.innerHeight * .46 : current + (event.key === "ArrowUp" ? 24 : -24)
    this.setEditorHeight(field, wanted)
  }

  async generate() {
    if (this.generateTarget.disabled || this.lastGenerated !== null) return
    await this.performGeneration(false)
  }

  async performGeneration(isRetry) {
    const editor = this.editor()
    if (this.pending || this.sending || editor?.generating || !this.valid(this.bodyTarget.value)) return
    const original = this.bodyTarget.value
    const options = this.currentOptions()
    const preset = options.preset
    const endpoint = this.element.dataset.quickBeautifyUrl
    if (!endpoint || !PRESETS.includes(preset)) {
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
    if (!isRetry) {
      this.modelText = null
      this.provenance = null
    }
    this.panelTarget.hidden = false
    this.element.classList.add("sd-quick-beautify-active")
    if (!isRetry) {
      this.candidateTarget.value = ""
      this.candidateTarget.hidden = true
      this.costTarget.hidden = true
      this.costTarget.textContent = ""
    }
    this.settingsPanelTarget.hidden = true
    this.settingsToggleTarget.setAttribute("aria-expanded", "false")
    this.statusTarget.hidden = false
    this.statusTarget.textContent = this.copyValue.working
    this.pending = true
    editor.generating = true
    editor.updateButtons()
    this.resizeEditors()
    this.refresh()
    try {
      const response = await fetch(endpoint, {
        method: "POST", credentials: "same-origin",
        headers: {"Content-Type":"application/json","Accept":"application/json","X-CSRF-Token":csrf},
        body: JSON.stringify({draft:{
          text: original, preset_id: preset, consent:"1",
          writing_language: options.language, writing_tone: options.tone,
          request_id: globalThis.crypto.randomUUID()
        }})
      })
      if (!response.ok) throw new Error("request_failed")
      const result = await response.json()
      if (!this.valid(result.text)) throw new Error("invalid_result")
      if (epoch !== this.epoch || !this.element.isConnected ||
          this.bodyTarget.value !== original) return
      if (this.optionsKey() !== this.optionsKey(options)) {
        this.statusTarget.textContent = this.copyValue.staleSettings
        return
      }
      this.lastGenerated = {...options}
      this.costTarget.textContent = "$" + String(result.cost_usd ?? this.copyValue.unknown)
      this.costTarget.hidden = false
      if (result.text === original) {
        this.modelText = null
        this.provenance = null
        this.candidateTarget.value = ""
        this.candidateTarget.hidden = true
        this.statusTarget.textContent = this.copyValue.unchanged
        return
      }
      this.modelText = result.text
      this.provenance = typeof result.provenance_token === "string" ?
        result.provenance_token : null
      this.candidateTarget.value = result.text
      this.candidateTarget.hidden = false
      this.statusTarget.textContent = this.provenance ? "" : this.copyValue.proofUnavailable
      this.statusTarget.hidden = !!this.provenance
      this.aiCustomHeight = false
      this.resizeEditors()
      this.panelTarget.scrollTop = 0
    } catch (_) {
      if (epoch === this.epoch) {
        this.statusTarget.hidden = false
        this.statusTarget.textContent = this.copyValue.failed
      }
    } finally {
      this.pending = false
      editor.generating = false
      editor.updateButtons()
      this.refresh()
    }
  }

  // formdata is constructed by Turbo after the submit event. No alternate
  // endpoint, draft replacement or duplicate Send is used.
  beforeSubmit(event) {
    this.submittingAi = event.submitter === this.sendAiTarget
    this.aiSubmission = null
    if (this.submittingAi && !this.canAiSend()) {
      event.preventDefault()
      this.submittingAi = false
      return
    }
    if (this.submittingAi) {
      this.aiSubmission = {
        body: this.candidateTarget.value,
        source: this.modelText,
        proof: this.provenance
      }
    }
  }

  formData(event) {
    // Turbo may set sending=true before constructing FormData.
    // Retain the reviewed snapshot from submit, not live mutable controls.
    if (!this.submittingAi || !this.aiSubmission) return
    event.formData.set("message[send_variant]", "ai")
    event.formData.set("message[ai_body]", this.aiSubmission.body)
    event.formData.set("message[ai_source]", this.aiSubmission.source)
    event.formData.set("message[ai_proof]", this.aiSubmission.proof)
  }

  submitStart() {
    this.sending = true
    this.refresh()
  }

  submitEnd(event) {
    this.sending = false
    this.submittingAi = false
    this.aiSubmission = null
    if (event.detail.success) {
      this.discard()
      this.bodyTarget.removeAttribute("data-manual-height")
      this.aiCustomHeight = false
    }
    this.refresh()
  }
}
