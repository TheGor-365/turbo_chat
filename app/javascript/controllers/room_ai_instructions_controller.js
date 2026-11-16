import { Controller } from "@hotwired/stimulus"

// Human-saved room text only. Nothing here authorizes provider access,
// attaches chat history, runs xAI, or submits the surrounding message form.
export default class extends Controller {
  static targets = [
    "editor", "counter", "revision", "save", "status", "history",
    "historyToggle", "historyShell", "conflict", "conflictSummary",
    "currentPreview", "currentText", "currentVersion",
    "templateName", "templateList", "templateStatus"
  ]
  static values = {
    url: String, historyUrl: String, revision: Number,
    canEdit: Boolean, copy: Object, userId: Number, roomId: Number
  }

  connect() {
    this.lastSaved = this.hasCurrentTextTarget
      ? this.currentTextTarget.textContent : this.editorTarget.value
    this.composingFresh = this.canEditValue && this.editorTarget.value.trim().length === 0
    this.pending = false
    this.serverConflict = null
    this.historyRequestId = 0
    this.setHistoryOpen(false)
    this.setConflictOpen(false)
    this.showCount()
    this.refreshSave()
    this.loadTemplates()
  }

  get templateStorageKey() {
    return `turbo-chat:room-instruction-templates:v1:user:${this.userIdValue}:room:${this.roomIdValue}`
  }

  loadTemplates() {
    if (!this.canEditValue || !this.hasTemplateListTarget) return
    this.templates = []
    this.selectedTemplateId = null
    try {
      const saved = JSON.parse(window.localStorage.getItem(this.templateStorageKey) || "[]")
      if (Array.isArray(saved)) {
        this.templates = saved.filter(entry =>
          Number.isSafeInteger(entry?.id) && entry.id > 0 &&
          typeof entry.name === "string" && entry.name.length <= 60 &&
          typeof entry.content === "string" && entry.content.length <= 4000
        ).slice(0, 12)
      }
    } catch (_) {
      this.templateStatusTarget.textContent = this.copyValue.template_storage_error
    }
    this.renderTemplates()
  }

  persistTemplates(next) {
    try {
      window.localStorage.setItem(this.templateStorageKey, JSON.stringify(next))
      this.templates = next
      this.renderTemplates()
      return true
    } catch (_) {
      this.templateStatusTarget.textContent = this.copyValue.template_storage_error
      return false
    }
  }

  validTemplateContent(content) {
    const value = content.trim()
    if (!value || value.length > 4000 || new TextEncoder().encode(value).length > 16000) return false
    if (/[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F\\u202A-\\u202E\\u2066-\\u2069]/.test(value)) return false
    // This is only client-side hygiene; server validation is authoritative.
    return !/\\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,}|xai-[A-Za-z0-9_-]{20,})\\b/.test(value)
  }

  saveTemplate() {
    if (!this.canEditValue || this.pending || !this.hasTemplateNameTarget || !this.hasTemplateListTarget) return
    const content = this.editorTarget.value.trim()
    if (!this.validTemplateContent(content)) {
      this.templateStatusTarget.textContent = this.copyValue.template_invalid
      return
    }
    const id = Math.max(0, ...this.templates.map(entry => entry.id)) + 1
    const name = this.templateNameTarget.value.trim() ||
      this.copyValue.template_default.replace("%{count}", String(id))
    if (name.length > 60 || this.templates.some(entry => entry.name.toLocaleLowerCase() === name.toLocaleLowerCase())) {
      this.templateStatusTarget.textContent = this.copyValue.template_duplicate
      return
    }
    if (this.templates.length >= 12) {
      this.templateStatusTarget.textContent = this.copyValue.template_limit
      return
    }
    if (!this.persistTemplates([...this.templates, { id, name, content }])) return
    // A local save NEVER calls the room instructions PATCH endpoint or Grok.
    this.templateNameTarget.value = name
    this.templateStatusTarget.textContent = this.copyValue.template_saved
  }

  newTemplate() {
    if (!this.canEditValue || this.pending) return
    if (this.dirty() && !window.confirm(this.copyValue.template_confirm_discard)) return
    this.editorTarget.value = ""
    this.templateNameTarget.value = ""
    this.selectedTemplateId = null
    this.composingFresh = true
    this.changed()
    this.renderTemplates()
    this.templateStatusTarget.textContent = this.copyValue.template_new_ready
    this.editorTarget.focus()
  }

  applyTemplate(id) {
    const entry = this.templates.find(row => row.id === id)
    if (!this.canEditValue || !entry || this.pending) return
    if (this.dirty() && this.editorTarget.value !== entry.content &&
        !window.confirm(this.copyValue.template_confirm_discard)) return
    // Load into the human-controlled draft only. Saving to shared room
    // remains an additional explicit, revision-checked PATCH.
    this.editorTarget.value = entry.content
    this.templateNameTarget.value = entry.name
    this.composingFresh = false
    this.changed()
    this.selectedTemplateId = id
    this.renderTemplates()
    this.templateStatusTarget.textContent = this.copyValue.template_selected
    this.editorTarget.focus()
  }

  deleteTemplate(id) {
    const entry = this.templates.find(row => row.id === id)
    if (!this.canEditValue || !entry || this.pending) return
    if (!window.confirm(this.copyValue.template_confirm_delete.replace("%{name}", entry.name))) return
    if (!this.persistTemplates(this.templates.filter(row => row.id !== id))) return
    if (this.selectedTemplateId === id) this.selectedTemplateId = null
    this.templateStatusTarget.textContent = this.copyValue.template_deleted
  }

  renderTemplates() {
    if (!this.hasTemplateListTarget) return
    const fragment = document.createDocumentFragment()
    if (!this.templates?.length) {
      const empty = document.createElement("p")
      empty.className = "sd-room-ai-instructions__template-empty"
      empty.textContent = this.copyValue.template_empty
      fragment.append(empty)
    }
    this.templates?.forEach(entry => {
      const panel = document.createElement("details")
      panel.className = "sd-room-ai-instructions__template-card"
      if (this.selectedTemplateId === entry.id) panel.dataset.selected = "true"
      const summary = document.createElement("summary")
      const number = document.createElement("span")
      number.className = "sd-room-ai-instructions__template-number"
      number.textContent = `#${entry.id}`
      const title = document.createElement("strong")
      title.textContent = entry.name
      summary.append(number, title)
      const preview = document.createElement("pre")
      preview.textContent = entry.content // Never parse user-authored HTML.
      const actions = document.createElement("div")
      actions.className = "sd-room-ai-instructions__template-actions"
      const apply = document.createElement("button")
      apply.type = "button"
      apply.textContent = this.copyValue.template_apply
      apply.addEventListener("click", () => this.applyTemplate(entry.id))
      const remove = document.createElement("button")
      remove.type = "button"
      remove.textContent = this.copyValue.template_delete
      remove.className = "sd-room-ai-instructions__template-remove"
      remove.addEventListener("click", () => this.deleteTemplate(entry.id))
      actions.append(apply, remove)
      panel.append(summary, preview, actions)
      fragment.append(panel)
    })
    this.templateListTarget.replaceChildren(fragment)
  }

  changed() {
    this.serverConflict = null
    this.setConflictOpen(false)
    this.showCount()
    this.refreshSave()
    this.statusTarget.textContent = this.dirty() ? this.copyValue.unsaved : ""
  }

  dirty() {
    const value = this.editorTarget.value.trim()
    // After saving, the empty editor is ready for a NEW full revision.
    // It must not immediately offer to write an accidental blank revision.
    return this.composingFresh ? value.length > 0 : value !== this.lastSaved
  }
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
        this.setConflictOpen(true)
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
      if (this.hasCurrentPreviewTarget && this.hasCurrentTextTarget) {
        this.currentPreviewTarget.hidden = false
        this.currentPreviewTarget.open = true
        this.currentTextTarget.textContent = this.lastSaved
        this.currentVersionTarget.textContent = this.copyValue.version
          .replace("%{count}", this.revisionValue)
      }
      // Do not erase characters the user typed while the request was in flight.
      // Clear only the successfully saved snapshot, not a later local draft.
      if (this.editorTarget.value === text && this.canEditValue) {
        this.editorTarget.value = ""
        this.composingFresh = true
      }
      this.statusTarget.textContent = this.dirty() ? this.copyValue.unsaved : this.copyValue.saved
      this.showCount()
      this.setHistoryOpen(false)
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.network_error
    } finally {
      this.pending = false
      this.refreshSave()
    }
  }

  setHistoryOpen(open) {
    this.historyOpen = Boolean(open)
    if (this.hasHistoryShellTarget) {
      this.historyShellTarget.dataset.open = String(this.historyOpen)
      this.historyShellTarget.setAttribute("aria-hidden", String(!this.historyOpen))
      this.historyShellTarget.inert = !this.historyOpen
    }
    if (this.hasHistoryToggleTarget) {
      this.historyToggleTarget.setAttribute("aria-expanded", String(this.historyOpen))
    }
    if (!this.historyOpen) this.historyRequestId += 1
  }

  setConflictOpen(open) {
    this.conflictTarget.dataset.open = String(Boolean(open))
    this.conflictTarget.setAttribute("aria-hidden", String(!open))
    this.conflictTarget.inert = !open
  }

  loadCurrent() {
    if (!this.canEditValue || this.pending || !this.hasCurrentTextTarget) return
    // This is an explicit COMPLETE replacement draft, not an append.
    this.editorTarget.value = this.lastSaved
    this.composingFresh = false
    this.changed()
    this.editorTarget.focus()
  }

  // Conflict reconciliation is always explicit: keep the user's edited text,
  // or restore the server text without silently overwriting it.
  rebaseDraft() {
    if (!this.serverConflict) return
    this.revisionValue = Number(this.serverConflict.current_revision || 0)
    this.lastSaved = this.serverConflict.current?.content || ""
    this.composingFresh = false
    this.revisionTarget.textContent = this.copyValue.version
      .replace("%{count}", this.revisionValue)
    this.setConflictOpen(false)
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
    if (this.historyOpen) {
      this.setHistoryOpen(false)
      return
    }
    if (this.historyLoading) return
    const requestId = ++this.historyRequestId
    this.historyLoading = true
    this.historyToggleTarget.disabled = true
    this.statusTarget.textContent = this.copyValue.loading
    try {
      const response = await fetch(this.historyUrlValue, {
        credentials: "same-origin", headers: { Accept: "application/json" }
      })
      if (!response.ok) throw new Error("Failed to fetch")
      const result = await response.json()
      if (!this.element.isConnected || requestId !== this.historyRequestId) return
      // Populate OFFSCREEN while collapsed, then animate the complete
      // measured height rather than replacing a tiny loading label in a
      // visible panel and causing a sudden vertical jump.
      this.renderHistory(result.history || [])
      this.setHistoryOpen(true)
      this.statusTarget.textContent = ""
    } catch (_) {
      if (this.element.isConnected && requestId === this.historyRequestId) {
        this.historyTarget.textContent = this.copyValue.network_error
        this.setHistoryOpen(true)
        this.statusTarget.textContent = this.copyValue.network_error
      }
    } finally {
      this.historyLoading = false
      if (this.hasHistoryToggleTarget) this.historyToggleTarget.disabled = false
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
          this.composingFresh = false
          this.changed()
          this.editorTarget.focus()
        })
        section.append(button)
      }
      this.historyTarget.append(section)
    }
  }
}
