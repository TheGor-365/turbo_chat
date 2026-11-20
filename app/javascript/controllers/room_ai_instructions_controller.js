import { Controller } from "@hotwired/stimulus"

// Human-saved room text only. Nothing here authorizes provider access,
// attaches chat history, runs xAI, or submits the surrounding message form.
export default class extends Controller {
  static targets = [
    "editor", "counter", "revision", "save", "status", "history",
    "historyToggle", "historyShell", "conflict", "conflictSummary",
    "currentPreview", "currentText", "currentVersion",
    "templateName", "templateTitle", "templateEdit", "templateConfirm"
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
    this.resizeEditor()
  }


  disconnect() {
    if (this.resizeFrame) window.cancelAnimationFrame(this.resizeFrame)
  }

  get templateStorageKey() {
    // User-owned library is shared across this user's rooms on THIS browser.
    return "turbo-chat:room-instruction-templates:v2:user:" + this.userIdValue
  }

  get legacyRoomTemplateKey() {
    return "turbo-chat:room-instruction-templates:v1:user:" +
      this.userIdValue + ":room:" + this.roomIdValue
  }

  defaultName(number) {
    return this.copyValue.template_default.replace("%{count}", String(number))
  }

  validTemplateContent(content) {
    if (typeof content !== "string" || !content.trim() || content.length > 4000 ||
        new TextEncoder().encode(content).length > 16000) return false
    if (/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u202A-\u202E\u2066-\u2069]/.test(content)) return false
    return !/\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,}|xai-[A-Za-z0-9_-]{20,})\b/.test(content)
  }

  validTemplateName(name) {
    return typeof name === "string" && name.trim().length > 0 && name.trim().length <= 60 &&
      !/[\x00-\x1F\x7F\u202A-\u202E\u2066-\u2069]/.test(name)
  }

  loadTemplates() {
    this.templates = []
    this.draftName = this.defaultName(this.revisionValue + 1)
    if (!this.canEditValue) return
    try {
      const stored = JSON.parse(window.localStorage.getItem(this.templateStorageKey) || "[]")
      if (Array.isArray(stored)) {
        this.templates = stored.filter(t => Number.isSafeInteger(t?.id) && t.id > 0 &&
          this.validTemplateName(t.name) && this.validTemplateContent(t.content))
          .slice(-100)
      }
      // Read old per-room drafts without destroying the old key, so the R2
      // user's work is preserved when upgrading to a single template library.
      const legacy = JSON.parse(window.localStorage.getItem(this.legacyRoomTemplateKey) || "[]")
      if (Array.isArray(legacy)) {
        let imported = false
        for (const item of legacy.slice(0, 12)) {
          if (!this.validTemplateName(item?.name) || !this.validTemplateContent(item?.content)) continue
          if (this.templates.some(t => t.source_room_id === this.roomIdValue &&
              t.source_revision == null && t.name === item.name && t.content === item.content)) continue
          if (this.templates.length >= 100) break
          this.templates.push({
            id: this.nextTemplateId(), name: item.name.trim(), content: item.content.trim(),
            source_room_id: this.roomIdValue, source_revision: null
          })
          imported = true
        }
        if (imported) this.persistTemplates()
      }
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.template_storage_error
    }
    this.renderDraftName()
  }

  nextTemplateId() {
    return Math.max(0, ...this.templates.map(t => t.id)) + 1
  }

  persistTemplates() {
    try {
      window.localStorage.setItem(this.templateStorageKey, JSON.stringify(this.templates))
      return true
    } catch (_) {
      this.statusTarget.textContent = this.copyValue.template_storage_error
      return false
    }
  }

  renderDraftName() {
    if (!this.hasTemplateTitleTarget) return
    this.templateTitleTarget.textContent = this.draftName ||
      this.defaultName(this.revisionValue + 1)
    this.templateTitleTarget.hidden = false
    if (this.hasTemplateNameTarget) this.templateNameTarget.hidden = true
    if (this.hasTemplateEditTarget) this.templateEditTarget.hidden = false
    if (this.hasTemplateConfirmTarget) this.templateConfirmTarget.hidden = true
  }

  editName() {
    if (!this.canEditValue || !this.hasTemplateNameTarget) return
    this.templateNameTarget.value = this.draftName
    this.templateTitleTarget.hidden = true
    this.templateNameTarget.hidden = false
    this.templateEditTarget.hidden = true
    this.templateConfirmTarget.hidden = false
    this.templateNameTarget.focus()
    this.templateNameTarget.select()
  }

  confirmName() {
    if (!this.canEditValue || !this.hasTemplateNameTarget) return
    const name = this.templateNameTarget.value.trim() ||
      this.defaultName(this.revisionValue + 1)
    if (!this.validTemplateName(name)) {
      this.statusTarget.textContent = this.copyValue.template_invalid_name
      return
    }
    // Name changes to unchanged saved text are local library edits only:
    // no new room revision, provider call or Send.
    if (!this.composingFresh && this.revisionValue > 0 &&
        this.editorTarget.value.trim() === this.lastSaved.trim() &&
        this.validTemplateContent(this.lastSaved)) {
      if (!this.recordTemplate(this.lastSaved, this.roomIdValue,
          this.revisionValue, name)) return
      this.statusTarget.textContent = this.copyValue.template_renamed
      if (this.loadedHistory) this.renderHistory(this.loadedHistory)
    }
    this.draftName = name
    this.renderDraftName()
    this.editorTarget.focus()
  }

  nameKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.confirmName()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.renderDraftName()
      this.editorTarget.focus()
    }
  }

  findTemplate(roomId, revision) {
    return this.templates.find(t =>
      t.source_room_id === roomId && t.source_revision === revision)
  }

  recordTemplate(content, roomId, revision, name) {
    if (!this.canEditValue || !this.validTemplateContent(content)) return false
    const existing = this.findTemplate(roomId, revision)
    if (existing) {
      if (this.validTemplateName(name) && existing.name !== name) existing.name = name.trim()
    } else {
      if (this.templates.length >= 100) {
        this.statusTarget.textContent = this.copyValue.template_limit
        return false
      }
      const id = this.nextTemplateId()
      this.templates.push({
        id, name: this.validTemplateName(name) ? name.trim() : this.defaultName(revision || id),
        content: content.trim(), source_room_id: roomId, source_revision: revision
      })
    }
    return this.persistTemplates()
  }

  importCurrentRoomHistory(history) {
    if (!this.canEditValue || !Array.isArray(history)) return
    let imported = false
    for (const row of history) {
      const revision = Number(row?.revision_number)
      if (!Number.isSafeInteger(revision) || revision < 1 ||
          !this.validTemplateContent(row.content) ||
          this.findTemplate(this.roomIdValue, revision) || this.templates.length >= 100) continue
      this.templates.push({
        id: this.nextTemplateId(), name: this.defaultName(revision),
        content: row.content, source_room_id: this.roomIdValue, source_revision: revision
      })
      imported = true
    }
    if (imported) this.persistTemplates()
  }

  applyTemplate(template) {
    if (!this.canEditValue || this.pending || !template) return false
    if (this.dirty() && this.editorTarget.value !== template.content &&
        !window.confirm(this.copyValue.template_confirm_discard)) return false
    this.editorTarget.value = template.content
    this.composingFresh = false
    this.draftName = template.name
    this.renderDraftName()
    this.changed()
    this.editorTarget.focus()
    return true
  }

  // An explicit 'Apply to room' click saves a NEW version immediately.
  // Existing 'Load into draft' remains non-destructive.
  activateTemplate(template) {
    if (!this.applyTemplate(template)) return
    if (this.dirty()) void this.save()
  }

  renameStoredTemplate(id, input, controls) {
    const row = this.templates.find(t => t.id === id)
    if (!row || !this.canEditValue) return
    const name = input.value.trim()
    if (!this.validTemplateName(name)) {
      this.statusTarget.textContent = this.copyValue.template_invalid_name
      return
    }
    row.name = name
    if (this.persistTemplates()) {
      this.renderHistory(this.loadedHistory || [])
      this.statusTarget.textContent = this.copyValue.template_renamed
    }
  }

  changed() {
    this.resizeEditor()
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
  // Grow after typing/paste, bounded to the existing room editor max.
  resizeEditor() {
    if (!this.canEditValue || this.editorTarget.hidden) return
    const editor = this.editorTarget
    const before = Math.max(125, editor.getBoundingClientRect().height || 125)
    editor.style.height = "auto"
    const needed = Math.min(320, Math.max(125, editor.scrollHeight))
    const next = editor.value ? Math.max(before, needed) : 125
    editor.style.height = before + "px"
    if (this.resizeFrame) window.cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = window.requestAnimationFrame(() => {
      if (this.element.isConnected) editor.style.height = next + "px"
    })
  }
  refreshSave() {
    if (this.hasSaveTarget) this.saveTarget.disabled =
      !this.canEditValue || this.pending || !this.dirty()
  }

  async save() {
    if (!this.canEditValue || !this.dirty() || this.pending) return
    const text = this.editorTarget.value
    const draftNameAtSave = this.draftName
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
      const librarySaved = !result.changed || this.recordTemplate(
        this.lastSaved, this.roomIdValue, this.revisionValue, draftNameAtSave
      )
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
        this.draftName = this.defaultName(this.revisionValue + 1)
        this.renderDraftName()
      }
      this.statusTarget.textContent = this.dirty() ? this.copyValue.unsaved :
        (librarySaved ? this.copyValue.saved : this.copyValue.template_storage_error)
      this.showCount()
      this.resizeEditor()
      this.setHistoryOpen(false)
      this.dispatch("saved", {detail: {revision: this.revisionValue}})
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
    this.draftName = this.findTemplate(this.roomIdValue, this.revisionValue)?.name ||
      this.defaultName(this.revisionValue)
    this.renderDraftName()
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
      this.loadedHistory = result.history || []
      this.importCurrentRoomHistory(this.loadedHistory)
      this.renderHistory(this.loadedHistory)
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
    const openKeys = new Set(Array.from(
      this.historyTarget.querySelectorAll(".sd-room-ai-instructions__history-entry[open]")
    ).map(el => el.dataset.templateKey))
    this.historyTarget.replaceChildren()
    // Editors see one list: all personal reusable copies plus current room
    // revisions, including those imported from the immutable server audit.
    // Read-only members see only the history of their accessible room.
    const rows = this.canEditValue ? [...this.templates].reverse() :
      (Array.isArray(history) ? history : []).map(revision => ({
        name: this.defaultName(revision.revision_number),
        content: revision.content, source_room_id: this.roomIdValue,
        source_revision: revision.revision_number, readOnly: true
      }))
    if (!rows.length) {
      this.historyTarget.textContent = this.copyValue.no_history
      return
    }
    for (const template of rows) {
      const section = document.createElement("details")
      section.className = "sd-room-ai-instructions__history-entry"
      const key = String(template.id || template.source_revision)
      section.dataset.templateKey = key
      section.open = openKeys.has(key)
      const summary = document.createElement("summary")
      const name = document.createElement("strong")
      name.className = "sd-room-ai-instructions__history-name"
      name.textContent = template.name
      const source = document.createElement("small")
      const sameRoom = template.source_room_id === this.roomIdValue
      source.textContent = sameRoom && template.source_revision ?
        this.copyValue.version.replace("%{count}", template.source_revision) :
        (sameRoom ? this.copyValue.template_local_draft : this.copyValue.template_other_room)
      summary.append(name, source)
      const content = document.createElement("pre")
      content.textContent = template.content || this.copyValue.empty_version
      section.append(summary, content)
      if (this.canEditValue) {
        const controls = document.createElement("div")
        controls.className = "sd-room-ai-instructions__history-tools"
        const apply = document.createElement("button")
        apply.type = "button"
        apply.className = "sd-room-ai-instructions__history-button"
        apply.textContent = this.copyValue.copy_version
        apply.addEventListener("click", () => this.applyTemplate(template))
        const nameInput = document.createElement("input")
        nameInput.type = "text"
        nameInput.maxLength = 60
        nameInput.value = template.name
        nameInput.hidden = true
        nameInput.setAttribute("aria-label", this.copyValue.template_name)
        const pencil = document.createElement("button")
        pencil.type = "button"
        pencil.className = "sd-room-ai-instructions__history-button sd-room-ai-instructions__rename-button"
        pencil.textContent = this.copyValue.rename_template
        pencil.addEventListener("click", () => {
          nameInput.hidden = false
          pencil.hidden = true
          check.hidden = false
          nameInput.focus()
          nameInput.select()
        })
        const check = document.createElement("button")
        check.type = "button"
        check.hidden = true
        check.className = "sd-room-ai-instructions__history-button"
        check.textContent = this.copyValue.confirm_template_name
        check.addEventListener("click", () => this.renameStoredTemplate(template.id, nameInput))
        nameInput.addEventListener("keydown", event => {
          if (event.key === "Enter") {
            event.preventDefault()
            this.renameStoredTemplate(template.id, nameInput)
          } else if (event.key === "Escape") {
            nameInput.hidden = true
            pencil.hidden = false
            check.hidden = true
          }
        })
        const activate = document.createElement("button")
        activate.type = "button"
        activate.className = "sd-room-ai-instructions__history-button sd-room-ai-instructions__apply-now"
        activate.textContent = this.copyValue.apply_template_now
        activate.addEventListener("click", () => this.activateTemplate(template))
        controls.append(apply, activate, pencil, nameInput, check)
        section.append(controls)
      }
      this.historyTarget.append(section)
    }
  }

}
