import { Controller } from "@hotwired/stimulus"

// S8/D5 first vertical slice: one browser-side Context Studio for the room.
// Every source is fetched through the consent/DLP inventory, never from the
// ordinary chat DOM. Generated model context is independently validated by
// ai-answer-entry/GenerationOrchestrator; no provider or Send action lives here.
export default class extends Controller {
  static targets = [
    "dialog", "list", "status", "metrics", "scope", "scopeHelp", "saved",
    "name", "search", "author", "from", "to", "more", "apply", "inherit",
    "preset", "notice", "effective", "replyTarget", "board",
    "savedToggle", "savedPanel", "savedCount", "participantLegend"
  ]
  static values = { url: String, roomId: Number, userId: Number,
    roomName: String, copy: Object }

  connect() {
    this.activeScope = "shared"
    this.shared = this.defaultConfig()
    this.overrides = {}
    this.namedSets = []
    this.appliedAnswer = JSON.stringify(this.shared)
    this.appliedAnswerScope = "shared"
    this.page = 0
    this.snapshot = null
    this.items = []
    this.loading = false
    this.serial = 0
    this.filterTimer = null
    this.loadLocal()
  }

  disconnect() {
    clearTimeout(this.filterTimer)
    ++this.serial
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  defaultConfig() {
    return {kind: "all", excluded: [], included: [], authorId: null}
  }

  get key() {
    return "turbo-chat:context-studio:v1:user:" + this.userIdValue +
      ":room:" + this.roomIdValue
  }

  validConfig(value) {
    if (!value || !["all", "last", "author", "single", "custom"].includes(value.kind)) return false
    for (const key of ["excluded", "included"]) {
      if (!Array.isArray(value[key]) || value[key].length > 10000 ||
          !value[key].every(id => Number.isSafeInteger(id) && id > 0)) return false
    }
    return value.authorId == null ||
      (Number.isSafeInteger(value.authorId) && value.authorId > 0)
  }

  loadLocal() {
    // Device drafts and named snapshots are NEVER active provider grants.
    // The initial Answer contract remains server default until explicit Apply.
    try {
      const local = JSON.parse(localStorage.getItem(this.key) || "{}")
      if (this.validConfig(local.drafts?.shared)) this.shared = local.drafts.shared
      if (local.drafts?.overrides && typeof local.drafts.overrides === "object") {
        for (const mode of ["answer", "beautify", "auto_reply", "finalize"]) {
          if (this.validConfig(local.drafts.overrides[mode])) {
            this.overrides[mode] = local.drafts.overrides[mode]
          }
        }
      }
      if (Array.isArray(local.namedSets)) {
        this.namedSets = local.namedSets.filter(row =>
          row && typeof row.name === "string" && row.name.length <= 80 &&
          this.validConfig(row.config)).slice(-30)
      }
      // Explicitly NO re-activation of a saved selection from localStorage.
    } catch (_) { /* Private browsing may not have usable storage. */ }
  }

  persistLocal() {
    try {
      localStorage.setItem(this.key, JSON.stringify({
        drafts: {shared: this.shared, overrides: this.overrides},
        namedSets: this.namedSets
      }))
      return true
    } catch (_) { return false }
  }

  current() {
    return this.activeScope === "shared" ? this.shared :
      (this.overrides[this.activeScope] || this.shared)
  }

  isInherited() {
    return this.activeScope !== "shared" && !this.overrides[this.activeScope]
  }

  editConfig() {
    if (this.activeScope === "shared") return this.shared
    if (!this.overrides[this.activeScope]) {
      this.overrides[this.activeScope] = JSON.parse(JSON.stringify(this.shared))
    }
    return this.overrides[this.activeScope]
  }

  async open(event) {
    event?.preventDefault()
    if (!this.hasDialogTarget || this.dialogTarget.open) return
    this.returnFocus = document.activeElement
    const answer = this.answer()
    if (answer?.planOpen) {
      answer.hidePlan()
      // Wait for the actual close animation, instead of hiding it on pointerdown:
      // that reflow swallowed the click which should have opened this dialog.
      try { await answer.planMotion?.finished } catch (_) { /* reversed motion */ }
    }
    if (!this.element.isConnected || this.dialogTarget.open) return
    this.dialogTarget.showModal()
    this.render()
    await this.loadPage(1)
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  closed() {
    ++this.serial
    clearTimeout(this.filterTimer)
    this.returnFocus?.focus?.({preventScroll: true})
  }

  setScope(event) {
    this.activeScope = event.currentTarget.dataset.scope
    this.noticeTarget.textContent = ""
    this.render()
  }

  inherit() {
    if (this.activeScope === "shared") return
    delete this.overrides[this.activeScope]
    this.persistLocal()
    this.render()
    this.noticeTarget.textContent = this.copyValue.inherited
  }

  preset(event) {
    const name = event.currentTarget.dataset.preset
    const cfg = this.editConfig()
    cfg.excluded = []
    cfg.included = []
    cfg.authorId = null
    if (name === "last") {
      const incoming = this.snapshot?.latest_incoming_id ?
        {id: this.snapshot.latest_incoming_id} : this.items.find(row => row.incoming)
      if (!incoming) {
        this.noticeTarget.textContent = this.copyValue.noIncoming
        return
      }
      cfg.kind = "last"
      cfg.included = [incoming.id]
    } else if (name === "author") {
      const chosen = Number(this.authorTarget.value)
      if (!chosen) {
        this.noticeTarget.textContent = this.copyValue.chooseAuthor
        this.authorTarget.focus()
        return
      }
      cfg.kind = "author"
      cfg.authorId = chosen
    } else if (name === "all") {
      cfg.kind = "all"
    } else if (name === "custom") {
      // Starting manual mode retains the visible selection instead of
      // unexpectedly clearing every switch. Later pages remain opt-in.
      cfg.kind = "custom"
      cfg.included = this.items.map(row => row.id)
    }
    this.persistLocal()
    this.render()
  }

  sole(event) {
    const id = Number(event.currentTarget.dataset.id)
    const cfg = this.editConfig()
    cfg.kind = "single"
    cfg.included = [id]
    cfg.excluded = []
    this.persistLocal()
    this.render()
  }

  toggle(event) {
    const id = Number(event.currentTarget.dataset.id)
    const enabled = event.currentTarget.getAttribute("aria-checked") === "true"
    const cfg = this.editConfig()
    if (cfg.kind !== "all" && cfg.kind !== "custom") {
      cfg.included = this.items.filter(item => this.selected(item, cfg))
        .map(item => item.id)
      cfg.kind = "custom"
      cfg.excluded = []
    }
    if (cfg.kind === "all") {
      cfg.excluded = enabled ? [...new Set([...cfg.excluded, id])] :
        cfg.excluded.filter(value => value !== id)
    } else {
      cfg.included = enabled ? cfg.included.filter(value => value !== id) :
        [...new Set([...cfg.included, id])]
    }
    this.persistLocal()
    this.render()
  }

  selected(row, cfg = this.current()) {
    if (cfg.kind === "all") return !cfg.excluded.includes(row.id)
    if (cfg.kind === "author") return row.author_id === cfg.authorId
    if (cfg.kind === "last" || cfg.kind === "single") {
      return cfg.included.includes(row.id)
    }
    return cfg.included.includes(row.id)
  }

  filterChanged() {
    clearTimeout(this.filterTimer)
    this.filterTimer = setTimeout(() => void this.loadPage(1), 280)
  }

  async loadMore() {
    if (!this.loading && this.snapshot?.has_more) await this.loadPage(this.page + 1)
  }

  async loadPage(page) {
    if (!this.dialogTarget.open || this.loading && page > 1) return
    const serial = ++this.serial
    this.loading = true
    this.statusTarget.textContent = this.copyValue.loading
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      if (!csrf) throw new Error("csrf")
      const body = {page: String(page), q: this.searchTarget.value.trim(),
        author_id: this.authorTarget.value || null,
        from: this.fromTarget.value || null, to: this.toTarget.value || null}
      const res = await fetch(this.urlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf}, body: JSON.stringify(body)
      })
      const data = await res.json().catch(() => ({}))
      if (serial !== this.serial || !this.dialogTarget.open) return
      if (!res.ok || data.version !== 1 || !Array.isArray(data.messages) ||
          data.model_receives_full_history !== false) throw new Error("denied")
      if (page > 1 && this.snapshot &&
          (this.snapshot.snapshot_fingerprint !== data.snapshot_fingerprint ||
           this.snapshot.room_id !== data.room_id)) throw new Error("changed")
      this.page = page
      this.snapshot = data
      if (page === 1) {
        this.items = []
        this.loadAuthors(data.participants)
      }
      this.items.push(...data.messages)
      this.render()
      this.statusTarget.textContent = this.copyValue.ready
    } catch (_) {
      if (serial !== this.serial || !this.dialogTarget.open) return
      // Never continue displaying a stale snapshot after consent or DLP failure.
      this.snapshot = null
      this.items = []
      this.render()
      this.statusTarget.textContent = this.copyValue.unavailable
    } finally {
      if (serial === this.serial) {
        this.loading = false
        this.applyTarget.disabled = !this.snapshot
      }
    }
  }

  loadAuthors(people) {
    if (!Array.isArray(people)) return
    const chosen = this.authorTarget.value
    this.authorTarget.replaceChildren(new Option(this.copyValue.allAuthors, ""))
    for (const person of people) {
      if (!Number.isSafeInteger(person.id)) continue
      this.authorTarget.add(new Option(person.name, String(person.id)))
    }
    this.authorTarget.value = chosen
    this.authorTarget.dispatchEvent(new Event("ui-select:sync"))
  }

  el(tag, cls = "", value = "") {
    const node = document.createElement(tag)
    if (cls) node.className = cls
    node.textContent = value
    return node
  }

  scopeLabel(mode) {
    return {
      shared: this.copyValue.allModes, answer: this.copyValue.modeAnswer,
      beautify: this.copyValue.modeBeautify,
      auto_reply: this.copyValue.modeAuto, finalize: this.copyValue.modeFinalize
    }[mode] || mode
  }

  scopeConfig(mode) {
    return mode === "shared" ? this.shared : (this.overrides[mode] || this.shared)
  }

  eligibleCount(cfg) {
    if (!this.snapshot) return 0
    if (cfg.kind === "all") {
      return Math.max(0, this.snapshot.eligible_total - cfg.excluded.length)
    }
    if (cfg.kind === "author") {
      return this.snapshot.participants.find(person =>
        person.id === cfg.authorId)?.eligible_count || 0
    }
    return cfg.included.length
  }

  sourceReference(row) {
    return row && Number.isSafeInteger(row.participant_no) &&
      Number.isSafeInteger(row.participant_message_no) ?
      "P" + row.participant_no + "." + row.participant_message_no :
      "M" + row?.id
  }

  participantLabel(id) {
    return this.snapshot?.participants?.find(person =>
      person.id === Number(id))?.name || this.copyValue.member
  }

  selectionText(cfg) {
    const number = this.eligibleCount(cfg)
    if (cfg.kind === "all" && !cfg.excluded.length) {
      return this.copyValue.defaultName + " · " + number
    }
    if (cfg.kind === "all") {
      return this.copyValue.exceptName.replace("{count}", String(cfg.excluded.length)) +
        " · " + number
    }
    if (cfg.kind === "author") {
      return this.participantLabel(cfg.authorId) + " · " + number
    }
    if (cfg.kind === "last") return this.copyValue.latestName
    return this.copyValue.messagesName.replace("{count}", String(number))
  }

  memberSummary(cfg) {
    if (cfg.kind === "author") return this.participantLabel(cfg.authorId)
    if (cfg.kind === "all" && !cfg.excluded.length) return this.copyValue.allAuthors
    const current = this.items.filter(row => this.selected(row, cfg))
    const names = [...new Set(current.map(row => this.participantLabel(row.author_id)))]
    return names.length ? names.join(", ") : this.copyValue.selectedUsersUnknown
  }

  answerApplied() {
    const actualMode = this.overrides.answer ? "answer" : "shared"
    return this.appliedAnswerScope === actualMode &&
      this.appliedAnswer === JSON.stringify(this.scopeConfig(actualMode))
  }

  statusFor(mode) {
    const override = mode !== "shared" && Boolean(this.overrides[mode])
    if (mode === "answer" || (mode === "shared" && !this.overrides.answer)) {
      if (this.answerApplied()) return this.copyValue.applied
      return this.copyValue.needsApply
    }
    if (mode === "shared") return this.copyValue.localDraft
    return override ? this.copyValue.ownDraft : this.copyValue.inheritsDraft
  }

  renderBoard() {
    if (!this.hasBoardTarget) return
    this.boardTarget.replaceChildren()
    const modes = ["shared", "answer", "beautify", "auto_reply", "finalize"]
    for (const mode of modes) {
      const cfg = this.scopeConfig(mode)
      const isOverride = mode !== "shared" && Boolean(this.overrides[mode])
      const row = this.el("div", "sd-ai-context-board__row")
      row.dataset.mode = mode
      row.dataset.active = String(mode === this.activeScope)
      row.dataset.override = String(isOverride)
      const icon = this.scopeTargets.find(button =>
        button.dataset.scope === mode)?.querySelector("svg")?.cloneNode(true)
      if (icon) row.append(icon)
      const name = this.el("div", "sd-ai-context-board__name")
      name.append(this.el("strong", "", this.scopeLabel(mode)))
      name.append(this.el("small", "", mode === "shared" ?
        this.copyValue.baseScope :
        (isOverride ? this.copyValue.own : this.copyValue.inheritedShort)))
      const description = this.el("div", "sd-ai-context-board__selection",
        this.selectionText(cfg))
      const state = this.el("span", "sd-ai-context-board__state", this.statusFor(mode))
      state.dataset.state = mode === "answer" ||
        (mode === "shared" && !this.overrides.answer) ?
          (this.answerApplied() ? "applied" : "draft") : "local"
      row.append(name, description, state)
      this.boardTarget.append(row)
    }
  }

  renderParticipantLegend() {
    this.participantLegendTarget.replaceChildren()
    for (const person of this.snapshot?.participants || []) {
      this.participantLegendTarget.append(
        this.el("span", "sd-ai-context-participant",
          "P" + person.participant_no + " · " + person.name +
          " · " + person.eligible_count))
    }
  }

  toggleSaved() {
    const section = this.savedToggleTarget.closest(".sd-ai-context-studio__saved")
    const opening = section.dataset.open !== "true"
    section.dataset.open = String(opening)
    this.savedToggleTarget.setAttribute("aria-expanded", String(opening))
  }

  automaticName(scope, cfg) {
    return (this.roomNameValue + " · " + this.scopeLabel(scope) + " · " +
      this.selectionText(cfg)).slice(0, 80)
  }

  captureSet({automatic = true, applied = false} = {}) {
    if (!this.snapshot) return false
    const scope = this.activeScope
    const cfg = JSON.parse(JSON.stringify(this.current()))
    const stamp = new Date().toISOString()
    const name = automatic ?
      this.automaticName(scope, cfg) :
      (this.nameTarget.value.trim() || this.automaticName(scope, cfg)).slice(0, 80)
    const existing = automatic ? this.namedSets.find(row =>
      row.scope === scope && row.automatic &&
      JSON.stringify(row.config) === JSON.stringify(cfg)) : null
    if (existing) {
      Object.assign(existing, {name, date: stamp,
        snapshot_fingerprint: this.snapshot.snapshot_fingerprint,
        applied, count: this.eligibleCount(cfg), people: this.memberSummary(cfg)})
    } else {
      if (this.namedSets.length >= 30) {
        const oldestAuto = this.namedSets.findIndex(row => row.automatic)
        if (oldestAuto < 0) return false
        this.namedSets.splice(oldestAuto, 1)
      }
      this.namedSets.push({scope, name, config: cfg,
        date: stamp, automatic, applied,
        snapshot_fingerprint: this.snapshot.snapshot_fingerprint,
        count: this.eligibleCount(cfg), people: this.memberSummary(cfg)})
    }
    const persisted = this.persistLocal()
    this.renderSaved()
    return persisted
  }

  render() {
    if (!this.hasDialogTarget) return
    const cfg = this.current()
    for (const button of this.scopeTargets) {
      const mode = button.dataset.scope
      const override = mode !== "shared" && Boolean(this.overrides[mode])
      button.setAttribute("aria-pressed", String(this.activeScope === mode))
      button.dataset.custom = String(override)
      const label = button.querySelector("[data-scope-state]")
      if (label) label.textContent = mode === "shared" ?
        this.copyValue.baseScope : (override ?
          this.copyValue.own : this.copyValue.inheritedShort)
      const note = button.querySelector("[data-scope-note]")
      if (note) note.textContent = mode === "shared" ?
        this.copyValue.scopeSharedNote : mode === "answer" ?
          this.copyValue.scopeAnswerNote : mode === "beautify" ?
          this.copyValue.scopeBeautifyNote : mode === "auto_reply" ?
          this.copyValue.scopeAutoNote : this.copyValue.scopeFinalizerNote
    }
    for (const button of this.presetTargets) {
      const name = button.dataset.preset
      const selected = cfg.kind === name ||
        (name === "custom" && cfg.kind === "all" && cfg.excluded.length > 0) ||
        (name === "custom" && cfg.kind === "single")
      button.setAttribute("aria-pressed", String(selected))
    }
    this.inheritTarget.hidden = this.activeScope === "shared" || this.isInherited()
    this.scopeHelpTarget.textContent = this.activeScope === "shared" ?
      this.copyValue.sharedScope : (this.isInherited() ?
        this.copyValue.inheritedScope : this.copyValue.personalScope)
    this.effectiveTarget.textContent = this.scopeLabel(this.activeScope) + " · " +
      this.selectionText(cfg) + " · " + this.memberSummary(cfg) +
      " · " + this.statusFor(this.activeScope)
    this.renderBoard()
    this.listTarget.replaceChildren()
    const people = new Map((this.snapshot?.participants || []).map(row =>
      [row.id, row]))
    const lastIncoming = this.items.find(row => row.incoming && this.selected(row, cfg))
    this.replyTargetTarget.textContent = lastIncoming ?
      this.copyValue.targetPreview.replace("{id}", this.sourceReference(lastIncoming)) :
      this.copyValue.targetUnknown
    for (const row of this.items) {
      const on = this.selected(row, cfg)
      const card = this.el("article", "sd-ai-context-message" +
        (row.incoming ? "" : " sd-ai-context-message--own") +
        (on ? "" : " sd-ai-context-message--excluded"))
      const head = this.el("div", "sd-ai-context-message__head")
      const person = people.get(row.author_id)
      const initial = person?.name?.slice(0, 1)?.toUpperCase() || "?"
      let avatar = this.el("span", "sd-ai-context-message__avatar", initial)
      if (typeof person?.avatar_url === "string" && person.avatar_url.startsWith("/")) {
        avatar = this.el("img", "sd-ai-context-message__avatar")
        avatar.src = person.avatar_url
        avatar.alt = ""
        avatar.loading = "lazy"
      }
      head.append(avatar)
      head.append(this.el("strong", "", person?.name || this.copyValue.member))
      head.append(this.el("span", "sd-ai-context-message__ref", this.sourceReference(row)))
      head.append(this.el("time", "",
        new Date(row.created_at).toLocaleString(document.documentElement.lang || undefined,
          {dateStyle: "short", timeStyle: "short"})))
      const toggle = this.el("button", "sd-ai-context-message__switch",
        on ? this.copyValue.on : this.copyValue.off)
      toggle.type = "button"
      toggle.dataset.id = row.id
      toggle.setAttribute("role", "switch")
      toggle.setAttribute("aria-checked", String(on))
      toggle.setAttribute("aria-label",
        this.copyValue.toggle.replace("{id}", String(row.id)))
      toggle.addEventListener("click", event => this.toggle(event))
      const solo = this.el("button", "sd-ai-context-message__solo", this.copyValue.solo)
      solo.type = "button"
      solo.dataset.id = row.id
      solo.setAttribute("aria-label",
        this.copyValue.onlyThis.replace("{id}", String(row.id)))
      solo.addEventListener("click", event => this.sole(event))
      head.append(solo, toggle)
      card.append(head, this.el("p", "sd-ai-context-message__text", row.text))
      this.listTarget.append(card)
    }
    if (!this.items.length) {
      this.listTarget.append(this.el("p", "sd-ai-context-empty",
        this.snapshot ? this.copyValue.empty : this.copyValue.loading))
    }
    const values = {
      eligible: this.snapshot?.eligible_total ?? "—",
      found: this.snapshot?.filtered_total ?? "—",
      shown: this.items.length,
      selected: this.snapshot ? this.eligibleCount(cfg) : "—"
    }
    for (const [name, value] of Object.entries(values)) {
      const target = this.metricsTarget.querySelector('[data-metric="' + name + '"]')
      if (target) target.textContent = String(value)
    }
    this.renderParticipantLegend()
    this.moreTarget.hidden = !this.snapshot?.has_more
    this.applyTarget.disabled = !this.snapshot || this.loading
    this.renderSaved()
  }

  defaultName() {
    return this.roomNameValue + " · " +
      new Date().toLocaleString(document.documentElement.lang || undefined,
        {dateStyle: "short", timeStyle: "short"})
  }

  saveSet() {
    if (!this.captureSet({automatic: false, applied: false})) {
      this.noticeTarget.textContent = this.copyValue.storageFailed
      return
    }
    this.nameTarget.value = ""
    this.noticeTarget.textContent = this.copyValue.localSaved
  }

  openSaved() {
    const section = this.savedToggleTarget.closest(".sd-ai-context-studio__saved")
    section.dataset.open = "true"
    this.savedToggleTarget.setAttribute("aria-expanded", "true")
  }

  loadSet(row) {
    const next = JSON.parse(JSON.stringify(row.config))
    const mode = ["shared","answer","beautify","auto_reply","finalize"]
      .includes(row.scope) ? row.scope : "shared"
    this.activeScope = mode
    if (mode === "shared") this.shared = next
    else this.overrides[mode] = next
    this.persistLocal()
    this.render()
    this.noticeTarget.textContent = this.copyValue.loaded
  }

  deleteSet(row) {
    this.namedSets = this.namedSets.filter(entry => entry !== row)
    this.persistLocal()
    this.renderSaved()
  }

  renderSaved() {
    this.savedTarget.replaceChildren()
    this.savedCountTarget.textContent = String(this.namedSets.length)
    for (const row of [...this.namedSets].reverse()) {
      const mode = ["shared","answer","beautify","auto_reply","finalize"]
        .includes(row.scope) ? row.scope : "shared"
      const item = this.el("article", "sd-ai-context-saved__entry")
      item.dataset.open = "false"
      const header = this.el("button", "sd-ai-context-saved__header")
      header.type = "button"
      header.setAttribute("aria-expanded", "false")
      const icon = this.scopeTargets.find(button =>
        button.dataset.scope === mode)?.querySelector("svg")?.cloneNode(true)
      if (icon) header.append(icon)
      const title = this.el("span", "sd-ai-context-saved__title", row.name)
      const count = Number.isSafeInteger(row.count) ?
        row.count : this.eligibleCount(row.config)
      const indicator = this.el("small", "sd-ai-context-saved__count",
        String(count) + " · " + this.scopeLabel(mode))
      header.append(title, indicator)
      header.addEventListener("click", () => {
        const opened = item.dataset.open !== "true"
        item.dataset.open = String(opened)
        header.setAttribute("aria-expanded", String(opened))
      })
      const reveal = this.el("div", "sd-ai-context-studio__reveal")
      const inner = this.el("div", "sd-ai-context-studio__reveal-inner")
      const sameInventory = Boolean(this.snapshot &&
        row.snapshot_fingerprint === this.snapshot.snapshot_fingerprint)
      const label = row.automatic ? this.copyValue.autoSnapshot :
        this.copyValue.manualSnapshot
      inner.append(this.el("p", "sd-ai-context-saved__meta",
        label + " · " + (row.people || this.memberSummary(row.config)) +
        " · " + (row.date ? new Date(row.date).toLocaleString(
          document.documentElement.lang || undefined,
          {dateStyle: "short", timeStyle: "short"}) : "—")))
      inner.append(this.el("p", "sd-ai-context-saved__meta",
        this.copyValue.savedSelection + ": " + this.selectionText(row.config)))
      inner.append(this.el("p", "sd-ai-context-saved__meta",
        sameInventory ? this.copyValue.savedRevalidate :
          this.copyValue.savedStale))
      const actions = this.el("div", "sd-ai-context-saved__actions")
      const load = this.el("button", "", this.copyValue.loadSaved)
      load.type = "button"
      load.addEventListener("click", () => this.loadSet(row))
      const remove = this.el("button", "sd-ai-context-saved__delete",
        this.copyValue.deleteSaved)
      remove.type = "button"
      remove.addEventListener("click", () => this.deleteSet(row))
      actions.append(load, remove)
      inner.append(actions)
      reveal.append(inner)
      item.append(header, reveal)
      this.savedTarget.append(item)
    }
    if (!this.namedSets.length) {
      this.savedTarget.append(this.el("p", "sd-ai-context-empty",
        this.copyValue.noSets))
    }
  }

  answer() {
    return this.application.getControllerForElementAndIdentifier(
      this.element, "ai-answer-entry")
  }

  async apply() {
    const cfg = this.current()
    const target = this.activeScope === "shared" ?
      (!this.overrides.answer ? "answer" : "none") : this.activeScope
    // Modes not yet wired to the common input contract are explicitly local
    // configuration drafts, never misrepresented as live provider behavior.
    if (target !== "answer") {
      const stored = this.captureSet({automatic: true, applied: false})
      this.openSaved()
      this.noticeTarget.textContent = stored ?
        this.copyValue.savedButNotWired : this.copyValue.storageFailed
      this.render()
      return
    }
    const answer = this.answer()
    if (!answer || !answer.goal?.configured || !answer.access?.ready) {
      this.noticeTarget.textContent = this.copyValue.unavailable
      return
    }
    this.applyTarget.disabled = true
    this.noticeTarget.textContent = this.copyValue.applying
    try {
      if (cfg.kind === "all" && cfg.excluded.length === 0) {
        if (!await answer.clearContextSelection()) throw new Error("stale")
      } else {
        if (cfg.kind === "author") throw new Error("notBounded")
        if (!answer.planFullSources || !answer.planSourceToken) {
          if (!await answer.reloadPlan(null, {allowClosed: true})) throw new Error("stale")
        }
        const sources = answer.planFullSources || []
        const rows = sources.filter(row => {
          const id = Number(row.ref.slice(1))
          if (cfg.kind === "all") return !cfg.excluded.includes(id)
          if (cfg.kind === "last" || cfg.kind === "single" ||
              cfg.kind === "custom") return cfg.included.includes(id)
          return false
        })
        if ((cfg.kind === "last" || cfg.kind === "single" || cfg.kind === "custom") &&
            cfg.included.some(id => !sources.some(row => Number(row.ref.slice(1)) === id))) {
          throw new Error("notBounded")
        }
        const incoming = rows.filter(row => row.speaker !== "you")
        if (!incoming.length) throw new Error("noIncoming")
        const ids = rows.map(row => Number(row.ref.slice(1)))
        const targetId = Number(incoming[incoming.length - 1].ref.slice(1))
        if (!await answer.applyContextSelection({
          sourceToken: answer.planSourceToken, ids, targetId,
          goalRevision: answer.goal.current_revision
        })) throw new Error("stale")
      }
      this.appliedAnswer = JSON.stringify(cfg)
      this.appliedAnswerScope = this.activeScope
      const stored = this.captureSet({automatic: true, applied: true})
      this.openSaved()
      this.render()
      this.noticeTarget.textContent = this.copyValue.appliedBounded +
        (stored ? "" : " " + this.copyValue.storageFailed)
    } catch (error) {
      this.noticeTarget.textContent = error.message === "notBounded" ?
        this.copyValue.boundedLimit : error.message === "noIncoming" ?
          this.copyValue.noIncoming : this.copyValue.unavailable
    } finally {
      this.applyTarget.disabled = false
    }
  }
}
