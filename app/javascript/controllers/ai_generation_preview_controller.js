import { Controller } from "@hotwired/stimulus"

// Read-only S3 input inspection. Never calls model, replaces editor, applies
// a candidate, or submits a message. Preview is not an outbound authorization.
export default class extends Controller {
  static targets = ["answer", "beautify", "status", "result"]
  static values = { url: String, goalUrl: String, copy: Object }

  connect() {
    this.busy = false
    this.sequence = 0
    this.render()
  }

  disconnect() { ++this.sequence }

  editor() {
    return this.element.closest(".msg-form")?.querySelector("form.message-composer #chat-text")
  }

  render() {
    this.answerTarget.disabled = this.busy
    this.beautifyTarget.disabled = this.busy
  }

  answer() { this.preview("answer") }
  beautify() { this.preview("beautify") }

  async preview(mode) {
    if (this.busy) return
    const editor = this.editor()
    if (!editor) return this.showError(this.copyValue.unavailable)
    const draft = editor.value
    if (mode === "answer" && draft.trim()) return this.showError(this.copyValue.emptyRequired)
    if (mode === "beautify" && !draft.trim()) return this.showError(this.copyValue.draftRequired)

    const sequence = ++this.sequence
    this.busy = true
    this.render()
    this.resultTarget.hidden = true
    this.statusTarget.textContent = this.copyValue.checking
    try {
      const preview = { mode, draft_text: draft }
      if (mode === "answer") {
        const goalResponse = await fetch(this.goalUrlValue, {
          credentials: "same-origin", cache: "no-store",
          headers: { Accept: "application/json" }
        })
        if (!goalResponse.ok) throw new Error("unavailable")
        const goal = await goalResponse.json()
        if (!goal.configured || !Number.isInteger(goal.current_revision) ||
            goal.current_revision < 1) throw new Error("goal")
        preview.expected_goal_revision = goal.current_revision
      }
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content
      if (!csrf) throw new Error("unavailable")
      const response = await fetch(this.urlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { "Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf },
        body: JSON.stringify({ preview })
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || "unavailable")
      if (sequence !== this.sequence || !this.element.isConnected) return
      if (data.mode !== mode || data.provider_called !== false ||
          data.budget_reserved !== false || data.message_sent !== false ||
          data.automatic_send_active !== false ||
          !Array.isArray(data.source_ids)) throw new Error("unavailable")
      const lines = [
        this.copyValue.mode + ": " + mode,
        this.copyValue.sources + ": " + data.source_ids.length,
        this.copyValue.fingerprint + ": " + data.fingerprint.slice(0, 16)
      ]
      if (data.goal_purpose) lines.push(this.copyValue.goal + ": " + data.goal_purpose)
      if (data.draft_preview) lines.push(this.copyValue.draft + ":\n" + data.draft_preview)
      for (const source of (data.sources || [])) {
        lines.push(source.ref + " / " + source.speaker + ":\n" + source.text)
      }
      this.resultTarget.textContent = lines.join("\n\n")
      this.resultTarget.hidden = false
      this.statusTarget.textContent = this.copyValue.ready
    } catch (error) {
      if (sequence !== this.sequence || !this.element.isConnected) return
      const key = error.message === "goal" ? "goalMissing" :
        error.message === "context_consent_required" ? "consentMissing" :
        error.message === "invalid_or_stale_input" ? "invalid" : "unavailable"
      this.showError(this.copyValue[key])
    } finally {
      if (sequence === this.sequence) { this.busy = false; this.render() }
    }
  }

  showError(message) {
    this.resultTarget.hidden = true
    this.statusTarget.textContent = message
  }
}
