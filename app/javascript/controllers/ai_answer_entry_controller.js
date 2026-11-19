import { Controller } from "@hotwired/stimulus"

// S1 on Quiet Depth: explicit AI Answer entry, personal goal + unanimous context
// permissions, and a provider-free S3 dry-run. It NEVER triggers Send or paid AI.
export default class extends Controller {
  static targets = ["trigger", "status", "consent", "consentStatus", "result", "resultText", "resultHeading", "candidate", "sendAi", "body"]
  static values = { goalUrl: String, consentUrl: String, previewUrl: String, generateUrl: String, copy: Object }

  connect() {
    this.epoch = 0
    this.pending = false
    this.goal = null
    this.access = null
    this.generated = null
    this.aiSubmission = null
    this.form = this.element.querySelector("form.message-composer")
    this.boundFormData = event => this.formData(event)
    this.form?.addEventListener("formdata", this.boundFormData)
    this.changed()
    this.refresh()
  }

  disconnect() {
    this.epoch += 1
    this.form?.removeEventListener("formdata", this.boundFormData)
  }

  editor() { return this.bodyTarget }
  text(key, data = {}) {
    let msg = this.copyValue[key] || key
    for (const [k, v] of Object.entries(data)) msg = msg.replaceAll("{" + k + "}", String(v))
    return msg
  }

  changed() {
    // Never keep an AI candidate after the human editor changes or Send resets.
    if (this.editor().value.trim() || this.generated) {
      ++this.epoch
      this.generated = null
      if (this.hasCandidateTarget) this.candidateTarget.value = ""
      if (this.hasCandidateTarget) this.candidateTarget.hidden = true
      if (this.hasSendAiTarget) this.sendAiTarget.hidden = true
    }
    if (this.hasResultTarget) this.resultTarget.hidden = true
    this.element.dataset.aiComposerMode = this.editor().value.trim() ? "beautify" : "answer"
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
      if (this.generated && (!access.ready ||
          goal.current_revision !== this.generated.goalRevision)) this.discard()
      this.render()
    } catch (_) {
      if (epoch !== this.epoch || !this.element.isConnected) return
      this.statusTarget.textContent = this.text("unavailable")
      this.statusTarget.dataset.state = "error"
    }
  }

  render() {
    this.triggerTarget.disabled = this.pending
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
      label = this.hasGenerateUrlValue ? this.text("paidReady") : this.text("dryRunReady")
      state = "ready"
    }
    this.statusTarget.textContent = label
    this.statusTarget.dataset.state = state
    this.triggerTarget.title = this.text("buttonHint") + " · " + label
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
      if (!window.confirm(this.text("confirmSpend"))) return
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
    return !this.pending && this.generated !== null &&
      !this.editor().value.trim() && candidate.trim().length > 0 &&
      candidate.length <= 5000 && new TextEncoder().encode(candidate).length <= 20000
  }

  candidateChanged() {
    this.sendAiTarget.disabled = !this.canSend()
  }

  discard() {
    this.generated = null
    this.aiSubmission = null
    if (this.hasCandidateTarget) {
      this.candidateTarget.value = ""
      this.candidateTarget.hidden = true
    }
    if (this.hasSendAiTarget) this.sendAiTarget.hidden = true
    if (this.hasResultTarget) this.resultTarget.hidden = true
  }

  async generate() {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || !globalThis.crypto?.randomUUID || !this.hasGenerateUrlValue ||
        !this.goal?.configured || !this.access?.ready || this.editor().value.trim()) return
    const original = this.editor().value
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
          confirmed: "1", draft_text: original, goal_source: "room_instructions",
          expected_goal_revision: goalRevision, request_id: crypto.randomUUID()
        }})
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || "provider_unavailable")
      if (epoch !== this.epoch || !this.element.isConnected ||
          this.editor().value !== original) return
      if (data.mode !== "answer" || data.message_sent !== false ||
          data.automatic_send_active !== false || data.goal_revision !== goalRevision ||
          typeof data.text !== "string" || !data.text.trim() || data.text.length > 5000 ||
          typeof data.provenance_token !== "string" || data.provenance_token.length < 20 ||
          !Array.isArray(data.source_ids) || !data.source_ids.length ||
          typeof data.cost_usd !== "string") throw new Error("provider_unavailable")
      this.generated = {source: data.text, proof: data.provenance_token,
        goalRevision, sourceIds: data.source_ids}
      this.resultHeadingTarget.textContent = this.text("aiResultTitle")
      this.resultTextTarget.textContent =
        this.text("aiResultMeta", {model: data.model || "xAI",
          cost: data.cost_usd, count: data.source_ids.length})
      this.candidateTarget.value = data.text
      this.candidateTarget.hidden = false
      this.sendAiTarget.hidden = false
      this.sendAiTarget.disabled = !this.canSend()
      this.resultTarget.hidden = false
      this.statusTarget.textContent = this.text("candidateReady")
    } catch (e) {
      if (epoch !== this.epoch || !this.element.isConnected) return
      const key = ["context_consent_required", "invalid_or_stale_input",
        "budget_unavailable", "provider_unavailable"].includes(e.message) ?
        e.message : "provider_unavailable"
      this.statusTarget.textContent = this.text(key)
    } finally {
      this.pending = false
      this.render()
      if (epoch === this.epoch) this.statusTarget.textContent =
        this.generated ? this.text("candidateReady") : this.statusTarget.textContent
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
