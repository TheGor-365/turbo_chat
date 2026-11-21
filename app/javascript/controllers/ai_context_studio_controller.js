import { Controller } from "@hotwired/stimulus"

// S8/D5 first vertical slice: one browser-side Context Studio for the room.
// Every source is fetched through the consent/DLP inventory, never from the
// ordinary chat DOM. Generated model context is independently validated by
// ai-answer-entry/GenerationOrchestrator; no provider or Send action lives here.
export default class extends Controller {
  static targets = [
    "dialog", "list", "status", "metrics", "scope", "scopeHelp", "saved",
    "name", "search", "author", "from", "to", "more", "apply", "inherit",
    "preset", "notice"
  ]
  static values = { url: String, roomId: Number, userId: Number,
    roomName: String, copy: Object }

  connect() {
    this.scope = "shared"
    this.shared = this.defaultConfig()
    this.overrides = {}
    this.namedSets = []
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
    // Browser storage is NOT an authorization/active provider selection.
    // Rehydrate named draft sets only. Live effective Answer context always
    // begins from the validated server default after a fresh page load.
    try {
      const local = JSON.parse(localStorage.getItem(this.key) || "{}")
      if (Array.isArray(local.namedSets)) {
        this.namedSets = local.namedSets.filter(row =>
          row && typeof row.name === "string" && row.name.length <= 80 &&
          this.validConfig(row.config)).slice(-30)
      }
    } catch (_) { /* Private browsing can block localStorage. */ }
  }

  persistLocal() {
    try {
      localStorage.setItem(this.key, JSON.stringify({namedSets: this.namedSets}))
      return true
    } catch (_) { return false }
  }

  current() {
    return this.scope === "shared" ? this.shared :
      (this.overrides[this.scope] || this.shared)
  }

  isInherited() {
    return this.scope !== "shared" && !this.overrides[this.scope]
  }

  editConfig() {
    if (this.scope === "shared") return this.shared
    if (!this.overrides[this.scope]) {
      this.overrides[this.scope] = JSON.parse(JSON.stringify(this.shared))
    }
    return this.overrides[this.scope]
  }

  async open() {
    if (!this.hasDialogTarget || this.dialogTarget.open) return
    this.returnFocus = document.activeElement
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
    this.scope = event.currentTarget.dataset.scope
    this.noticeTarget.textContent = ""
    this.render()
  }

  inherit() {
    if (this.scope === "shared") return
    delete this.overrides[this.scope]
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
      const incoming = this.items.find(row => row.incoming) ||
        (this.snapshot?.latest_incoming_id ? {id: this.snapshot.latest_incoming_id} : null)
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
      cfg.kind = "custom"
    }
    this.render()
  }

  sole(event) {
    const id = Number(event.currentTarget.dataset.id)
    const cfg = this.editConfig()
    cfg.kind = "single"
    cfg.included = [id]
    cfg.excluded = []
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

  render() {
    if (!this.hasDialogTarget) return
    const cfg = this.current()
    for (const button of this.scopeTargets) {
      const mode = button.dataset.scope
      button.setAttribute("aria-pressed", String(this.scope === mode))
      const label = button.querySelector("[data-scope-state]")
      if (label) label.textContent = mode === "shared" ?
        this.copyValue.allModes :
        (this.overrides[mode] ? this.copyValue.own : this.copyValue.inheritedShort)
    }
    for (const button of this.presetTargets) {
      button.setAttribute("aria-pressed", String(cfg.kind === button.dataset.preset))
    }
    this.inheritTarget.hidden = this.scope === "shared" || this.isInherited()
    this.scopeHelpTarget.textContent = this.scope === "shared" ?
      this.copyValue.sharedScope : (this.isInherited() ?
        this.copyValue.inheritedScope : this.copyValue.personalScope)
    this.listTarget.replaceChildren()
    const people = new Map((this.snapshot?.participants || []).map(row =>
      [row.id, row.name]))
    for (const row of this.items) {
      const on = this.selected(row, cfg)
      const card = this.el("article", "sd-ai-context-message" +
        (row.incoming ? "" : " sd-ai-context-message--own") +
        (on ? "" : " sd-ai-context-message--excluded"))
      const head = this.el("div", "sd-ai-context-message__head")
      const initial = people.get(row.author_id)?.slice(0, 1)?.toUpperCase() || "?"
      head.append(this.el("span", "sd-ai-context-message__avatar", initial))
      head.append(this.el("strong", "", people.get(row.author_id) || this.copyValue.member))
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
    const selected = cfg.kind === "all" ?
      Math.max(0, (this.snapshot?.eligible_total || 0) - cfg.excluded.length) :
      cfg.kind === "author" ?
        (this.snapshot?.participants || []).find(row => row.id === cfg.authorId)?.eligible_count ?? 0 :
      cfg.included.length
    const displayedSelected = this.items.filter(row => this.selected(row, cfg)).length
    this.metricsTarget.textContent = this.copyValue.metrics
      .replace("{eligible}", String(this.snapshot?.eligible_total ?? "—"))
      .replace("{shown}", String(this.snapshot?.filtered_total ?? "—"))
      .replace("{selected}", String(selected))
      .replace("{page}", String(this.items.length))
      .replace("{onPage}", String(displayedSelected))
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
    const name = (this.nameTarget.value.trim() || this.defaultName()).slice(0, 80)
    if (!name || this.namedSets.length >= 30) {
      this.noticeTarget.textContent = this.copyValue.setLimit
      return
    }
    this.namedSets.push({name, config: JSON.parse(JSON.stringify(this.current())),
      date: new Date().toISOString()})
    if (!this.persistLocal()) {
      this.namedSets.pop()
      this.noticeTarget.textContent = this.copyValue.storageFailed
      return
    }
    this.nameTarget.value = ""
    this.renderSaved()
    this.noticeTarget.textContent = this.copyValue.localSaved
  }

  renderSaved() {
    this.savedTarget.replaceChildren()
    for (const [index, row] of this.namedSets.entries()) {
      const count = row.config.kind === "all" ?
        Math.max(0, (this.snapshot?.eligible_total || 0) - row.config.excluded.length) :
        row.config.kind === "author" ?
          ((this.snapshot?.participants || []).find(p => p.id === row.config.authorId)?.eligible_count || 0) :
          row.config.included.length
      const button = this.el("button", "sd-ai-context-saved__item",
        row.name + " · " + String(count) + " · " + row.config.kind)
      button.type = "button"
      button.addEventListener("click", () => {
        const next = JSON.parse(JSON.stringify(row.config))
        if (this.scope === "shared") this.shared = next
        else this.overrides[this.scope] = next
        this.render()
        this.noticeTarget.textContent = this.copyValue.loaded
      })
      this.savedTarget.append(button)
    }
    if (!this.namedSets.length) this.savedTarget.append(this.el("span", "",
      this.copyValue.noSets))
  }

  answer() {
    return this.application.getControllerForElementAndIdentifier(
      this.element, "ai-answer-entry")
  }

  async apply() {
    const cfg = this.current()
    const target = this.scope === "shared" ?
      (!this.overrides.answer ? "answer" : "none") : this.scope
    // Modes not yet wired to the common input contract are explicitly local
    // configuration drafts, never misrepresented as live provider behavior.
    if (target !== "answer") {
      this.noticeTarget.textContent = this.copyValue.savedButNotWired
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
        await answer.clearContextSelection()
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
      if (!this.persistLocal()) throw new Error("storage")
      this.noticeTarget.textContent = this.copyValue.appliedBounded
    } catch (error) {
      this.noticeTarget.textContent = error.message === "notBounded" ?
        this.copyValue.boundedLimit : error.message === "noIncoming" ?
          this.copyValue.noIncoming : this.copyValue.unavailable
    } finally {
      this.applyTarget.disabled = false
    }
  }
}
