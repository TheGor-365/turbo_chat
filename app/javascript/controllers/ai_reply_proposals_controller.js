import { Controller } from "@hotwired/stimulus"

// S7-A: explicit offline template -> server-checked Apply -> existing human Send.
// The controller never submits a chat form or marks a template as model-made.
export default class extends Controller {
  static targets = ["create", "apply", "dismiss", "candidate", "status"]
  static values = { url: String, language: String, copy: Object }

  connect() {
    this.busy = false
    this.ready = false
    this.entry = null
    this.sequence = 0
    this.render()
    this.load()
  }

  disconnect() { ++this.sequence }

  editor() {
    return this.element.closest(".msg-form")?.querySelector("form.message-composer #chat-text")
  }

  render() {
    this.createTarget.disabled = this.busy || !this.ready
    const valid = this.entry && ["pending", "applied"].includes(this.entry.state) &&
      this.entry.origin === "offline_template" && this.entry.provider_called === false &&
      this.entry.ai_assisted === false && typeof this.entry.body === "string"
    this.applyTarget.disabled = this.busy || !this.ready || !valid
    this.dismissTarget.disabled = this.busy || !this.ready || !valid ||
      this.entry.state !== "pending"
    this.candidateTarget.hidden = !valid
    this.candidateTarget.textContent = valid ? this.entry.body : ""
  }

  async load() {
    const seq = ++this.sequence
    this.busy = true
    this.render()
    try {
      const response = await fetch(this.urlValue, {
        credentials: "same-origin", cache: "no-store",
        headers: {Accept: "application/json"}
      })
      if (!response.ok) throw new Error("unavailable")
      const data = await response.json()
      if (seq !== this.sequence || !this.element.isConnected) return
      this.entry = data.proposal || null
      this.ready = true
      this.statusTarget.textContent = this.entry ? this.copyValue.loaded : this.copyValue.empty
    } catch (_) {
      if (seq === this.sequence) {
        this.ready = true
        this.entry = null
        this.statusTarget.textContent = this.copyValue.unavailable
      }
    } finally {
      if (seq === this.sequence) { this.busy = false; this.render() }
    }
  }

  async create() {
    if (this.busy || !this.ready) return
    await this.request("POST", this.urlValue, {
      proposal: {language: this.languageValue}
    }, this.copyValue.created)
  }

  async dismiss() {
    if (this.busy || !this.entry || this.entry.state !== "pending") return
    await this.request("DELETE", this.urlValue + "/" + encodeURIComponent(this.entry.id),
      null, this.copyValue.dismissed)
  }

  async apply() {
    if (this.busy || !this.entry) return
    const editor = this.editor()
    if (!editor || editor.value.trim()) {
      this.statusTarget.textContent = this.copyValue.nonempty
      return
    }
    const id = this.entry.id
    const textBefore = editor.value
    const success = await this.request("PATCH",
      this.urlValue + "/" + encodeURIComponent(id) + "/apply",
      null, this.copyValue.applied)
    if (!success || !this.entry || this.entry.id !== id ||
        this.entry.provider_called !== false || this.entry.ai_assisted !== false ||
        this.entry.origin !== "offline_template" || editor.value !== textBefore) {
      return
    }

    // Set only the canonical HUMAN draft; no synthetic click, requestSubmit,
    // AI provenance token, or hidden send_variant.
    editor.value = this.entry.body
    editor.dispatchEvent(new Event("input", {bubbles: true}))
    const root = this.element.closest(".msg-form")
    const workspace = root && this.application.getControllerForElementAndIdentifier(root, "ai-draft")
    workspace?.closeSettings()
    editor.focus()
    this.statusTarget.textContent = this.copyValue.applied
  }

  async request(method, url, payload, successMessage) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf) { this.statusTarget.textContent = this.copyValue.unavailable; return false }
    this.busy = true
    this.render()
    try {
      const response = await fetch(url, {
        method, credentials: "same-origin",
        headers: {Accept: "application/json", "Content-Type": "application/json",
          "X-CSRF-Token": csrf},
        ...(payload ? {body: JSON.stringify(payload)} : {})
      })
      if (!response.ok) throw new Error("request_failed")
      if (method === "DELETE") {
        this.entry = null
      } else {
        const data = await response.json()
        if (!data.proposal || data.proposal.provider_called !== false ||
            data.proposal.origin !== "offline_template") throw new Error("invalid_origin")
        this.entry = data.proposal
      }
      this.statusTarget.textContent = successMessage
      return true
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.unavailable
      return false
    } finally {
      this.busy = false
      this.render()
    }
  }
}
