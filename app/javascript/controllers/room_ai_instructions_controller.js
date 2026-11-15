import { Controller } from "@hotwired/stimulus"

// Human-saved room text only. Nothing here authorizes provider access,
// attaches chat history, runs xAI, or submits the surrounding message form.
export default class extends Controller {
  static targets = [
    "editor", "counter", "revision", "save", "status", "history",
    "historyToggle", "conflict", "conflictSummary"
  ]
  static values = {
    url: String, historyUrl: String, revision: Number,
    canEdit: Boolean, copy: Object
  }

  connect() {
    this.lastSaved = this.editorTarget.value
    this.pending = false
    this.serverConflict = null
    this.showCount()
    this.refreshSave()
  }

  changed() {
    this.serverConflict = null
    this.conflictTarget.hidden = true
    this.showCount()
    this.refreshSave()
    this.statusTarget.textContent = this.dirty() ? this.copyValue.unsaved : ""
  }

  dirty() { return this.editorTarget.value.trim() !== this.lastSaved }
  showCount() {
    this.counterTarget.textContent =
      this.editorTarget.value.length + " / " + this.editorTarget.maxLength
  }
  refreshSave() {
    if (this.hasSaveTarget) this.saveTarget.disabled =
      !this.canEditValue || this.pending || !this.dirty()
  }

  async save() {
    if (!this.canEditValue || !this.dirty() || this.pending) return
    const text = this.editorTarget.value
    const revision = this.revisionValue
    this.pending = true
    this.refreshSave()
    this.statusTarget.textContent = this.copyValue.saving
    try {
      const token = document.querySelector("meta[name='csrf-token']")?.content
      if (!token) throw new Error(this.copyValue.request_error)
      const response = await fetch(this.urlValue, {
        method: "PATCH", credentials: "same-origin",
        headers: { "Accept": "application/json", "Content-Type": "application/json",
          "X-CSRF-Token": token },
        body: JSON.stringify({ instruction: { content: text, base_revision: revision } })
      })
      const result = await response.json().catch(() => ({}))
      if (response.status === 409) {
        this.serverConflict = result
        this.conflictTarget.hidden = false
        this.conflictSummaryTarget.textContent = this.copyValue.conflict
        this.statusTarget.textContent = this.copyValue.conflict
        return
      }
      if (!response.ok) {
        this.statusTarget.textContent = response.status === 403 ?
          this.copyValue.forbidden : this.copyValue.request_error
        return
      }
      this.revisionValue = Number(result.current_revision || 0)
      this.revisionTarget.textContent = this.copyValue.version
        .replace("%{count}", this.revisionValue)
      this.lastSaved = result.current?.content || ""
      if (this.editorTarget.value === text) this.editorTarget.value = this.lastSaved
      this.statusTarget.textContent = this.dirty() ? this.copyValue.unsaved : this.copyValue.saved
      this.showCount()
      this.historyTarget.hidden = true
      this.historyToggleTarget.setAttribute("aria-expanded", "false")
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.network_error
    } finally {
      this.pending = false
      this.refreshSave()
    }
  }

  // Conflict reconciliation is always explicit: keep the user's edited text,
  // or restore the server text without silently overwriting it.
  rebaseDraft() {
    if (!this.serverConflict) return
    this.revisionValue = Number(this.serverConflict.current_revision || 0)
    this.lastSaved = this.serverConflict.current?.content || ""
    this.revisionTarget.textContent = this.copyValue.version
      .replace("%{count}", this.revisionValue)
    this.conflictTarget.hidden = true
    this.serverConflict = null
    this.statusTarget.textContent = this.copyValue.rebased
    this.refreshSave()
  }

  useServer() {
    if (!this.serverConflict) return
    this.rebaseDraft()
    this.editorTarget.value = this.lastSaved
    this.statusTarget.textContent = this.copyValue.server_restored
    this.showCount()
    this.refreshSave()
  }

  async toggleHistory() {
    if (!this.historyTarget.hidden) {
      this.historyTarget.hidden = true
      this.historyToggleTarget.setAttribute("aria-expanded", "false")
      return
    }
    this.historyTarget.hidden = false
    this.historyToggleTarget.setAttribute("aria-expanded", "true")
    this.historyTarget.textContent = this.copyValue.loading
    try {
      const response = await fetch(this.historyUrlValue, {
        credentials: "same-origin", headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error("Failed to fetch")
      const result = await response.json()
      if (!this.element.isConnected || this.historyTarget.hidden) return
      this.renderHistory(result.history || [])
    } catch (_) {
      this.historyTarget.textContent = this.copyValue.network_error
    }
  }

  renderHistory(history) {
    this.historyTarget.replaceChildren()
    if (!history.length) {
      this.historyTarget.textContent = this.copyValue.no_history
      return
    }
    for (const revision of history) {
      const section = document.createElement("details")
      section.className = "sd-room-ai-instructions__history-entry"
      const summary = document.createElement("summary")
      const label = this.copyValue.version.replace("%{count}", revision.revision_number)
      const date = new Date(revision.updated_at)
      summary.textContent = label + " · " + revision.editor +
        (Number.isNaN(date.valueOf()) ? "" : " · " + date.toLocaleString())
      const content = document.createElement("pre")
      content.textContent = revision.content || this.copyValue.empty_version
      section.append(summary, content)
      if (this.canEditValue) {
        const button = document.createElement("button")
        button.type = "button"
        button.className = "sd-room-ai-instructions__history-button"
        button.textContent = this.copyValue.copy_version
        button.addEventListener("click", () => {
          this.editorTarget.value = revision.content || ""
          this.changed()
          this.editorTarget.focus()
        })
        section.append(button)
      }
      this.historyTarget.append(section)
    }
  }
}
