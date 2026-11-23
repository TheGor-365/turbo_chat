import { Controller } from "@hotwired/stimulus"

// D3.1a: visible status/proxy for existing canonical controllers, not a new
// settings owner. Never use localStorage or PATCH from this controller.
// Reversible local switches delegate to their existing DOM controls.
// Consent/grants remain an explicit action in the canonical Room editor.
const SOURCES = {
  spelling: "[data-ai-draft-target='spellToggle']",
  consent: "[data-ai-draft-target='smartReplyToggle']",
  auto: ".sd-ai-room-switch--locked",
  contextReady: ".msg-form",
  translation: "[data-incoming-translation-target='toggle']",
  detailed: "[data-simple-chat-target='detailToggle']"
}

export default class extends Controller {
  static targets = ["consentDialog", "consentMembers", "consentSummary", "consentOwn",
    "consentRequest", "consentNotice"]
  static values = { copy: Object }

  connect() {
    this.room = this.element.closest(".msg-form")
    this.consentStatus = null
    this.working = false
    this.onConsentChanged = event => {
      this.consentStatus = event.detail?.status || null
      if (this.consentStatus) this.syncRoomMemberCount(this.consentStatus)
      if (this.hasConsentDialogTarget && this.consentDialogTarget.open) this.renderConsentDialog()
      this.queueRender()
    }
    this.room?.addEventListener("ai-consent:changed", this.onConsentChanged)
    this.onChange = () => this.queueRender()
    this.onRefresh = () => this.queueRender()
    document.addEventListener("change", this.onChange, true)
    document.addEventListener("ai-draft:preferences-saved", this.onRefresh)
    this.observers = []
    for (const key of Object.keys(SOURCES)) {
      const node = this.source(key)
      if (!node) continue
      const observer = new MutationObserver(() => this.queueRender())
      observer.observe(node, {
        attributes: true, attributeFilter: ["aria-checked", "disabled", "data-enabled"]
      })
      this.observers.push(observer)
    }
    if (this.room) {
      const observer = new MutationObserver(() => this.queueRender())
      observer.observe(this.room, {attributes: true,
        attributeFilter: ["data-ai-room-context-ready"]})
      this.observers.push(observer)
    }
    this.queueRender()
    // The source controllers restore room/browser/consent asynchronously.
    this.initialRefresh = window.setTimeout(() => this.queueRender(), 180)
  }

  disconnect() {
    document.removeEventListener("change", this.onChange, true)
    document.removeEventListener("ai-draft:preferences-saved", this.onRefresh)
    this.room?.removeEventListener("ai-consent:changed", this.onConsentChanged)
    this.observers?.forEach(observer => observer.disconnect())
    if (this.initialRefresh) window.clearTimeout(this.initialRefresh)
    if (this.renderFrame) window.cancelAnimationFrame(this.renderFrame)
  }

  source(key) {
    // The translation and display controllers may be mounted above the dock.
    if (key === "contextReady") return this.room
    return (this.room || document).querySelector(SOURCES[key]) ||
      document.querySelector(SOURCES[key])
  }

  queueRender() {
    if (this.renderFrame) return
    this.renderFrame = window.requestAnimationFrame(() => {
      this.renderFrame = null
      this.render()
    })
  }

  render() {
    this.element.querySelectorAll("[data-composer-setting]").forEach(button => {
      const key = button.dataset.composerSetting
      const node = this.source(key)
      const unavailable = !node || key === "auto"
      const enabled = !unavailable && (key === "contextReady"
        ? node.dataset.aiRoomContextReady === "true"
        : node.matches("input[type='checkbox']")
          ? node.checked === true
          : node.getAttribute("aria-checked") === "true")
      const draft = this.application.getControllerForElementAndIdentifier(
        this.room, "ai-draft")
      const unknownReadiness = key === "contextReady" &&
        node?.dataset.aiRoomContextReady == null
      const consentError = key === "consent" && draft?.contextStatusError === true
      const waiting = unknownReadiness || (key === "consent" && node?.disabled === true)
      const state = unavailable || consentError ? "locked" :
        waiting ? "pending" : enabled ? "on" : "off"
      button.dataset.state = state
      button.setAttribute("aria-pressed", String(enabled))
      const label = button.dataset.label || key
      const stateLabel = state === "locked" ? button.dataset.locked :
        state === "pending" ? button.dataset.pending :
          state === "on" ? button.dataset.on : button.dataset.off
      button.setAttribute("aria-label", label + ": " + stateLabel)
      button.title = label + ": " + stateLabel + (button.dataset.help ? " · " + button.dataset.help : "")
      const output = button.querySelector("[data-setting-value]")
      if (output) output.textContent = stateLabel
    })
  }

  activate(event) {
    event.preventDefault()
    const key = event.currentTarget.dataset.composerSetting
    const source = this.source(key)
    if (key === "consent" || key === "auto") {
      void this.openConsentDialog(key)
      return
    }
    if (key === "contextReady") {
      if (this.room?.dataset.aiRoomContextReady === "true") {
        // The canonical Context workspace is the only source-selection owner.
        const tab = this.room.querySelector("#sd-mobile-workspace [data-workspace-tab='context']")
        if (tab) tab.click()
        else this.application.getControllerForElementAndIdentifier(
          this.room, "ai-context-studio")?.open(event)
      } else {
        void this.openConsentDialog(key)
      }
      return
    }
    if (!source || source.disabled) return
    // Settings inputs live inside a normally closed native <dialog>.
    // Browser inertness may suppress .click() on those hidden controls.
    // Delegate to the same existing owner instead of cloning preference
    // state here; every UI click continues to be explicit and device-local.
    if (key === "spelling") {
      const draft = this.application.getControllerForElementAndIdentifier(
        this.room, "ai-draft")
      if (!draft || typeof draft.toggleSpellcheck !== "function") return
      draft.toggleSpellcheck()
    } else if (source.matches("input[type='checkbox']")) {
      source.checked = !source.checked
      source.dispatchEvent(new Event("change", {bubbles: true}))
    } else {
      source.click()
    }
    this.queueRender()
  }


  syncRoomMemberCount(status) {
    if (!Number.isSafeInteger(status.members) || status.members < 1) return
    const details = document.querySelector("#private-group-details")
    if (!details) return
    const count = details.querySelector(".sd-private-group-details__count")
    if (count) count.textContent = String(status.members)
    const summary = details.querySelector("summary")
    const template = summary?.dataset.countLabelTemplate
    if (template) {
      const label = template.replace("{count}", String(status.members))
      summary.setAttribute("aria-label", label)
      summary.title = label
    }
    const dd = details.querySelector(".sd-private-group-details__meta > div:nth-child(2) dd")
    if (dd) dd.textContent = String(status.members)
  }

  async openConsentDialog(key) {
    if (!this.hasConsentDialogTarget) return
    this.consentNoticeTarget.textContent = ""
    this.consentDialogTarget.dataset.reason = key
    if (!this.consentDialogTarget.open) this.consentDialogTarget.showModal()
    const draft = this.application.getControllerForElementAndIdentifier(this.room, "ai-draft")
    if (draft?.latestConsentStatus) this.consentStatus = draft.latestConsentStatus
    this.renderConsentDialog()
    if (draft?.loadSmartReplyStatus) await draft.loadSmartReplyStatus()
    if (!this.consentDialogTarget.open) return
    this.consentStatus = draft?.latestConsentStatus || this.consentStatus
    this.renderConsentDialog()
  }

  closeConsentDialog() {
    if (this.hasConsentDialogTarget && this.consentDialogTarget.open) this.consentDialogTarget.close()
  }

  renderConsentDialog() {
    if (!this.hasConsentDialogTarget) return
    const status = this.consentStatus
    const people = Array.isArray(status?.participants) ? status.participants.filter(p =>
      Number.isSafeInteger(p.id) && typeof p.name === "string" &&
      typeof p.enabled === "boolean") : []
    this.consentMembersTarget.replaceChildren(...people.map(person => {
      const row = document.createElement("li")
      row.className = "sd-consent-access__member"
      const label = document.createElement("span")
      label.textContent = person.name
      const state = document.createElement("strong")
      state.dataset.enabled = String(person.enabled)
      state.textContent = person.enabled ? this.copyValue.on : this.copyValue.off
      row.append(label, state)
      return row
    }))
    const viewer = Number(this.room?.dataset.aiDraftUserId)
    const own = people.find(p => p.id === viewer)
    const missing = people.filter(p => p.id !== viewer && !p.enabled)
    const eligible = status?.consent_available === true
    this.consentSummaryTarget.textContent = !status ? this.copyValue.pending :
      !eligible ? this.copyValue.consentUnavailable :
        status.ready ? this.copyValue.consentReady :
          this.copyValue.consentWaiting.replace("{names}",
            missing.map(p => p.name).join(", ") || this.copyValue.consentSelf)
    this.consentOwnTarget.disabled = this.working || !eligible || !own
    this.consentOwnTarget.textContent = own?.enabled ?
      this.copyValue.revokeMine : this.copyValue.grantMine
    this.consentRequestTarget.hidden = missing.length === 0 || !eligible || status.ready
    this.consentRequestTarget.disabled = this.working
    if (this.consentDialogTarget.dataset.reason === "auto") {
      this.consentNoticeTarget.textContent = this.copyValue.autoDisabled
    }
  }

  async changeMyConsent() {
    if (this.working || !this.consentStatus?.consent_available) return
    const draft = this.application.getControllerForElementAndIdentifier(this.room, "ai-draft")
    if (!draft || typeof draft.toggleSmartReplies !== "function") return
    this.working = true
    this.renderConsentDialog()
    try {
      await draft.toggleSmartReplies()
      this.consentStatus = draft.latestConsentStatus || this.consentStatus
      this.consentNoticeTarget.textContent = draft.contextStatusError ?
        this.copyValue.consentUnavailable : this.copyValue.consentUpdated
    } catch (_) {
      this.consentNoticeTarget.textContent = this.copyValue.consentUnavailable
    } finally {
      this.working = false
      this.renderConsentDialog()
    }
  }

  prepareConsentRequest() {
    const people = this.consentStatus?.participants
    const viewer = Number(this.room?.dataset.aiDraftUserId)
    if (!Array.isArray(people)) return
    const missing = people.filter(p => p.id !== viewer && p.enabled === false &&
      typeof p.name === "string").map(p => p.name)
    if (!missing.length) return
    // Requests only prepare an ordinary human message. No auto-send or grant.
    const editor = this.room?.querySelector("#chat-text")
    if (!editor) return
    if (editor.value.trim()) {
      this.consentNoticeTarget.textContent = this.copyValue.keepDraft
      return
    }
    editor.value = this.copyValue.requestDraft.replace("{names}", missing.join(", "))
    editor.dispatchEvent(new Event("input", {bubbles: true}))
    this.consentNoticeTarget.textContent = this.copyValue.requestPrepared
  }
}
