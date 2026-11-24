import { Controller } from "@hotwired/stimulus"

// Shared defaults are a separate owner-controlled full snapshot. Do not
// copy the values into personal settings or treat them as an AI permission.
export default class extends Controller {
  static targets = ["fields", "profile", "style", "language", "tone", "save", "status"]
  static values = { url: String, defaults: Object, messages: Object }

  connect() {
    this.active = true
    this.snapshot = null
    this.refresh()
  }

  disconnect() {
    this.active = false
    this.request?.abort()
  }

  refresh() { return this.load(false) }
  save() {
    if (!this.snapshot?.editable || this.request) return
    return this.load(true)
  }

  profileChanged() {
    const selected = this.profileTarget.selectedOptions[0]
    if (!selected?.value) return
    this.styleTarget.value = selected.dataset.style
    this.toneTarget.value = selected.dataset.tone
  }

  styleChanged() { this.profileTarget.value = "" }

  get controls() { return [this.profileTarget, this.styleTarget, this.languageTarget, this.toneTarget] }

  async load(write) {
    if (!this.active || this.request) return
    const request = new AbortController()
    this.request = request
    this.controls.forEach(control => control.disabled = true)
    this.saveTarget.disabled = true
    let feedback = ""
    try {
      const headers = { Accept: "application/json" }
      const options = { credentials: "same-origin", cache: "no-store", headers, signal: request.signal }
      if (write) {
        const csrf = document.querySelector('meta[name="csrf-token"]')?.content
        if (!csrf) throw new Error("Missing CSRF")
        options.method = "PATCH"
        headers["X-CSRF-Token"] = csrf
        headers["Content-Type"] = "application/json"
        options.body = JSON.stringify({ expected_revision: this.snapshot.revision,
          preference: { profile_id: this.profileTarget.value || null,
            writing_style: this.styleTarget.value, language: this.languageTarget.value,
            tone: this.toneTarget.value } })
      }
      let response = await fetch(this.urlValue, options)
      if (write && response.status === 409) {
        response = await fetch(this.urlValue, { credentials: "same-origin", cache: "no-store",
          headers: { Accept: "application/json" }, signal: request.signal })
        feedback = "conflict"
      } else if (write) feedback = "saved"
      if (!response.ok || response.redirected) throw new Error("Unavailable")
      const snapshot = await response.json()
      if (typeof snapshot.configured !== "boolean" || typeof snapshot.editable !== "boolean" ||
          !Number.isSafeInteger(snapshot.revision) || snapshot.revision < 0 ||
          snapshot.configured !== (snapshot.revision > 0) ||
          (!snapshot.configured && snapshot.preference !== null)) throw new Error("Invalid snapshot")
      const values = snapshot.configured ? snapshot.preference : this.defaultsValue
      const selected = [values?.profile_id === null ? "" : values?.profile_id,
        values?.writing_style, values?.language, values?.tone]
      if (!this.controls.every((control, index) =>
        Array.from(control.options).some(option => option.value === selected[index]))) throw new Error("Invalid preference")
      if (!this.active || request.signal.aborted) return
      this.snapshot = snapshot
      this.controls.forEach((control, index) => control.value = selected[index])
      this.fieldsTarget.hidden = !snapshot.configured && !snapshot.editable
      this.saveTarget.hidden = !snapshot.editable
      this.statusTarget.textContent = this.messagesValue[feedback || (snapshot.configured ? "configured" : "unconfigured")]
    } catch (error) {
      if (!this.active || request.signal.aborted) return
      this.snapshot = null
      this.fieldsTarget.hidden = true
      this.saveTarget.hidden = true
      this.statusTarget.textContent = this.messagesValue.unavailable
    } finally {
      if (this.active && this.request === request) {
        this.request = null
        this.controls.forEach(control => control.disabled = !this.snapshot?.editable)
        this.saveTarget.disabled = !this.snapshot?.editable
      }
    }
  }
}
