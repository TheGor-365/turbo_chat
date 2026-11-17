import { Controller } from "@hotwired/stimulus"

// Render the existing authorized Rails review in a native modal. No iframe:
// this app deliberately denies all framing in its CSP. No request on hover,
// no caching of evidence, no localStorage, and no change to any server POST.
const REVIEW_PATH = /^\/rooms\/(\d+)\/ai\/deliverable-review\/?$/
const SAVE_PATH = /^\/rooms\/(\d+)\/ai_deliverables(?:\/(\d+))?\/?$/
const LOCALES = new Set(["en", "ru", "hy", "es"])

export default class extends Controller {
  static targets = ["dialog", "content", "status", "closeButton"]
  static values = { copy: Object }

  connect() {
    this.request = null
    this.opener = null
    this.roomId = null
  }

  reviewUrl(href, forCurrentRoom = false) {
    let url
    try { url = new URL(href, window.location.href) } catch (_) { return null }
    if (url.origin !== window.location.origin) return null
    const match = url.pathname.match(REVIEW_PATH)
    if (!match || (forCurrentRoom && match[1] !== this.roomId)) return null
    return url
  }

  open(event) {
    if (event.defaultPrevented || (event.button !== undefined && event.button !== 0) ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
        !this.hasDialogTarget || !this.hasContentTarget ||
        typeof this.dialogTarget.showModal !== "function") return

    const url = this.reviewUrl(event.currentTarget?.href)
    if (!url) return
    event.preventDefault() // Without JS, the original link remains a real GET.
    if (this.dialogTarget.open) return

    this.roomId = url.pathname.match(REVIEW_PATH)[1]
    const chosenLocale = this.element.dataset.uiLocale
    if (!url.searchParams.has("ui_locale") && LOCALES.has(chosenLocale)) {
      url.searchParams.set("ui_locale", chosenLocale)
    }
    this.opener = event.currentTarget
    this.dialogTarget.showModal()
    this.closeButtonTarget.focus()
    this.load(url)
  }

  async load(url, options = {}) {
    this.request?.abort()
    const controller = new AbortController()
    this.request = controller
    this.showStatus(this.label("modal_loading", "Loading document…"))
    try {
      const response = await fetch(url.toString(), {
        method: options.method || "GET",
        body: options.body,
        credentials: "same-origin",
        cache: "no-store",
        redirect: "follow",
        headers: { Accept: "text/html" },
        signal: controller.signal
      })
      if (this.request !== controller) return
      if (!response.ok) {
        // Revoked access: never leave stale confidential evidence visible.
        if ([401, 403, 404].includes(response.status)) this.contentTarget.replaceChildren()
        this.showStatus(this.label(
          [401, 403, 404].includes(response.status) ? "modal_forbidden" : "modal_invalid",
          "Review unavailable."
        ))
        return
      }
      const resolved = new URL(response.url)
      if (resolved.origin !== window.location.origin ||
          !response.headers.get("Content-Type")?.includes("text/html")) {
        this.showStatus(this.label("modal_unavailable", "Unable to open document."))
        return
      }
      const html = new DOMParser().parseFromString(await response.text(), "text/html")
      if (this.request !== controller) return
      const review = html.querySelector("main #h4-manual-review")
      if (review && this.reviewUrl(resolved.toString(), true)) {
        this.mountReview(review, url.hash)
        return
      }
      // H5 explicitly saves and redirects to its authorized saved-document page.
      // Never report success from a redirect alone: require its actual view.
      const saved = resolved.pathname.match(SAVE_PATH)
      if (options.method === "POST" && response.redirected &&
          saved && saved[1] === this.roomId && saved[2] &&
          html.querySelector("main #h5-saved-document")) {
        this.mountSaved(resolved)
        return
      }
      this.showStatus(this.label("modal_unavailable", "Unable to open document."))
    } catch (error) {
      if (error?.name !== "AbortError" && this.request === controller) {
        this.showStatus(this.label("modal_unavailable", "Unable to open document."))
      }
    } finally {
      if (this.request === controller) this.request = null
    }
  }

  mountReview(review, hash) {
    // Parse only server-rendered, escaped markup from our authorized endpoint.
    // Do not import the response's scripts, layout, styles or other resources.
    this.contentTarget.replaceChildren(document.importNode(review, true))
    const back = this.contentTarget.querySelector(".sd-activity-back")
    if (back) back.dataset.reviewSheetBack = "true"
    // Source evidence must never replace the editor or navigate inside a sheet.
    this.contentTarget.querySelectorAll(".sd-h4-sources a, .sd-h4-demo-link")
      .forEach(link => {
        link.target = "_blank"
        link.rel = "noopener noreferrer"
      })
    this.statusTarget.hidden = true
    this.statusTarget.textContent = ""
    this.contentTarget.scrollTop = 0
    if (hash && /^#[a-z0-9-]+$/i.test(hash)) {
      this.contentTarget.querySelector(hash)?.scrollIntoView({ block: "start" })
    }
  }

  mountSaved(url) {
    this.contentTarget.replaceChildren()
    this.showStatus(this.label("modal_saved", "Private draft saved. Not sent."))
    const link = document.createElement("a")
    link.href = url.href
    link.target = "_blank"
    link.rel = "noopener noreferrer"
    link.className = "sd-review-sheet__saved-link"
    link.textContent = this.label("modal_open_saved", "Open saved document")
    this.contentTarget.append(link)
    link.focus()
  }

  submit(event) {
    if (!this.dialogTarget.open || !this.contentTarget.contains(event.target)) return
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    // Never allow a provider-backed or external form to be proxied.
    const submitter = event.submitter
    let url
    try { url = new URL(submitter?.formAction || form.action, window.location.href) } catch (_) {
      event.preventDefault()
      this.showStatus(this.label("modal_unavailable", "Unable to submit."))
      return
    }
    const path = url.pathname
    const review = path.match(REVIEW_PATH)
    const save = path.match(SAVE_PATH)
    event.preventDefault()
    if (url.origin !== window.location.origin ||
        (!review && !(save && !save[2])) ||
        (review && review[1] !== this.roomId) ||
        (save && save[1] !== this.roomId) ||
        (submitter?.formMethod || form.method).toLowerCase() !== "post") {
      this.showStatus(this.label("modal_unavailable", "Unable to submit."))
      return
    }
    const chosenLocale = this.element.dataset.uiLocale
    if (!url.searchParams.has("ui_locale") && LOCALES.has(chosenLocale)) {
      url.searchParams.set("ui_locale", chosenLocale)
    }
    const payload = new FormData(form, submitter || undefined)
    this.load(url, { method: "POST", body: payload })
  }

  follow(event) {
    const anchor = event.target.closest("a[data-review-sheet-back]")
    if (!anchor || !this.contentTarget.contains(anchor)) return
    event.preventDefault()
    this.close()
  }

  label(name, fallback) {
    const key = name.replace(/^modal_/, "")
    return this.copyValue?.[key] || fallback
  }

  showStatus(message) {
    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  close(event) {
    event?.preventDefault()
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  closed() {
    this.request?.abort()
    this.request = null
    this.contentTarget.replaceChildren()
    this.statusTarget.textContent = ""
    this.statusTarget.hidden = true
    const focus = this.opener?.getClientRects().length
      ? this.opener
      : this.opener?.closest(".sd-conversation-tools")?.querySelector(".sd-conversation-tools__trigger")
    if (focus?.isConnected) focus.focus()
    this.opener = null
    this.roomId = null
  }

  disconnect() {
    this.request?.abort()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }
}
