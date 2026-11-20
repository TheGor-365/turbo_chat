import { Controller } from "@hotwired/stimulus"

// Human-reviewed contextual AI Answer with budget/consent preflight; the user
// selects either independent Send. No automatic publication or repeat billing.
export default class extends Controller {
  static targets = ["trigger", "status", "consent", "consentStatus", "result", "resultText", "resultHeading", "candidate", "candidateLabel", "composer", "sendAi", "body", "regenerate", "settings", "grip"]
  static values = { goalUrl: String, consentUrl: String, previewUrl: String, generateUrl: String, synthetic: Boolean, copy: Object }

  connect() {
    this.epoch = 0
    this.pending = false
    this.goal = null
    this.access = null
    this.generated = null
    this.aiSubmission = null
    this.needsRegeneration = false
    this.customAiHeight = false
    this.form = this.element.querySelector("form.message-composer")
    this.boundFormData = event => this.formData(event)
    this.form?.addEventListener("formdata", this.boundFormData)
    this.boundResize = () => this.alignTwin()
    window.addEventListener("resize", this.boundResize)
    this.sizeObserver = window.ResizeObserver ? new ResizeObserver(this.boundResize) : null
    for (const element of [
      this.element.querySelector(".composer-controls"),
      this.element.querySelector(".composer-controls .sd-composer-editor-field"),
      this.element.querySelector(".composer-controls button.composer-send")
    ]) {
      if (element) this.sizeObserver?.observe(element)
    }
    this.changed()
    this.refresh()
  }

  disconnect() {
    this.epoch += 1
    this.form?.removeEventListener("formdata", this.boundFormData)
    window.removeEventListener("resize", this.boundResize)
    this.sizeObserver?.disconnect()
  }

  editor() { return this.bodyTarget }
  text(key, data = {}) {
    let msg = this.copyValue[key] || key
    for (const [k, v] of Object.entries(data)) msg = msg.replaceAll("{" + k + "}", String(v))
    return msg
  }

  changed() {
    // The human and AI editors are independent. Typing in the lower one
    // changes the next generation action to Beautify, but does NOT delete the
    // already reviewed AI candidate or steal its separate Send.
    if (this.pending) ++this.epoch
    this.element.dataset.aiComposerMode =
      this.editor().value.trim() ? "beautify" : "answer"
    this.render()
  }

  async refresh() {
    const epoch = ++this.epoch
    this.goal = null
    this.access = null
    this.render()
    try {
      const [goalResponse, consentResponse] = await Promise.all([
        fetch(this.goalUrlValue, {credentials: "same-origin", cache: "no-store",
          headers: {Accept: "application/json"}}),
        fetch(this.consentUrlValue, {credentials: "same-origin", cache: "no-store",
          headers: {Accept: "application/json"}})
      ])
      if (!goalResponse.ok || !consentResponse.ok) throw new Error("unavailable")
      const [goal, access] = await Promise.all([goalResponse.json(), consentResponse.json()])
      if (epoch !== this.epoch || !this.element.isConnected) return
      if (typeof goal.configured !== "boolean" ||
          !Number.isSafeInteger(goal.current_revision) ||
          typeof access.ready !== "boolean" ||
          !Number.isSafeInteger(access.members) ||
          !Number.isSafeInteger(access.granted)) throw new Error("unavailable")
      this.goal = goal
      this.access = access
      if (this.generated && !access.ready) this.discard()
      if (this.generated && goal.current_revision !== this.generated.goalRevision) {
        this.needsRegeneration = true
      }
      this.render()
    } catch (_) {
      if (epoch !== this.epoch || !this.element.isConnected) return
      this.statusTarget.textContent = this.text("unavailable")
      this.statusTarget.dataset.state = "error"
    }
  }

  render() {
    this.triggerTarget.disabled = this.pending
    this.updateAiActions()
    const draft = this.editor().value.trim()
    let label, state
    if (!this.goal || !this.access) {
      label = this.text("checking")
      state = "checking"
    } else if (draft) {
      label = this.text("emptyEditor")
      state = "draft"
    } else if (!this.goal.configured) {
      label = this.text("missingGoal")
      state = "goal"
    } else if (!this.access.ready) {
      label = this.text("missingConsent", {
        granted: this.access.granted, members: this.access.members
      })
      state = "consent"
    } else {
      label = this.hasGenerateUrlValue
        ? this.text(this.syntheticValue ? "syntheticReady" : "paidReady")
        : this.text("dryRunReady")
      state = "ready"
    }
    this.statusTarget.textContent = label
    this.statusTarget.dataset.state = state
    const hint = !this.hasGenerateUrlValue ? "buttonHint" :
      (this.syntheticValue ? "syntheticButtonHint" : "paidButtonHint")
    this.triggerTarget.title = this.text(hint) + " · " + label
    this.triggerTarget.setAttribute("aria-label", this.text("button") + " · " + label)
    this.triggerTarget.dataset.state = state
    this.element.dataset.aiComposerMode =
      this.editor().value.trim() ? "beautify" : "answer"
    if (this.hasConsentStatusTarget) {
      this.consentStatusTarget.textContent = this.access
        ? this.text("consentCount", {
            granted: this.access.granted, members: this.access.members
          }) : this.text("checking")
    }
    if (this.hasConsentTarget && this.access) {
      this.consentTarget.textContent = this.access.enabled
        ? this.text("revokeConsent") : this.text("grantConsent")
      this.consentTarget.disabled = this.pending
    }
  }

  openSettings(selector, focusSelector) {
    const draft = this.application.getControllerForElementAndIdentifier(this.element, "ai-draft")
    if (!draft) {
      this.statusTarget.textContent = this.text("unavailable")
      return
    }
    draft.showSettings()
    const section = this.element.querySelector(selector)
    const fold = section?.querySelector("details")
    if (fold) fold.open = true
    const target = section?.querySelector(focusSelector || "button, textarea, summary")
    target?.focus({preventScroll: false})
    section?.scrollIntoView({block: "nearest"})
  }

  async open() {
    if (this.pending) return
    if (this.editor().value.trim()) {
      this.statusTarget.textContent = this.text("emptyEditor")
      this.editor().focus()
      return
    }
    // Read the current goal and grants on EVERY user click, not only on mount.
    await this.refresh()
    if (!this.goal || !this.access) return
    if (!this.goal.configured) {
      this.openSettings(".sd-room-ai-instructions",
        ".sd-room-ai-instructions__summary")
      return
    }
    if (!this.access.ready) {
      this.openSettings(".sd-ai-room-option--smart",
        "[data-ai-draft-target='smartReplyToggle']")
      return
    }
    if (this.hasGenerateUrlValue) {
      if (!window.confirm(this.text(this.syntheticValue ? "confirmSynthetic" : "confirmSpend"))) return
      await this.generate()
    } else {
      await this.preview()
    }
  }

  async toggleConsent() {
    if (this.pending || !this.access) return
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf) return
    const enabled = this.access.enabled ? "0" : "1"
    this.pending = true
    this.render()
    try {
      const response = await fetch(this.consentUrlValue, {
        method: "PATCH", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf},
        body: JSON.stringify({consent: {enabled}})
      })
      if (!response.ok) throw new Error("unavailable")
      this.discard()
      this.access = null
    } catch (_) {
      this.consentStatusTarget.textContent = this.text("unavailable")
    } finally {
      this.pending = false
      await this.refresh()
    }
  }

  async preview() {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || !this.goal?.configured || !this.access?.ready ||
        this.editor().value.trim()) return
    const epoch = ++this.epoch
    const original = this.editor().value
    this.pending = true
    this.render()
    this.discard()
    this.resultHeadingTarget.textContent = this.text("privacy")
    this.statusTarget.textContent = this.text("preparing")
    try {
      const res = await fetch(this.previewUrlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf},
        body: JSON.stringify({preview: {mode: "answer", draft_text: original,
          goal_source: "room_instructions",
          expected_goal_revision: this.goal.current_revision}})
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) throw new Error(data.error || "unavailable")
      if (epoch !== this.epoch || !this.element.isConnected ||
          this.editor().value !== original) return
      if (data.mode !== "answer" || data.provider_called !== false ||
          data.budget_reserved !== false || data.message_sent !== false ||
          data.automatic_send_active !== false || !Array.isArray(data.sources) ||
          !Array.isArray(data.source_ids)) throw new Error("unavailable")
      const lines = [this.text("goal") + ": " + data.goal_purpose,
        this.text("sources") + ": " + data.source_ids.length]
      for (const item of data.sources) {
        lines.push(item.ref + " · " + item.speaker + "\n" + item.text)
      }
      this.resultTextTarget.textContent = lines.join("\n\n")
      this.resultTarget.dataset.mode = "preview"
      this.resultTarget.hidden = false
      this.statusTarget.textContent = this.text("previewReady")
    } catch (e) {
      if (epoch !== this.epoch || !this.element.isConnected) return
      const key = e.message === "context_consent_required" ? "missingConsent" :
        e.message === "invalid_or_stale_input" ? "stale" : "unavailable"
      this.statusTarget.textContent = key === "missingConsent"
        ? this.text(key, {granted: this.access?.granted ?? 0,
          members: this.access?.members ?? 0}) : this.text(key)
    } finally {
      this.pending = false
      const finalStatus = this.statusTarget.textContent
      this.render()
      // Keep the specific denial reason, not a generic 'stale' response.
      if (epoch === this.epoch) this.statusTarget.textContent =
        this.resultTarget.hidden ? finalStatus : this.text("previewReady")
    }
  }

  canSend() {
    const candidate = this.hasCandidateTarget ? this.candidateTarget.value : ""
    return !this.pending && !this.needsRegeneration &&
      this.generated !== null && candidate.trim().length > 0 &&
      candidate.length <= 5000 && new TextEncoder().encode(candidate).length <= 20000
  }

  candidateChanged() {
    this.resizeCandidate()
    this.sendAiTarget.disabled = !this.canSend()
  }

  updateAiActions() {
    if (this.hasRegenerateTarget) {
      this.regenerateTarget.disabled = this.pending || !this.generated ||
        !this.needsRegeneration || !this.goal?.configured || !this.access?.ready
    }
    if (this.hasSendAiTarget) this.sendAiTarget.disabled = !this.canSend()
  }

  // Only successfully persisted instruction/preference changes authorize
  // offering a NEW (explicit, chargeable) generation; editing candidate text
  // alone never unlocks regeneration.
  settingsChanged() {
    if (!this.generated) return
    this.needsRegeneration = true
    this.updateAiActions()
  }

  editSettings() {
    const draft = this.application.getControllerForElementAndIdentifier(
      this.element, "ai-draft")
    draft?.showSettings()
  }

  async regenerate() {
    if (!this.generated || !this.needsRegeneration || this.pending) return
    await this.refresh()
    if (!this.goal?.configured || !this.access?.ready) return
    if (!window.confirm(this.text(
      this.syntheticValue ? "confirmSynthetic" : "confirmSpend"))) return
    await this.generate()
  }

  // Mirror the lower human composer: Enter sends the explicitly selected AI
  // candidate, while Shift+Enter inserts a newline. Never invoke native Send.
  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.ctrlKey ||
        event.altKey || event.metaKey || event.isComposing || event.repeat ||
        window.matchMedia("(pointer: coarse)").matches || !this.canSend()) return
    event.preventDefault()
    this.form?.requestSubmit(this.sendAiTarget)
  }

  resizeCandidate() {
    if (!this.hasCandidateTarget || this.candidateTarget.hidden ||
        this.customAiHeight) return
    const editor = this.candidateTarget
    editor.style.height = "auto"
    const max = Math.max(90, window.innerHeight * .32)
    editor.style.height = Math.min(Math.max(editor.scrollHeight, 60), max) + "px"
  }

  alignTwin() {
    if (!this.hasComposerTarget || this.composerTarget.hidden ||
        this.candidateTarget.hidden) return
    const humanField = this.element.querySelector(
      ".composer-controls .sd-composer-editor-field")
    const humanSend = this.element.querySelector(
      ".composer-controls button.composer-send")
    if (!humanField || !humanSend) return
    const row = this.composerTarget
    const a = row.getBoundingClientRect()
    const field = humanField.getBoundingClientRect()
    const send = humanSend.getBoundingClientRect()
    const gap = Math.max(0, send.left - field.right)
    const right = Math.max(0, a.right - send.right)
    const minEditor = 35
    const maxLeft = Math.max(0, a.width - right - send.width - 2 * gap - minEditor)
    const left = Math.min(Math.max(0, field.left - a.left - gap), maxLeft)
    row.style.setProperty("--sd-ai-twin-left", left + "px")
    row.style.setProperty("--sd-ai-twin-gap", gap + "px")
    row.style.setProperty("--sd-ai-twin-right", right + "px")
    row.style.setProperty("--sd-ai-twin-send-width", send.width + "px")
    row.style.setProperty("--sd-ai-twin-send-height", send.height + "px")
  }

  beginResize(event) {
    if (event.button !== 0 || this.candidateTarget.hidden) return
    event.preventDefault()
    this.drag = {id: event.pointerId, y: event.clientY,
      height: this.candidateTarget.getBoundingClientRect().height}
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  setAiHeight(height) {
    const max = Math.max(90, window.innerHeight * .46)
    this.candidateTarget.style.height =
      Math.min(max, Math.max(60, height)) + "px"
    this.customAiHeight = true
  }

  dragResize(event) {
    if (!this.drag || this.drag.id !== event.pointerId) return
    this.setAiHeight(this.drag.height + this.drag.y - event.clientY)
  }

  endResize(event) {
    if (!this.drag || this.drag.id !== event.pointerId) return
    const grip = event.currentTarget
    if (grip.hasPointerCapture(event.pointerId)) grip.releasePointerCapture(event.pointerId)
    this.drag = null
  }

  resizeWithKeyboard(event) {
    if (!["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key) ||
        this.candidateTarget.hidden) return
    event.preventDefault()
    const h = this.candidateTarget.getBoundingClientRect().height
    const next = event.key === "Home" ? 60 : event.key === "End"
      ? window.innerHeight * .46 : h + (event.key === "ArrowUp" ? 24 : -24)
    this.setAiHeight(next)
  }

  discard() {
    this.generated = null
    this.needsRegeneration = false
    this.customAiHeight = false
    this.aiSubmission = null
    if (this.hasCandidateTarget) {
      this.candidateTarget.value = ""
      this.candidateTarget.hidden = true
    }
    if (this.hasSendAiTarget) this.sendAiTarget.hidden = true
    if (this.hasCandidateLabelTarget) this.candidateLabelTarget.hidden = true
    if (this.hasComposerTarget) this.composerTarget.hidden = true
    if (this.hasCandidateTarget) this.candidateTarget.style.height = ""
    this.updateAiActions()
    if (this.hasResultTarget) {
      this.resultTarget.hidden = true
      delete this.resultTarget.dataset.mode
    }
  }

  async generate() {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || !globalThis.crypto?.randomUUID || !this.hasGenerateUrlValue ||
        !this.goal?.configured || !this.access?.ready) return
    const goalRevision = this.goal.current_revision
    const epoch = ++this.epoch
    this.pending = true
    this.discard()
    this.render()
    this.statusTarget.textContent = this.text("generating")
    try {
      const response = await fetch(this.generateUrlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf},
        body: JSON.stringify({answer: {
          confirmed: "1", draft_text: "", goal_source: "room_instructions",
          expected_goal_revision: goalRevision, request_id: crypto.randomUUID()
        }})
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || "provider_unavailable")
      if (epoch !== this.epoch || !this.element.isConnected) return
      if (data.mode !== "answer" || data.message_sent !== false ||
          data.automatic_send_active !== false || data.goal_revision !== goalRevision ||
          typeof data.text !== "string" || !data.text.trim() || data.text.length > 5000 ||
          typeof data.provenance_token !== "string" || data.provenance_token.length < 20 ||
          !Array.isArray(data.source_ids) || !data.source_ids.length ||
          typeof data.cost_usd !== "string" ||
          data.synthetic !== this.syntheticValue) throw new Error("provider_unavailable")
      if (this.syntheticValue &&
          (data.provider_called !== false || data.budget_reserved !== false ||
           data.cost_usd !== "0.000000" || data.model !== "synthetic-local-no-ai")) {
        throw new Error("provider_unavailable")
      }
      if (!this.syntheticValue &&
          (data.provider_called !== true || data.budget_reserved !== true)) {
        throw new Error("provider_unavailable")
      }
      this.generated = {source: data.text, proof: data.provenance_token,
        goalRevision, sourceIds: data.source_ids}
      this.resultHeadingTarget.textContent =
        this.text(this.syntheticValue ? "syntheticResultTitle" : "aiResultTitle")
      this.resultTextTarget.textContent =
        this.text(this.syntheticValue ? "syntheticResultMeta" : "aiResultMeta", {
          model: data.model || "xAI", cost: data.cost_usd,
          count: data.source_ids.length
        })
      // The diagnostics remain available on hover, not above the editor.
      if (this.hasSettingsTarget) {
        this.settingsTarget.title = this.text("editSettings") + " · " +
          this.text("auditTooltip", {model: data.model, cost: data.cost_usd,
            count: data.source_ids.length})
      }
      this.resultTarget.dataset.costUsd = data.cost_usd
      this.resultTarget.dataset.sourceCount = String(data.source_ids.length)
      this.candidateTarget.value = data.text
      this.candidateTarget.hidden = false
      this.candidateLabelTarget.hidden = false
      this.composerTarget.hidden = false
      this.sendAiTarget.hidden = false
      this.sendAiTarget.disabled = !this.canSend()
      this.resultTarget.dataset.mode = "candidate"
      this.resultTarget.hidden = false
      this.resizeCandidate()
      this.alignTwin()
      this.statusTarget.textContent = this.text(this.syntheticValue ? "syntheticCandidateReady" : "candidateReady")
      this.updateAiActions()
    } catch (e) {
      if (epoch !== this.epoch || !this.element.isConnected) return
      const key = ["context_consent_required", "invalid_or_stale_input",
        "budget_unavailable", "provider_unavailable"].includes(e.message) ?
        e.message : "provider_unavailable"
      this.statusTarget.textContent = this.text(key)
    } finally {
      const finalMessage = this.statusTarget.textContent
      this.pending = false
      this.render()
      if (epoch === this.epoch) this.statusTarget.textContent =
        this.generated ? this.text(this.syntheticValue ? "syntheticCandidateReady" : "candidateReady") : finalMessage
      if (this.hasSendAiTarget) this.sendAiTarget.disabled = !this.canSend()
    }
  }

  beforeSubmit(event) {
    this.aiSubmission = null
    if (event.submitter !== this.sendAiTarget) return
    if (event.defaultPrevented || !this.canSend()) {
      event.preventDefault()
      return
    }
    this.aiSubmission = {
      body: this.candidateTarget.value,
      source: this.generated.source,
      proof: this.generated.proof
    }
  }

  formData(event) {
    if (!this.aiSubmission) return
    event.formData.set("message[send_variant]", "ai")
    event.formData.set("message[ai_body]", this.aiSubmission.body)
    event.formData.set("message[ai_source]", this.aiSubmission.source)
    event.formData.set("message[ai_proof]", this.aiSubmission.proof)
  }

  submitEnd(event) {
    this.aiSubmission = null
    if (event.detail.success) this.discard()
  }
}
