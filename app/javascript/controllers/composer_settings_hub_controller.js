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
  connect() {
    this.room = this.element.closest(".msg-form")
    this.onChange = () => this.queueRender()
    this.onRefresh = () => this.queueRender()
    document.addEventListener("change", this.onChange, true)
    document.addEventListener("ai-draft:preferences-saved", this.onRefresh)
    document.addEventListener("ai-room-context:updated", this.onRefresh)
    this.dialog = this.buildConsentDialog()
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
    document.removeEventListener("ai-room-context:updated", this.onRefresh)
    this.dialog?.remove()
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
    // No consent toggle from a tiny badge: authorizations need full context.
    // Auto Reply is explicitly unavailable; only reveal its explanation.
    if (["consent", "contextReady", "auto"].includes(key)) {
      this.showConsentStatus(key, event.currentTarget)
      return
    }
    if (!source || source.disabled) {
      this.openRoomSettings(event.currentTarget, key)
      return
    }
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


  copy(key) {
    const ru = document.documentElement.lang?.toLowerCase().startsWith("ru")
    const dictionary = ru ? {
      title: "Доступ AI к истории", close: "Закрыть", allowed: "Разрешено",
      missing: "Не разрешено", own: "вы", allow: "Разрешить использовать мои сообщения",
      revoke: "Отозвать моё разрешение", waiting: "Для использования переписки необходимо отдельное согласие каждого участника.",
      ready: "Все участники согласились. Доступность AI-модели проверяется отдельно.",
      unavailable: "Актуальные разрешения недоступны.", request: "Подготовить запрос в чат",
      requestText: "Пожалуйста, проверь разрешения AI в этой комнате. Если согласен на обработку истории, включи «Мой допуск AI» в разделе «Состояние». Решение за тобой.",
      auto: "Автоматические ответы ещё недоступны. Отправка без участия человека запрещена.",
      noMembers: "Нет данных об участниках."
    } : {
      title: "AI history permissions", close: "Close", allowed: "Allowed",
      missing: "Not allowed", own: "you", allow: "Allow AI to use my messages",
      revoke: "Revoke my permission", waiting: "Each participant must independently permit AI context.",
      ready: "All participants have consented. AI model availability is a separate check.",
      unavailable: "Current permissions unavailable.", request: "Prepare request in chat",
      requestText: "Please review AI history access for this room. If you agree, enable your own AI access in Status. The decision is yours.",
      auto: "Automatic replies are not available. Unattended sending is disabled.",
      noMembers: "No participant data yet."
    }
    return dictionary[key]
  }

  buildConsentDialog() {
    const dialog = document.createElement("dialog")
    dialog.className = "sd-consent-explain-dialog"
    dialog.style.cssText = "width:min(540px,calc(100vw - 32px));max-width:540px;background:#1e2437;color:#f1f3fa;border:1px solid #565c78;border-radius:14px;padding:24px;box-shadow:0 20px 65px #0009"
    const title = document.createElement("h2")
    title.textContent = this.copy("title")
    title.style.cssText = "font-size:1.15rem;margin:0 0 12px"
    const summary = document.createElement("p")
    summary.dataset.consentSummary = ""
    const members = document.createElement("ul")
    members.dataset.consentMembers = ""
    members.style.cssText = "padding-left:20px;line-height:1.8"
    const buttons = document.createElement("div")
    buttons.style.cssText = "display:flex;gap:8px;flex-wrap:wrap;margin-top:16px"
    for (const [name, label, callback] of [
      ["own", this.copy("allow"), () => this.changeOwnConsent()],
      ["request", this.copy("request"), () => this.prepareConsentRequest()],
      ["close", this.copy("close"), () => dialog.close()]
    ]) {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.consentAction = name
      button.textContent = label
      button.style.cssText = "padding:10px 12px;background:#343b56;color:inherit;border:1px solid #636b89;border-radius:8px"
      button.addEventListener("click", callback)
      buttons.append(button)
    }
    dialog.append(title, summary, members, buttons)
    dialog.addEventListener("close", () => this.dialogTrigger?.focus?.({preventScroll:true}))
    document.body.append(dialog)
    return dialog
  }

  async showConsentStatus(key, trigger) {
    this.dialogMode = key
    this.dialogTrigger = trigger
    if (!this.dialog.open) this.dialog.showModal()
    await this.refreshConsentStatus()
  }

  async refreshConsentStatus() {
    if (!this.dialog?.open) return
    const draft = this.room && this.application.getControllerForElementAndIdentifier(this.room, "ai-draft")
    if (!draft) return
    if (this.dialogMode !== "auto") await draft.loadSmartReplyStatus()
    if (!this.dialog?.open) return
    const data = draft.lastConsentStatus
    const summary = this.dialog.querySelector("[data-consent-summary]")
    const list = this.dialog.querySelector("[data-consent-members]")
    const own = this.dialog.querySelector("[data-consent-action='own']")
    const request = this.dialog.querySelector("[data-consent-action='request']")
    list.replaceChildren()
    own.hidden = this.dialogMode === "auto" || !data || data.consent_available !== true
    request.hidden = this.dialogMode === "auto"
    if (this.dialogMode === "auto") {
      summary.textContent = this.copy("auto")
      request.hidden = true
      return
    }
    const participants = Array.isArray(data?.participants) ? data.participants : []
    summary.textContent = !data ? this.copy("unavailable") :
      data.ready ? this.copy("ready") : this.copy("waiting")
    const ownId = Number(this.room.dataset.aiDraftUserId)
    for (const member of participants) {
      const item = document.createElement("li")
      item.textContent = String(member.name || "") + " — " +
        this.copy(member.enabled ? "allowed" : "missing") +
        (member.id === ownId ? " (" + this.copy("own") + ")" : "")
      list.append(item)
    }
    if (!participants.length) {
      const item = document.createElement("li")
      item.textContent = this.copy("noMembers")
      list.append(item)
    }
    own.textContent = this.copy(data?.enabled ? "revoke" : "allow")
    own.disabled = !!draft.consentUpdating
    request.hidden = !participants.some(m => m.id !== ownId && !m.enabled)
  }

  async changeOwnConsent() {
    const draft = this.room && this.application.getControllerForElementAndIdentifier(this.room, "ai-draft")
    if (!draft || draft.consentUpdating) return
    await draft.toggleSmartReplies()
    await this.refreshConsentStatus()
  }

  prepareConsentRequest() {
    // Never grant consent for others or send automatically. Human reviews and sends.
    const editor = this.room?.querySelector("#chat-text")
    if (!editor || editor.value.trim()) return
    editor.value = this.copy("requestText")
    editor.dispatchEvent(new Event("input", {bubbles:true}))
    this.dialog.close()
    editor.focus()
  }

  openRoomSettings(trigger = null, key = null) {
    const draft = this.application.getControllerForElementAndIdentifier(
      this.room, "ai-draft")
    if (!draft) return
    draft.lastSheetTrigger = trigger
    draft.showSettings()
    const target = key === "auto"
      ? draft.settingsPanelTarget.querySelector(".sd-ai-room-option--auto")
      : key === "consent" || key === "contextReady"
        ? draft.settingsPanelTarget.querySelector(".sd-ai-room-option--smart")
        : null
    if (target) {
      const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches
      target.scrollIntoView({block: "center", behavior: reduced ? "instant" : "smooth"})
      const button = target.querySelector("button[role='switch']")
      button?.focus({preventScroll: true})
    }
  }
}
