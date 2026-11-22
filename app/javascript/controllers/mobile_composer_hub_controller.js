import { Controller } from "@hotwired/stimulus"

// G1: one responsive navigation surface, original controls and owners.
// Moving existing DOM preserves grants, source selection and persisted state.
// No synthetic Send, API request, or account settings storage is introduced.
export default class extends Controller {
  static targets = ["statusDialog", "attachmentsDialog"]

  connect() {
    this.inspectors = this.element.querySelector(".sd-composer-inspectors--unified")
    if (!this.inspectors) return
    this.statusDisclosure = this.inspectors.querySelector(".sd-composer-disclosure--status")
    this.statusAnchor = document.createComment("canonical status location")
    this.statusDisclosure.before(this.statusAnchor)
    this.anchor = document.createComment("restore canonical composer controls")
    this.inspectors.before(this.anchor)
    this.mobileQuery = window.matchMedia("(max-width:620px)")
    this.onBreakpoint = () => this.relocate()
    this.mobileQuery.addEventListener("change", this.onBreakpoint)
    this.onInspectorClick = (event) => {
      if (!this.hasStatusDialogTarget || !this.statusDialogTarget.open) return
      const trigger = event.target.closest(
        ".sd-composer-inspector > summary, .sd-composer-tool-trigger, .sd-composer-status-pill")
      if (!trigger) return
      const key = trigger.dataset.composerSetting
      // Reversible spelling/translation/display actions stay inside Status.
      if (key && !["consent", "contextReady", "auto"].includes(key)) return
      this.closeStatus()
    }
    this.inspectors.addEventListener("click", this.onInspectorClick, true)
    this.onBackdrop = event => {
      if (event.target === this.statusDialogTarget) this.closeStatus()
      if (event.target === this.attachmentsDialogTarget) this.closeAttachments()
    }
    this.statusDialogTarget.addEventListener("click", this.onBackdrop)
    this.attachmentsDialogTarget.addEventListener("click", this.onBackdrop)
    this.onOutside = event => {
      if (!this.statusDialogTarget.open || this.statusDialogTarget.contains(event.target) ||
          event.target.closest?.(".sd-mobile-composer-toolbar") ||
          event.target.closest?.(".sd-composer-disclosure--status > summary")) return
      this.closeStatus()
    }
    this.onEscape = event => {
      if (event.key !== "Escape" || !this.statusDialogTarget.open) return
      event.preventDefault()
      this.closeStatus()
    }
    document.addEventListener("pointerdown", this.onOutside)
    document.addEventListener("keydown", this.onEscape)
    this.mountTabs()
    this.observeWorkspaces()
    this.relocate()
  }

  disconnect() {
    this.mobileQuery?.removeEventListener("change", this.onBreakpoint)
    this.inspectors?.removeEventListener("click", this.onInspectorClick, true)
    this.statusDialogTarget?.removeEventListener("click", this.onBackdrop)
    this.attachmentsDialogTarget?.removeEventListener("click", this.onBackdrop)
    document.removeEventListener("pointerdown", this.onOutside)
    document.removeEventListener("keydown", this.onEscape)
    this.closeStatus()
    this.closeAttachments()
    if (this.anchor?.isConnected && this.inspectors) {
      this.anchor.after(this.inspectors)
      this.anchor.remove()
    }
    this.statusAnchor?.remove()
    this.workspaceObserver?.disconnect()
    this.element.querySelectorAll(".sd-workspace-tabs[data-injected]").forEach(node => node.remove())
  }

  relocate() {
    if (!this.inspectors || !this.anchor?.isConnected) return
    if (this.mobileQuery.matches) {
      this.closeStatus()
      if (this.inspectors.parentElement !== this.statusDialogTarget) {
        this.statusDialogTarget.append(this.inspectors)
      }
    } else {
      this.closeStatus()
      this.closeAttachments()
      if (this.inspectors.parentElement !== this.anchor.parentElement) {
        this.anchor.after(this.inspectors)
      }
    }
  }

  mountTabs() {
    const template = this.element.querySelector("#sd-mobile-workspace-tabs")
    if (!template) return
    const destinations = [
      [this.statusDialogTarget, ".sd-mobile-workspace__heading", "status"],
      [this.element.querySelector("#sd-ai-effective-plan"), ".sd-ai-effective-plan__head", "plan"],
      [this.element.querySelector("#sd-ai-context-studio"), ".sd-ai-context-studio__header", "context"],
      [this.element.querySelector("#ai-room-settings"), ".sd-ai-workspace-topbar", "room"],
      [this.element.querySelector("#ai-draft-panel"), ".sd-ai-workspace-topbar", "message"]
    ]
    for (const [root, header, active] of destinations) {
      const anchor = root?.querySelector(header)
      if (!anchor) continue
      const fragment = template.content.cloneNode(true)
      const nav = fragment.querySelector(".sd-workspace-tabs")
      nav.dataset.injected = "true"
      nav.dataset.workspaceOwner = active
      anchor.after(fragment)
    }
  }

  observeWorkspaces() {
    this.workspaceObserver = new MutationObserver(() => this.syncActiveWorkspace())
    for (const selector of ["#sd-mobile-workspace", "#sd-ai-effective-plan",
      "#sd-ai-context-studio", "#ai-room-settings", "#ai-draft-panel"]) {
      const node = this.element.querySelector(selector)
      if (node) this.workspaceObserver.observe(node, {
        attributes: true, attributeFilter: ["open", "hidden", "data-view", "data-motion"]
      })
    }
    this.syncActiveWorkspace()
  }

  syncActiveWorkspace() {
    const root = selector => this.element.querySelector(selector)
    const context = root("#sd-ai-context-studio")
    const room = root("#ai-room-settings")
    const draft = root("#ai-draft-panel")
    const plan = root("#sd-ai-effective-plan")
    const status = root("#sd-mobile-workspace")
    if (context?.open) this.markActive("context")
    else if (room?.open) this.markActive(room.dataset.view === "instructions" ? "instructions" : "room")
    else if (draft?.open) this.markActive("message")
    else if (status?.open) this.markActive("status")
    else if (plan && !plan.hidden && plan.dataset.motion !== "closing") this.markActive("plan")
  }

  markActive(tab) {
    this.element.querySelectorAll(".sd-workspace-tabs [data-workspace-tab]").forEach(button => {
      if (button.dataset.workspaceTab === tab) button.setAttribute("aria-current", "page")
      else button.removeAttribute("aria-current")
    })
  }

  closeStatus() {
    if (this.hasStatusDialogTarget && this.statusDialogTarget.open) this.statusDialogTarget.close()
    if (this.statusAnchor?.isConnected && this.statusDisclosure?.parentElement !== this.inspectors) {
      this.statusAnchor.after(this.statusDisclosure)
      this.statusDisclosure.open = true
    }
  }

  closeAttachments() {
    if (this.hasAttachmentsDialogTarget && this.attachmentsDialogTarget.open) this.attachmentsDialogTarget.close()
  }

  closeExisting() {
    this.closeStatus()
    this.closeAttachments()
    const context = this.element.querySelector("#sd-ai-context-studio")
    if (context?.open) context.close()
    const draft = this.application.getControllerForElementAndIdentifier(this.element, "ai-draft")
    for (const target of [draft?.settingsPanelTarget, draft?.panelTarget]) {
      if (target?.open) target.close()
      if (target) target.hidden = true
    }
    if (draft?.hasBackdropTarget) draft.backdropTarget.hidden = true
    draft?.toggleTarget?.setAttribute("aria-expanded", "false")
    document.body.classList.remove("sd-ai-sheet-open")
    const plan = this.application.getControllerForElementAndIdentifier(this.element, "ai-answer-entry")
    if (plan?.planOpen) plan.hidePlan()
  }

  openStatus(event) { this.openInspector(event, "status") }
  openAi(event) { this.openInspector(event, "ai") }

  openInspector(event, which) {
    event?.preventDefault()
    if (!this.mobileQuery.matches) {
      if (which !== "status") return
      this.closeExisting()
      this.statusDisclosure.open = true
      this.statusDialogTarget.dataset.mode = "status"
      this.statusDialogTarget.append(this.statusDisclosure)
      this.statusDialogTarget.show()
      this.markActive("status")
      this.statusDialogTarget.querySelector(".sd-mobile-workspace__close")?.focus()
      return
    }
    const modeLabel = this.element.querySelector(
      which === "status" ? ".sd-mobile-composer-toolbar [data-action*='openStatus']" :
        ".sd-mobile-composer-toolbar [data-action*='openAi']"
    )?.getAttribute("aria-label")
    this.statusDialogTarget.dataset.mode = which
    if (modeLabel) {
      this.statusDialogTarget.setAttribute("aria-label", modeLabel)
      const heading = this.statusDialogTarget.querySelector(".sd-mobile-workspace__heading strong")
      if (heading) heading.textContent = modeLabel
    }
    if (this.statusDialogTarget.open) {
      this.inspectors.querySelector(".sd-composer-disclosure--status").open = which === "status"
      this.inspectors.querySelector(".sd-composer-disclosure--ai").open = which === "ai"
      this.markActive(which === "status" ? "status" : "room")
      return
    }
    this.closeExisting()
    this.inspectors.querySelector(".sd-composer-disclosure--status").open = which === "status"
    this.inspectors.querySelector(".sd-composer-disclosure--ai").open = which === "ai"
    this.statusDialogTarget.show()
    this.markActive(which === "status" ? "status" : "room")
    this.statusDialogTarget.querySelector(".sd-mobile-workspace__close")?.focus()
  }

  openAttachments(event) {
    event?.preventDefault()
    if (!this.mobileQuery.matches) return
    this.closeExisting()
    this.attachmentsDialogTarget.showModal()
  }

  attachFiles(event) {
    event?.preventDefault()
    this.closeAttachments()
    this.element.querySelector(".composer-attach")?.click()
  }
  camera(event) {
    event?.preventDefault()
    this.closeAttachments()
    this.element.querySelector('.composer-controls button[data-action*="openCamera"]')?.click()
  }
  voice(event) {
    event?.preventDefault()
    this.closeAttachments()
    this.element.querySelector('.composer-controls button[data-message-composer-target="voiceButton"]')?.click()
  }

  navigate(event) {
    event.preventDefault()
    const tab = event.currentTarget.dataset.workspaceTab
    this.closeExisting()
    this.markActive(tab)
    if (tab === "status") { this.openInspector(null, "status"); return }
    const draft = this.application.getControllerForElementAndIdentifier(this.element, "ai-draft")
    if (tab === "message") { draft?.showEditor(); return }
    if (tab === "room") { draft?.showSettings(); return }
    if (tab === "instructions") {
      this.element.querySelector(".sd-room-instructions-launch")?.click()
      return
    }
    if (tab === "context") {
      this.application.getControllerForElementAndIdentifier(
        this.element, "ai-context-studio")?.open()
      return
    }
    if (tab === "plan") {
      this.application.getControllerForElementAndIdentifier(
        this.element, "ai-answer-entry")?.inspectPlan()
    }
  }
}
