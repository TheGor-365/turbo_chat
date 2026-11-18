import { Controller } from "@hotwired/stimulus"

// Personal goal metadata only: no AI request, no room-history consent and
// no Send. Revision conflicts never silently replace unsaved human edits.
const CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u202A-\u202E\u2066-\u2069]/
const SECRET = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|xai-[A-Za-z0-9_-]{20,})\b/i

export default class extends Controller {
  static targets = ["purpose", "constraints", "outcome", "save", "disable",
    "reload", "version", "status"]
  static values = { url: String, copy: Object }

  connect() {
    this.revision = 0
    this.configured = false
    this.saved = null
    this.pending = false
    this.loaded = false
    this.conflict = false
    this.dirty = false
    this.generation = 0
    this.refresh()
    this.load()
  }

  disconnect() {
    this.generation += 1
  }

  formValues() {
    return { purpose: this.purposeTarget.value.trim(),
      constraints: this.constraintsTarget.value.trim(),
      desired_outcome: this.outcomeTarget.value.trim() }
  }

  validate(values = this.formValues()) {
    if (!values.purpose || values.purpose.length > 500 ||
        values.constraints.length > 1000 || values.desired_outcome.length > 500) return false
    return Object.values(values).every(text => !CONTROL.test(text) && !SECRET.test(text))
  }

  changed() {
    this.dirty = true
    if (!this.conflict) this.statusTarget.textContent = this.copyValue.unsaved
    this.refresh()
  }

  refresh() {
    const values = this.formValues()
    const unchanged = this.configured && this.saved &&
      JSON.stringify(values) === JSON.stringify(this.saved)
    this.saveTarget.disabled = !this.loaded || this.pending || this.conflict ||
      !this.validate(values) || unchanged
    this.disableTarget.disabled = !this.loaded || this.pending || this.conflict || !this.configured
    this.reloadTarget.hidden = !this.conflict
    this.versionTarget.textContent = this.copyValue.version.replace("{revision}", String(this.revision))
  }

  async load() {
    const generation = ++this.generation
    this.pending = true
    this.refresh()
    try {
      const response = await fetch(this.urlValue, {
        credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error("load_failed")
      const result = await response.json()
      if (generation !== this.generation || !this.element.isConnected) return
      if (!Number.isSafeInteger(result.current_revision) || result.current_revision < 0) {
        throw new Error("invalid_revision")
      }
      this.revision = result.current_revision
      this.configured = result.configured === true
      this.saved = this.configured ? {
        purpose: String(result.goal?.purpose || ""),
        constraints: String(result.goal?.constraints || ""),
        desired_outcome: String(result.goal?.desired_outcome || "")
      } : null
      // If an initial GET races with human typing, the human text wins.
      if (!this.dirty) {
        this.purposeTarget.value = this.saved?.purpose || ""
        this.constraintsTarget.value = this.saved?.constraints || ""
        this.outcomeTarget.value = this.saved?.desired_outcome || ""
      }
      this.conflict = false
      this.loaded = true
      this.statusTarget.textContent = this.configured
        ? this.copyValue.loaded : this.copyValue.none
    } catch (_) {
      if (generation === this.generation) {
        this.loaded = false
        this.statusTarget.textContent = this.copyValue.load_error
      }
    } finally {
      if (generation === this.generation) {
        this.pending = false
        this.refresh()
      }
    }
  }

  reload() {
    // Explicitly replaces the local unsaved goal editor after a conflict.
    this.dirty = false
    this.conflict = false
    this.load()
  }

  async save() {
    if (this.saveTarget.disabled) return
    const values = this.formValues()
    if (!this.validate(values)) return
    await this.write("PATCH", { goal: { ...values, base_revision: this.revision } })
  }

  async disable() {
    if (this.disableTarget.disabled) return
    await this.write("DELETE", { goal: { base_revision: this.revision } })
  }

  async write(method, payload) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || this.pending || this.conflict) {
      this.statusTarget.textContent = this.copyValue.save_error
      return
    }
    this.pending = true
    this.refresh()
    try {
      const response = await fetch(this.urlValue, {
        method, credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf },
        body: JSON.stringify(payload)
      })
      if (response.status === 409) {
        this.conflict = true
        this.statusTarget.textContent = this.copyValue.conflict
        return
      }
      if (!response.ok) throw new Error("write_failed")
      const result = await response.json()
      if (!Number.isSafeInteger(result.current_revision) ||
          result.current_revision <= this.revision) {
        // No-op saves return the same revision, never a lower one.
        if (result.current_revision !== this.revision) throw new Error("bad_revision")
      }
      this.revision = result.current_revision
      this.configured = result.configured === true
      if (this.configured) {
        this.saved = {purpose: result.goal.purpose, constraints: result.goal.constraints,
          desired_outcome: result.goal.desired_outcome}
      } else {
        this.saved = null
      }
      this.dirty = false
      this.statusTarget.textContent = this.configured
        ? this.copyValue.saved : this.copyValue.disabled
      // Never touch the chat composer or enable AI Answer here.
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.save_error
    } finally {
      this.pending = false
      this.refresh()
    }
  }
}
