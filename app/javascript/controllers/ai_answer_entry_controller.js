import { Controller } from "@hotwired/stimulus"

// S1 on Quiet Depth: explicit AI Answer entry, personal goal + unanimous context
// permissions, and a provider-free S3 dry-run. It NEVER triggers Send or paid AI.
export default class extends Controller {
  static targets = ["trigger", "status", "consent", "consentStatus", "result", "resultText", "body"]
  static values = { goalUrl: String, consentUrl: String, previewUrl: String, copy: Object }

  connect() {
    this.epoch = 0
    this.pending = false
    this.goal = null
    this.access = null
    this.changed()
    this.refresh()
  }

  disconnect() { this.epoch += 1 }

  editor() { return this.bodyTarget }
  text(key, data = {}) {
    let msg = this.copyValue[key] || key
    for (const [k, v] of Object.entries(data)) msg = msg.replaceAll("{" + k + "}", String(v))
    return msg
  }

  changed() {
    // A stale output must never survive editing the human draft.
    if (this.hasResultTarget) this.resultTarget.hidden = true
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
      label = this.text("dryRunReady")
      state = "ready"
    }
    this.statusTarget.textContent = label
    this.statusTarget.dataset.state = state
    this.triggerTarget.title = this.text("buttonHint") + " · " + label
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
      this.openSettings(".sd-ai-conversation-goal", "#ai-conversation-goal-purpose")
      return
    }
    if (!this.access.ready) {
      this.openSettings(".sd-ai-answer-consent", "[data-ai-answer-entry-target='consent']")
      return
    }
    await this.preview()
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
      this.resultTarget.hidden = true
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
    this.resultTarget.hidden = true
    this.statusTarget.textContent = this.text("preparing")
    try {
      const res = await fetch(this.previewUrlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf},
        body: JSON.stringify({preview: {mode: "answer", draft_text: original,
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
}
