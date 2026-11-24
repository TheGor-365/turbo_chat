import { Controller } from "@hotwired/stimulus"

// Human-reviewed contextual AI Answer with budget/consent preflight; the user
// selects either independent Send. No automatic publication or repeat billing.
export default class extends Controller {
  static targets = ["trigger", "status", "consent", "consentStatus", "result", "resultText", "resultHeading", "candidateHead", "cost", "candidate", "candidateLabel", "composer", "sendAi", "body", "regenerate", "settings", "grip", "readiness", "readinessText", "readinessAction", "previewAction", "planButton", "planPanel", "planBody", "planStatus"]
  static values = { goalUrl: String, consentUrl: String, previewUrl: String, generateUrl: String, synthetic: Boolean, copy: Object, planCopy: Object, preferenceOptions: Object, instructionsUrl: String }

  connect() {
    this.epoch = 0
    this.planEpoch = 0
    this.planOpen = false
    this.planMotion = null
    this.planMotionId = 0
    this.planDrag = null
    this.planSaving = false
    this.planFullSources = null
    this.planSourceToken = null
    this.answerSelection = null
    this.pending = false
    this.goal = null
    this.access = null
    this.generated = null
    this.aiSubmission = null
    this.needsRegeneration = false
    this.customAiHeight = false
    this.form = this.element.querySelector("form.message-composer")
    this.boundFormData = event => this.formData(event)
    this.form?.addEventListener("formdata", this.boundFormData)
    this.boundResize = () => { this.alignTwin(); this.positionPlan() }
    window.addEventListener("resize", this.boundResize)
    this.boundPlanOutside = event => this.dismissPlanOutside(event)
    this.boundPlanKeydown = event => this.dismissPlanOnEscape(event)
    document.addEventListener("pointerdown", this.boundPlanOutside)
    document.addEventListener("keydown", this.boundPlanKeydown)
    this.sizeObserver = window.ResizeObserver ? new ResizeObserver(this.boundResize) : null
    for (const element of [
      this.element.querySelector(".composer-controls"),
      this.element.querySelector(".composer-controls .sd-composer-editor-field"),
      this.element.querySelector(".composer-controls button.composer-send")
    ]) {
      if (element) this.sizeObserver?.observe(element)
    }
    this.boundContextUpdated = () => this.refresh()
    this.element.addEventListener("ai-room-context:updated", this.boundContextUpdated)
    this.changed()
    this.refresh()
  }

  disconnect() {
    this.epoch += 1
    this.planEpoch += 1
    this.planMotionId += 1
    this.planMotion?.cancel()
    this.planMotion = null
    this.form?.removeEventListener("formdata", this.boundFormData)
    this.element.removeEventListener("ai-room-context:updated", this.boundContextUpdated)
    window.removeEventListener("resize", this.boundResize)
    document.removeEventListener("pointerdown", this.boundPlanOutside)
    document.removeEventListener("keydown", this.boundPlanKeydown)
    this.sizeObserver?.disconnect()
  }

  editor() { return this.bodyTarget }
  text(key, data = {}) {
    let msg = this.copyValue[key] || key
    for (const [k, v] of Object.entries(data)) msg = msg.replaceAll("{" + k + "}", String(v))
    return msg
  }

  changed() {
    // The human and AI editors are independent. Typing in the lower one
    // changes the next generation action to Beautify, but does NOT delete the
    // already reviewed AI candidate or steal its separate Send.
    if (this.pending) ++this.epoch
    this.hidePlan()
    if (this.editor().value.trim()) this.hideReadiness()
    this.element.dataset.aiComposerMode =
      this.editor().value.trim() ? "beautify" : "answer"
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
      if (this.generated && !access.ready) this.discard()
      if (!access.ready || (this.answerSelection &&
          goal.current_revision !== this.answerSelection.goalRevision)) {
        this.answerSelection = null
        this.planFullSources = null
        this.planSourceToken = null
      }
      if (this.generated && goal.current_revision !== this.generated.goalRevision) {
        this.needsRegeneration = true
      }
      this.render()
    } catch (_) {
      if (epoch !== this.epoch || !this.element.isConnected) return
      this.statusTarget.textContent = this.text("unavailable")
      this.statusTarget.dataset.state = "error"
    }
  }

  render() {
    const personalOff = this.element.dataset.personalAiEnabled !== "true"
    this.triggerTarget.disabled = this.pending || personalOff
    this.updateAiActions()
    const draft = this.editor().value.trim()
    let label, state
    if (personalOff) {
      label = this.element.querySelector("[data-personal-ai-readiness-target='label']")?.textContent || this.element.dataset.personalAiOffLabel
      state = "provider"
    } else if (!this.goal || !this.access) {
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
    } else if (!this.hasGenerateUrlValue) {
      label = this.text("modelOff")
      state = "provider"
    } else {
      label = this.text(this.syntheticValue ? "syntheticReady" : "paidReady")
      state = "ready"
    }
    this.statusTarget.textContent = label
    this.statusTarget.dataset.state = state
    const hint = !this.hasGenerateUrlValue ? "buttonHint" :
      (this.syntheticValue ? "syntheticButtonHint" : "paidButtonHint")
    this.triggerTarget.title = this.text(hint) + " · " + label
    this.triggerTarget.setAttribute("aria-label", this.text("button") + " · " + label)
    this.triggerTarget.dataset.state = state
    this.element.dataset.aiComposerMode =
      this.editor().value.trim() ? "beautify" : "answer"
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

  // Clicking Answer is an intent to generate, not consent to be taken into
  // a full unrelated settings wizard. Explain each blocking gate in place.
  showReadiness(state, message) {
    if (!this.hasReadinessTarget) return
    this.readinessTarget.dataset.state = state
    this.readinessTextTarget.textContent = message
    const configure = state === "goal" || state === "consent"
    this.readinessActionTarget.hidden = !configure
    this.readinessActionTarget.textContent = state === "goal"
      ? this.text("configureGoal") : this.text("configureConsent")
    this.previewActionTarget.hidden = state !== "provider"
    this.readinessTarget.hidden = false
  }

  hideReadiness() {
    if (!this.hasReadinessTarget) return
    this.readinessTarget.hidden = true
    delete this.readinessTarget.dataset.state
  }

  resolveReadiness() {
    if (!this.hasReadinessTarget || this.readinessTarget.hidden) return
    const kind = this.readinessTarget.dataset.state
    this.hideReadiness()
    if (kind === "goal") this.openSettings(".sd-room-ai-instructions",
      ".sd-room-ai-instructions__summary")
    if (kind === "consent") this.openSettings(".sd-ai-room-option--smart",
      "[data-ai-draft-target='smartReplyToggle']")
  }

  openSettings(selector, focusSelector) {
    const draft = this.application.getControllerForElementAndIdentifier(this.element, "ai-draft")
    if (!draft) {
      this.statusTarget.textContent = this.text("unavailable")
      return
    }
    // Room purpose must open the canonical versioned Instructions editor.
    // Consent and other settings still use the Room pane.
    if (selector === ".sd-room-ai-instructions") draft.openInstructions()
    else draft.showSettings()
    const section = this.element.querySelector(selector)
    const fold = section?.querySelector("details")
    if (fold) fold.open = true
    const target = section?.querySelector(focusSelector || "button, textarea, summary")
    target?.focus({preventScroll: false})
    section?.scrollIntoView({block: "nearest"})
  }

  async open() {
    if (this.element.dataset.personalAiEnabled !== "true" || this.pending || this.planSaving) return
    if (this.editor().value.trim()) {
      this.statusTarget.textContent = this.text("emptyEditor")
      this.editor().focus()
      return
    }
    // Read the current goal and grants on EVERY user click, not only on mount.
    await this.refresh()
    if (!this.goal || !this.access) return
    if (!this.goal.configured) {
      this.showReadiness("goal", this.text("missingGoal"))
      return
    }
    if (!this.access.ready) {
      this.showReadiness("consent", this.text("missingConsent",
        {granted: this.access.granted, members: this.access.members}))
      return
    }
    if (!this.hasGenerateUrlValue) {
      this.showReadiness("provider", this.text("modelOff"))
      return
    }
    this.hideReadiness()
    if (!window.confirm(this.text(this.syntheticValue ? "confirmSynthetic" : "confirmSpend"))) return
    await this.generate()
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
      this.discard()
      this.access = null
    } catch (_) {
      this.consentStatusTarget.textContent = this.text("unavailable")
    } finally {
      this.pending = false
      await this.refresh()
    }
  }

  // B17: same physical room anchor as Context/Message/Room, but the Plan
  // keeps its existing preview owner, accessible resize grip and exit motion.
  // Read-only DOM geometry; never changes room data or sends a message.
  positionPlan() {
    if (!this.hasPlanPanelTarget) return
    const room = document.querySelector("#room_container")
    if (!room) return
    const bounds = room.getBoundingClientRect()
    const gutter = window.innerWidth <= 620 ? 0 : 16
    this.planPanelTarget.style.setProperty("--sd-g1-plan-left",
      Math.round(Math.max(gutter, bounds.left + gutter)) + "px")
    this.planPanelTarget.style.setProperty("--sd-g1-plan-right",
      Math.round(Math.max(gutter, window.innerWidth - bounds.right + gutter)) + "px")
  }

  // T1: inspect only the server-owned compiled contract; never call a model,
  // reserve budget, mutate the conversation, or trust user text as HTML.
  // Keep space in the composer flowing during open/close. WAAPI also lets
  // a new click reverse an unfinished animation without racing an old 'finish'.
  animatePlan(open) {
    const panel = this.planPanelTarget
    const wasHidden = panel.hidden
    const fromHeight = wasHidden ? 0 : panel.getBoundingClientRect().height
    const previousOpacity = wasHidden ? 0 : Number.parseFloat(
      window.getComputedStyle(panel).opacity) || 0
    const previousTransform = wasHidden ? "translateY(8px)" :
      window.getComputedStyle(panel).transform
    const sequence = ++this.planMotionId
    this.planMotion?.cancel()
    this.planMotion = null
    if (open) panel.hidden = false
    const toHeight = open ? panel.getBoundingClientRect().height : 0
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
    if (reduced || typeof panel.animate !== "function" ||
        Math.abs(toHeight - fromHeight) < 0.5) {
      panel.hidden = !open
      panel.dataset.motion = open ? "open" : "closed"
      return
    }
    panel.dataset.motion = open ? "opening" : "closing"
    const from = {height: fromHeight + "px", minHeight: "0px",
      paddingTop: fromHeight ? "17px" : "0px",
      paddingBottom: fromHeight ? "10px" : "0px",
      marginBottom: fromHeight ? "7px" : "0px",
      opacity: previousOpacity, transform: previousTransform}
    const to = {height: toHeight + "px", minHeight: "0px",
      paddingTop: open ? "17px" : "0px",
      paddingBottom: open ? "10px" : "0px",
      marginBottom: open ? "7px" : "0px",
      opacity: open ? 1 : 0,
      transform: open ? "translateY(0px)" : "translateY(6px)"}
    const animation = panel.animate([from, to], {
      duration: open ? 250 : 195,
      easing: open ? "cubic-bezier(.2,.75,.2,1)" : "cubic-bezier(.4,0,1,1)",
      fill: "forwards"
    })
    this.planMotion = animation
    animation.finished.then(() => {
      if (sequence !== this.planMotionId) return
      if (!open) panel.hidden = true
      animation.cancel()
      this.planMotion = null
      panel.dataset.motion = open ? "open" : "closed"
    }, () => {})
  }

  // Drag/keyboard resize must never fight with a still-running entrance.
  finishPlanEntrance() {
    if (!this.planMotion || !this.planOpen) return
    this.planMotionId += 1
    this.planMotion.cancel()
    this.planMotion = null
    this.planPanelTarget.dataset.motion = "open"
  }

  hidePlan() {
    if (!this.planOpen) return
    this.planOpen = false
    this.planEpoch += 1
    if (this.hasPlanPanelTarget) this.animatePlan(false)
    if (this.hasPlanButtonTarget) {
      this.planButtonTarget.setAttribute("aria-expanded", "false")
      this.planButtonTarget.classList.remove("is-active")
    }
  }

  dismissPlanOutside(event) {
    if (!this.planOpen || !this.hasPlanPanelTarget) return
    if (this.planPanelTarget.contains(event.target) ||
        this.planButtonTarget.contains(event.target) ||
        event.target.closest?.(".sd-ai-context-launch")) return
    this.hidePlan()
  }

  dismissPlanOnEscape(event) {
    if (event.key !== "Escape" || !this.planOpen ||
        !this.hasPlanPanelTarget) return
    event.preventDefault()
    this.hidePlan()
    this.planButtonTarget.focus({preventScroll: true})
  }

  planElement(tag, className = "", value = null) {
    const el = document.createElement(tag)
    if (className) el.className = className
    if (value !== null && value !== undefined) el.textContent = String(value)
    return el
  }

  planIcon(name) {
    const template = this.planPanelTarget.querySelector("template[data-ai-plan-icons]")
    const source = template?.content.querySelector('[data-plan-icon="' + name + '"] svg')
    return source ? source.cloneNode(true) : this.planElement("span", "sd-ai-plan-icon-fallback")
  }

  planCard(grid, name, title, accent = "neutral", wide = false) {
    const card = this.planElement("section", "sd-ai-plan-card sd-ai-plan-card--" + accent +
      (wide ? " sd-ai-plan-card--wide" : ""))
    const heading = this.planElement("h3", "sd-ai-plan-card__heading")
    const icon = this.planElement("span", "sd-ai-plan-card__icon")
    icon.append(this.planIcon(name))
    heading.append(icon, this.planElement("span", "", title))
    const body = this.planElement("div", "sd-ai-plan-card__content")
    card.append(heading, body)
    grid.append(card)
    return body
  }

  planPair(parent, label, value, mono = false) {
    const row = this.planElement("div", "sd-ai-plan-pair")
    row.append(this.planElement("span", "sd-ai-plan-pair__label", label),
      this.planElement(mono ? "code" : "span", "sd-ai-plan-pair__value", value ?? "—"))
    parent.append(row)
  }

  // Only a deliberately small Markdown subset is formatted. All data still
  // enters the DOM through text nodes (no innerHTML / arbitrary links).
  planInline(parent, text) {
    const input = String(text ?? "")
    const rx = /\*\*([^*\n]{1,240})\*\*/g
    let cursor = 0
    for (const match of input.matchAll(rx)) {
      if (match.index > cursor) parent.append(document.createTextNode(input.slice(cursor, match.index)))
      parent.append(this.planElement("strong", "", match[1]))
      cursor = match.index + match[0].length
    }
    if (cursor < input.length) parent.append(document.createTextNode(input.slice(cursor)))
  }

  planMarkdown(parent, text) {
    const lines = String(text ?? "").replace(/\r\n?/g, "\n").split("\n")
    for (const raw of lines) {
      const line = raw.trim()
      if (!line) continue
      const heading = line.match(/^\*\*([^*]+)\*\*\s*$/)
      if (heading) {
        parent.append(this.planElement("h4", "sd-ai-plan-markdown__heading", heading[1]))
        continue
      }
      const bullet = line.match(/^(\d+[.)]|[-*])\s+(.+)$/)
      const item = this.planElement("p", bullet ? "sd-ai-plan-markdown__item" :
        "sd-ai-plan-markdown__paragraph")
      if (bullet) {
        item.append(this.planElement("span", "sd-ai-plan-markdown__marker", bullet[1] === "-"
          || bullet[1] === "*" ? "•" : bullet[1]))
        const body = this.planElement("span", "sd-ai-plan-markdown__body")
        this.planInline(body, bullet[2])
        item.append(body)
      } else {
        this.planInline(item, line)
      }
      parent.append(item)
    }
  }

  // The Plan is a READ-ONLY projection. Canonical edits live in the existing
  // room settings controller; never add duplicate forms or database owners.
  planCanonicalLink(parent, label, selector, focusSelector) {
    const button = this.planElement("button", "sd-ai-plan-open-canonical", label)
    button.type = "button"
    button.addEventListener("click", () => {
      this.hidePlan()
      this.openSettings(selector, focusSelector)
    })
    parent.append(button)
  }

  // A read-only Plan links to existing, canonical room and draft owners.
  planInstructionsLink(parent, label) {
    const button = this.planElement("button", "sd-ai-plan-open-canonical", label)
    button.type = "button"
    button.addEventListener("click", () => {
      this.hidePlan()
      this.element.querySelector(".sd-room-instructions-launch")?.click()
    })
    parent.append(button)
  }

  planMessageSettingsLink(parent, label) {
    const button = this.planElement("button", "sd-ai-plan-open-canonical", label)
    button.type = "button"
    button.addEventListener("click", () => {
      this.hidePlan()
      this.application.getControllerForElementAndIdentifier(
        this.element, "ai-draft")?.showEditor()
    })
    parent.append(button)
  }

  planInstructionsPreview(parent, mode, plan, copy) {
    const section = this.element.querySelector(".sd-room-ai-instructions")
    const revision = mode === "answer" ? plan.room_goal_revision :
      section?.dataset.roomAiInstructionsRevisionValue
    this.planPair(parent, copy.goalRevision, revision || "—", true)
    if (mode !== "answer") {
      parent.append(this.planElement("p", "sd-ai-plan-tip", copy.instructionsNotApplied))
    }
    // Read the canonical SAVED revision, not an unsaved editor buffer.
    const saved = section?.querySelector(
      '[data-room-ai-instructions-target="currentText"]')?.textContent?.trim()
    parent.append(this.planElement("pre", "sd-ai-plan-instruction-text",
      saved || copy.instructionsEmpty))
    this.planInstructionsLink(parent, copy.openInstructionEditor)
  }

  planTaskDetails(parent, task, mode, copy) {
    const details = this.planElement("details", "sd-ai-plan-task-details")
    const summary = this.planElement("summary", "", copy.taskDetails)
    const explanation = this.planElement("p", "",
      mode === "answer" ? copy.taskAnswerDescription : copy.taskBeautifyDescription)
    const id = this.planElement("code", "", task || "")
    details.append(summary, explanation, id)
    parent.append(details)
  }

  planSpeakerLabel(speaker, copy) {
    return speaker === "you" ? copy.yourOutgoing : copy.peerIncoming
  }

  // Rails supplies enum option labels in the active locale. Never overwrite
  // stored IDs or translate user-authored custom text.
  planOptionLabel(group, raw) {
    if (raw == null || raw === "") return "—"
    const id = String(raw)
    const match = (this.preferenceOptionsValue?.[group] || [])
      .find(item => String(item.id) === id)
    return match?.label || id
  }

  planPreferenceOrigin(raw, copy) {
    const labels = {room: copy.originRoom, account: copy.originAccount,
      system: copy.originSystem}
    return labels[raw] || (raw == null ? "—" : String(raw))
  }

  renderPlanCards(data) {
    const copy = this.planCopyValue
    const plan = data.effective_plan
    const ctx = plan.context || {}
    const prefs = plan.writing_preferences || {}
    const mode = data.mode
    const grid = this.planElement("div", "sd-ai-plan-grid")

    const overview = this.planCard(grid, "file-text", copy.mode, "blue")
    this.planPair(overview, copy.mode, mode === "answer" ? copy.modeAnswer : copy.modeBeautify)
    this.planPair(overview, copy.task,
      mode === "answer" ? copy.taskReadableAnswer : copy.taskReadableBeautify)
    this.planTaskDetails(overview, plan.task, mode, copy)
    this.planPair(overview, copy.preferenceSource,
      this.planPreferenceOrigin(plan.preference_origin, copy))

    const settings = this.planCard(grid, "sliders-horizontal", copy.preferences, "violet")
    this.planPair(settings, copy.profile, prefs.profile_id
      ? this.planOptionLabel("profiles", prefs.profile_id) : copy.customProfile)
    this.planPair(settings, copy.style, this.planOptionLabel("styles", prefs.writing_style))
    this.planPair(settings, copy.language, this.planOptionLabel("languages", prefs.language))
    this.planPair(settings, copy.tone, this.planOptionLabel("tones", prefs.tone))
    this.planCanonicalLink(settings, copy.openCanonicalRoomSettings,
      ".sd-ai-experience-profiles", ".sd-ai-experience-profiles__choice")

    if (mode === "answer") {
      const goal = this.planCard(grid, "messages", copy.instructionsTitle, "blue")
      this.planInstructionsPreview(goal, mode, plan, copy)

      const coverage = this.planCard(grid, "filter", copy.coverage, "amber")
      this.planPair(coverage, copy.replyTarget, ctx.reply_to_ref, true)
      this.planPair(coverage, copy.included, ctx.included + " / " + ctx.scanned)
      this.planPair(coverage, copy.candidateLimit, ctx.candidate_limit)
      this.planPair(coverage, copy.omitted, ctx.omitted_within_scan)
      this.planPair(coverage, copy.truncated, ctx.truncated)
      coverage.append(this.planElement("p", "sd-ai-plan-warning", copy.fullHistoryWarning))

    } else {
      const options = plan.one_shot_options || {}
      const current = this.planCard(grid, "palette", copy.oneShot, "violet")
      this.planPair(current, copy.preset, this.planOptionLabel("styles", options.preset_id))
      this.planPair(current, copy.language,
        this.planOptionLabel("languages", options.writing_language))
      this.planPair(current, copy.tone,
        this.planOptionLabel("tones", options.writing_tone))
      const draft = this.planCard(grid, "pencil", copy.draft, "blue")
      this.planMarkdown(draft, data.draft_preview)
      this.planMessageSettingsLink(current, copy.openMessageSettings)
      const instructions = this.planCard(grid, "file-text", copy.instructionsTitle, "blue")
      this.planInstructionsPreview(instructions, mode, plan, copy)
    }

    const cost = this.planCard(grid, "wallet", copy.budget, "amber")
    this.planPair(cost, copy.reservation, plan.on_paid_request_reservation_usd + " USD", true)
    cost.append(this.planElement("p", "sd-ai-plan-tip", copy.noEstimate))

    const safety = this.planCard(grid, "shield-check", copy.safety, "green")
    safety.append(this.planElement("p", "sd-ai-plan-tip", copy.noSend))
    this.planPair(safety, copy.provider, copy.no)
    this.planPair(safety, copy.autoSend, copy.no)

    this.planBodyTarget.replaceChildren(grid)
  }

  async inspectPlan() {
    if (!this.hasPlanButtonTarget || !this.hasPlanPanelTarget ||
        !this.hasPlanBodyTarget || this.pending || this.planSaving) return
    // A settings dialog is the current focus owner. Never open a second UI.
    if (this.element.querySelector("#sd-ai-context-studio[open]")) return
    if (this.planOpen) {
      this.hidePlan()
      return
    }
    this.planOpen = true
    this.positionPlan()
    this.animatePlan(true)
    this.planButtonTarget.setAttribute("aria-expanded", "true")
    this.planButtonTarget.classList.add("is-active")
    await this.reloadPlan()
  }

  async reloadPlan(proposedSelection = null, {allowClosed = false} = {}) {
    if ((!this.planOpen && !allowClosed) || this.pending) return false
    const nonce = ++this.planEpoch
    const draft = this.editor().value
    const mode = draft.trim() ? "beautify" : "answer"
    const copy = this.planCopyValue
    // Preserve the current working controls while checking the next plan.
    // Replacing them with an empty panel caused a disruptive visible flash.
    const scrollTop = this.planBodyTarget.scrollTop
    const previousNotice = this.planNotice
    this.planStatusTarget.textContent = proposedSelection ?
      copy.sourcesSaving : copy.checking
    try {
      let preview = {mode, draft_text: draft}
      if (mode === "answer") {
        if (!this.goal || !this.access) await this.refresh()
        if (nonce !== this.planEpoch || this.editor().value !== draft) return
        if (!this.goal?.configured) throw new Error("goalMissing")
        if (!this.access?.ready) throw new Error("consentMissing")
        preview = {...preview, goal_source: "room_instructions",
          expected_goal_revision: this.goal.current_revision}
        const selected = proposedSelection || this.answerSelection
        if (selected) {
          preview.source_token = selected.sourceToken
          preview.selected_ids = selected.ids
          preview.reply_target_id = selected.targetId
        }
      } else {
        const quick = this.application.getControllerForElementAndIdentifier(
          this.element, "quick-beautify")
        const options = quick?.currentOptions() || {}
        preview = {...preview, preset_id: options.preset || "polish_clarity",
          writing_language: options.language || "auto",
          writing_tone: options.tone || "neutral"}
      }
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content
      if (!csrf) throw new Error("unavailable")
      const response = await fetch(this.previewUrlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf},
        body: JSON.stringify({preview})
      })
      const data = await response.json().catch(() => ({}))
      if (nonce !== this.planEpoch || !this.element.isConnected ||
          this.editor().value !== draft) return
      if (!response.ok) throw new Error(data.error === "context_consent_required" ?
        "consentMissing" : data.error === "invalid_or_stale_input" ?
          "invalid" : "unavailable")
      const plan = data.effective_plan
      if (data.mode !== mode || !plan || plan.schema_version !== 1 ||
          plan.provider_called !== false || plan.budget_reserved !== false ||
          data.message_sent !== false || data.automatic_send_active !== false ||
          !Array.isArray(data.sources) || !Array.isArray(data.source_ids)) {
        throw new Error("unavailable")
      }
      if (mode === "answer") {
        if (!this.planFullSources || !preview.source_token) {
          this.planFullSources = data.sources.map(row => ({...row}))
        }
        this.planSourceToken = data.source_token
        if (proposedSelection) this.answerSelection = {
          ...proposedSelection, goalRevision: data.goal_revision
        }
      }
      if (proposedSelection) {
        this.planNotice = {kind: "sources", text: copy.sourcesSaved
          .replace("{count}", String(data.source_ids.length))
          .replace("{target}", data.effective_plan.context.reply_to_ref)}
      }
      if (this.planOpen) this.renderPlanCards(data)
      this.planBodyTarget.scrollTop = scrollTop
      this.planStatusTarget.textContent = copy.ready
      return true
    } catch (error) {
      if (nonce !== this.planEpoch || !this.element.isConnected) return false
      const key = ["goalMissing", "consentMissing", "invalid"].includes(error.message) ?
        error.message : "unavailable"
      this.planStatusTarget.textContent = proposedSelection ?
        copy.sourceApplyFailed : copy[key]
      // On failure preserve the old selection, the existing checkboxes and
      // the exact user choices; the server has not accepted any new contract.
      this.planNotice = previousNotice
      return false
    }
  }

  // Context Studio is the ONLY source-selection editor. This controller
  // remains the single owner of the signed, revalidated Answer contract.
  async clearContextSelection() {
    this.answerSelection = null
    this.planFullSources = null
    this.planSourceToken = null
    return await this.reloadPlan(null, {allowClosed: true})
  }

  async applyContextSelection(selection) {
    if (!selection || this.pending || this.editor().value.trim()) return false
    return await this.reloadPlan(selection, {allowClosed: true})
  }

  // Same top-edge drag direction as both independent message editor grips.
  planHeight(height) {
    const min = 210
    const max = Math.max(min, Math.min(720, window.innerHeight * .78))
    this.planPanelTarget.style.height = Math.round(Math.min(max, Math.max(min, height))) + "px"
  }

  beginPlanResize(event) {
    if (event.button !== 0 || !this.planOpen) return
    event.preventDefault()
    this.finishPlanEntrance()
    this.planDrag = {id: event.pointerId, y: event.clientY,
      height: this.planPanelTarget.getBoundingClientRect().height}
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  dragPlanResize(event) {
    if (!this.planDrag || this.planDrag.id !== event.pointerId) return
    this.planHeight(this.planDrag.height + this.planDrag.y - event.clientY)
  }

  endPlanResize(event) {
    if (!this.planDrag || this.planDrag.id !== event.pointerId) return
    const grip = event.currentTarget
    if (grip.hasPointerCapture(event.pointerId)) grip.releasePointerCapture(event.pointerId)
    this.planDrag = null
  }

  resizePlanWithKeyboard(event) {
    if (!["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key) ||
        !this.planOpen) return
    event.preventDefault()
    this.finishPlanEntrance()
    const height = this.planPanelTarget.getBoundingClientRect().height
    this.planHeight(event.key === "Home" ? 210 :
      event.key === "End" ? window.innerHeight * .78 :
      height + (event.key === "ArrowUp" ? 24 : -24))
  }

  async preview() {
    this.hideReadiness()
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (!csrf || !this.goal?.configured || !this.access?.ready ||
        this.editor().value.trim()) return
    const epoch = ++this.epoch
    const original = this.editor().value
    this.pending = true
    this.render()
    this.discard()
    this.resultHeadingTarget.textContent = this.text("privacy")
    this.statusTarget.textContent = this.text("preparing")
    try {
      const res = await fetch(this.previewUrlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf},
        body: JSON.stringify({preview: {mode: "answer", draft_text: original,
          goal_source: "room_instructions",
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
      this.resultTarget.dataset.mode = "preview"
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

  canSend() {
    const candidate = this.hasCandidateTarget ? this.candidateTarget.value : ""
    return !this.pending && !this.needsRegeneration &&
      this.generated !== null && candidate.trim().length > 0 &&
      candidate.length <= 5000 && new TextEncoder().encode(candidate).length <= 20000
  }

  candidateChanged() {
    this.resizeCandidate()
    this.sendAiTarget.disabled = !this.canSend()
  }

  updateAiActions() {
    if (this.hasRegenerateTarget) {
      this.regenerateTarget.disabled = this.element.dataset.personalAiEnabled !== "true" || this.pending || !this.generated ||
        !this.needsRegeneration || !this.goal?.configured || !this.access?.ready
    }
    if (this.hasSendAiTarget) this.sendAiTarget.disabled = !this.canSend()
  }

  // Only successfully persisted instruction/preference changes authorize
  // offering a NEW (explicit, chargeable) generation; editing candidate text
  // alone never unlocks regeneration.
  settingsChanged() {
    if (this.planOpen && !this.planSaving) void this.reloadPlan()
    if (this.generated) {
      this.needsRegeneration = true
      this.updateAiActions()
    }
  }

  editSettings() {
    const draft = this.application.getControllerForElementAndIdentifier(
      this.element, "ai-draft")
    draft?.showSettings()
  }

  async regenerate() {
    if (this.element.dataset.personalAiEnabled !== "true" || !this.generated || !this.needsRegeneration || this.pending || this.planSaving) return
    await this.refresh()
    if (!this.goal?.configured || !this.access?.ready) return
    if (!window.confirm(this.text(
      this.syntheticValue ? "confirmSynthetic" : "confirmSpend"))) return
    await this.generate()
  }

  // Mirror the lower human composer: Enter sends the explicitly selected AI
  // candidate, while Shift+Enter inserts a newline. Never invoke native Send.
  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey || event.ctrlKey ||
        event.altKey || event.metaKey || event.isComposing || event.repeat ||
        window.matchMedia("(pointer: coarse)").matches || !this.canSend()) return
    event.preventDefault()
    this.form?.requestSubmit(this.sendAiTarget)
  }

  resizeCandidate() {
    if (!this.hasCandidateTarget || this.candidateTarget.hidden ||
        this.customAiHeight) return
    const editor = this.candidateTarget
    editor.style.height = "auto"
    const max = Math.max(90, window.innerHeight * .32)
    editor.style.height = Math.min(Math.max(editor.scrollHeight, 60), max) + "px"
  }

  alignTwin() {
    if (!this.hasComposerTarget || this.composerTarget.hidden ||
        this.candidateTarget.hidden) return
    const humanField = this.element.querySelector(
      ".composer-controls .sd-composer-editor-field")
    const humanSend = this.element.querySelector(
      ".composer-controls button.composer-send")
    if (!humanField || !humanSend) return
    const row = this.composerTarget
    const a = row.getBoundingClientRect()
    const field = humanField.getBoundingClientRect()
    const send = humanSend.getBoundingClientRect()
    const gap = Math.max(0, send.left - field.right)
    const right = Math.max(0, a.right - send.right)
    const minEditor = 35
    const maxLeft = Math.max(0, a.width - right - send.width - 2 * gap - minEditor)
    const left = Math.min(Math.max(0, field.left - a.left - gap), maxLeft)
    row.style.setProperty("--sd-ai-twin-left", left + "px")
    row.style.setProperty("--sd-ai-twin-gap", gap + "px")
    row.style.setProperty("--sd-ai-twin-right", right + "px")
    row.style.setProperty("--sd-ai-twin-send-width", send.width + "px")
    row.style.setProperty("--sd-ai-twin-send-height", send.height + "px")
  }

  beginResize(event) {
    if (event.button !== 0 || this.candidateTarget.hidden) return
    event.preventDefault()
    this.drag = {id: event.pointerId, y: event.clientY,
      height: this.candidateTarget.getBoundingClientRect().height}
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  setAiHeight(height) {
    const max = Math.max(90, window.innerHeight * .46)
    this.candidateTarget.style.height =
      Math.min(max, Math.max(60, height)) + "px"
    this.customAiHeight = true
  }

  dragResize(event) {
    if (!this.drag || this.drag.id !== event.pointerId) return
    this.setAiHeight(this.drag.height + this.drag.y - event.clientY)
  }

  endResize(event) {
    if (!this.drag || this.drag.id !== event.pointerId) return
    const grip = event.currentTarget
    if (grip.hasPointerCapture(event.pointerId)) grip.releasePointerCapture(event.pointerId)
    this.drag = null
  }

  resizeWithKeyboard(event) {
    if (!["ArrowUp", "ArrowDown", "Home", "End"].includes(event.key) ||
        this.candidateTarget.hidden) return
    event.preventDefault()
    const h = this.candidateTarget.getBoundingClientRect().height
    const next = event.key === "Home" ? 60 : event.key === "End"
      ? window.innerHeight * .46 : h + (event.key === "ArrowUp" ? 24 : -24)
    this.setAiHeight(next)
  }

  discard() {
    this.generated = null
    this.needsRegeneration = false
    this.customAiHeight = false
    this.aiSubmission = null
    if (this.hasCandidateTarget) {
      this.candidateTarget.value = ""
      this.candidateTarget.hidden = true
    }
    if (this.hasSendAiTarget) this.sendAiTarget.hidden = true
    if (this.hasCandidateHeadTarget) this.candidateHeadTarget.hidden = true
    if (this.hasCostTarget) {
      this.costTarget.hidden = true
      this.costTarget.textContent = ""
    }
    if (this.hasCandidateLabelTarget) this.candidateLabelTarget.hidden = true
    if (this.hasComposerTarget) this.composerTarget.hidden = true
    if (this.hasCandidateTarget) this.candidateTarget.style.height = ""
    this.updateAiActions()
    if (this.hasResultTarget) {
      this.resultTarget.hidden = true
      delete this.resultTarget.dataset.mode
    }
  }

  async generate() {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    if (this.element.dataset.personalAiEnabled !== "true" || !csrf || !globalThis.crypto?.randomUUID || !this.hasGenerateUrlValue ||
        this.planSaving || !this.goal?.configured || !this.access?.ready) return
    const goalRevision = this.goal.current_revision
    const selection = this.answerSelection?.goalRevision === goalRevision ?
      {...this.answerSelection} : null
    const epoch = ++this.epoch
    this.pending = true
    this.discard()
    this.render()
    this.statusTarget.textContent = this.text("generating")
    try {
      const response = await fetch(this.generateUrlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: {"Content-Type": "application/json", Accept: "application/json",
          "X-CSRF-Token": csrf},
        body: JSON.stringify({answer: {
          confirmed: "1", draft_text: "", goal_source: "room_instructions",
          expected_goal_revision: goalRevision, request_id: crypto.randomUUID(),
          ...(selection ? {source_token: selection.sourceToken,
            selected_ids: selection.ids, reply_target_id: selection.targetId} : {})
        }})
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || "provider_unavailable")
      if (epoch !== this.epoch || !this.element.isConnected) return
      if (data.mode !== "answer" || data.message_sent !== false ||
          data.automatic_send_active !== false || data.goal_revision !== goalRevision ||
          typeof data.text !== "string" || !data.text.trim() || data.text.length > 5000 ||
          typeof data.provenance_token !== "string" || data.provenance_token.length < 20 ||
          !Array.isArray(data.source_ids) || !data.source_ids.length ||
          typeof data.cost_usd !== "string" ||
          data.synthetic !== this.syntheticValue) throw new Error("provider_unavailable")
      if (this.syntheticValue &&
          (data.provider_called !== false || data.budget_reserved !== false ||
           data.cost_usd !== "0.000000" || data.model !== "synthetic-local-no-ai")) {
        throw new Error("provider_unavailable")
      }
      if (!this.syntheticValue &&
          (data.provider_called !== true || data.budget_reserved !== true)) {
        throw new Error("provider_unavailable")
      }
      this.generated = {source: data.text, proof: data.provenance_token,
        goalRevision, sourceIds: data.source_ids}
      this.resultHeadingTarget.textContent =
        this.text(this.syntheticValue ? "syntheticResultTitle" : "aiResultTitle")
      this.resultTextTarget.textContent =
        this.text(this.syntheticValue ? "syntheticResultMeta" : "aiResultMeta", {
          model: data.model || "xAI", cost: data.cost_usd,
          count: data.source_ids.length
        })
      // The diagnostics remain available on hover, not above the editor.
      if (this.hasSettingsTarget) {
        this.settingsTarget.title = this.text("editSettings") + " · " +
          this.text("auditTooltip", {model: data.model, cost: data.cost_usd,
            count: data.source_ids.length})
      }
      // Same visible actual charge as Beautify, never for free preview.
      this.costTarget.textContent = "$" + data.cost_usd
      this.costTarget.hidden = false
      this.candidateHeadTarget.hidden = false
      this.resultTarget.dataset.costUsd = data.cost_usd
      this.resultTarget.dataset.sourceCount = String(data.source_ids.length)
      this.candidateTarget.value = data.text
      this.candidateTarget.hidden = false
      this.candidateLabelTarget.hidden = false
      this.composerTarget.hidden = false
      this.sendAiTarget.hidden = false
      this.sendAiTarget.disabled = !this.canSend()
      this.resultTarget.dataset.mode = "candidate"
      this.resultTarget.hidden = false
      this.resizeCandidate()
      this.alignTwin()
      this.statusTarget.textContent = this.text(this.syntheticValue ? "syntheticCandidateReady" : "candidateReady")
      this.updateAiActions()
    } catch (e) {
      if (epoch !== this.epoch || !this.element.isConnected) return
      const key = ["context_consent_required", "invalid_or_stale_input",
        "budget_unavailable", "provider_unavailable"].includes(e.message) ?
        e.message : "provider_unavailable"
      this.statusTarget.textContent = this.text(key)
    } finally {
      const finalMessage = this.statusTarget.textContent
      this.pending = false
      this.render()
      if (epoch === this.epoch) this.statusTarget.textContent =
        this.generated ? this.text(this.syntheticValue ? "syntheticCandidateReady" : "candidateReady") : finalMessage
      if (this.hasSendAiTarget) this.sendAiTarget.disabled = !this.canSend()
    }
  }

  beforeSubmit(event) {
    this.aiSubmission = null
    if (event.submitter !== this.sendAiTarget) return
    if (event.defaultPrevented || !this.canSend()) {
      event.preventDefault()
      return
    }
    this.aiSubmission = {
      body: this.candidateTarget.value,
      source: this.generated.source,
      proof: this.generated.proof
    }
  }

  formData(event) {
    if (!this.aiSubmission) return
    // The top AI arrow sends ONLY its reviewed text. Files or a reply target
    // queued in the lower human composer must never be attached implicitly.
    event.formData.delete("message[attachments][]")
    event.formData.delete("message[reply_to_id]")
    event.formData.set("message[send_variant]", "ai")
    event.formData.set("message[ai_body]", this.aiSubmission.body)
    event.formData.set("message[ai_source]", this.aiSubmission.source)
    event.formData.set("message[ai_proof]", this.aiSubmission.proof)
  }

  submitEnd(event) {
    this.aiSubmission = null
    if (event.detail.success) this.discard()
  }
}
