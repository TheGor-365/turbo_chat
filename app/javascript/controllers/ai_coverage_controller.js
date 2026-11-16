import { Controller } from "@hotwired/stimulus"

// FCC-2c.1: metadata coverage; individual message bodies only on explicit click
// after server-side access/consent/DLP revalidation. Never calls an AI model.
export default class extends Controller {
  static targets = ["status", "results", "metrics", "exclusions", "sources", "next", "refresh", "page"]
  static values = { url: String, copy: Object }

  connect() {
    this.requestEpoch = 0
    this.abortController = null
    this.currentPage = 0
    this.receipt = null
    this.visibleSourceIds = new Set()
    this.previewEpoch = 0
    this.previewAbort = null
    this.previewDialog = null
    this.clear()
  }

  disconnect() {
    this.invalidateRequest()
    this.clear()
  }

  toggle(event) {
    if (!event.currentTarget.open) {
      this.invalidateRequest()
      this.clear()
    }
  }

  invalidateRequest() {
    this.requestEpoch += 1
    this.abortController?.abort()
    this.abortController = null
  }

  clear() {
    this.closePreview()
    this.visibleSourceIds = new Set()
    this.currentPage = 0
    this.receipt = null
    this.resultsTarget.hidden = true
    this.metricsTarget.replaceChildren()
    this.exclusionsTarget.replaceChildren()
    this.sourcesTarget.replaceChildren()
    this.nextTarget.hidden = true
    this.pageTarget.textContent = ""
    this.statusTarget.textContent = ""
    this.refreshTarget.disabled = false
    this.nextTarget.disabled = false
  }

  refresh() {
    this.invalidateRequest()
    this.clear()
    this.fetchPage(1)
  }

  next() {
    if (this.currentPage < 1 || !this.receipt || this.nextTarget.hidden ||
        this.nextTarget.disabled) return
    this.fetchPage(this.currentPage + 1)
  }

  async fetchPage(page) {
    const epoch = ++this.requestEpoch
    const abort = new AbortController()
    this.abortController?.abort()
    this.abortController = abort
    this.refreshTarget.disabled = true
    this.nextTarget.disabled = true
    this.statusTarget.textContent = this.copyValue.loading

    try {
      const url = new URL(this.urlValue, window.location.origin)
      if (url.origin !== window.location.origin) throw new Error("Invalid endpoint origin")
      url.searchParams.set("page", String(page))
      if (page > 1) url.searchParams.set("token", this.receipt)
      const response = await fetch(url.toString(), {
        method: "GET", credentials: "same-origin", cache: "no-store",
        headers: { Accept: "application/json" }, signal: abort.signal
      })
      if (!response.ok) {
        throw new Error(response.status === 429 ? "rate_limit" : "unavailable")
      }
      const data = await response.json()
      if (epoch !== this.requestEpoch) return
      this.validate(data, page)
      this.render(data, page)
    } catch (error) {
      if (epoch !== this.requestEpoch || error.name === "AbortError") return
      this.clear()
      this.statusTarget.textContent = error.message === "rate_limit"
        ? this.copyValue.rate_limit : this.copyValue.unavailable
    } finally {
      if (epoch === this.requestEpoch) {
        this.refreshTarget.disabled = false
        this.nextTarget.disabled = false
        this.abortController = null
      }
    }
  }

  validate(data, requestedPage) {
    const count = (value) => Number.isSafeInteger(value) && value >= 0 && value <= 10000
    const coverage = data?.coverage, pagination = data?.pagination
    const reasons = coverage?.exclusions
    const keys = ["former_author", "non_text", "sensitive", "invalid"]
    if (data?.version !== 1 || data?.snapshot_version !== 2 ||
        data?.state !== "metadata_only_not_sent_to_ai" ||
        !coverage || !pagination || !reasons ||
        !count(coverage.total_messages) || !count(coverage.current_author_messages) ||
        !count(coverage.eligible_safe_text) || !count(coverage.excluded_messages) ||
        !keys.every(key => count(reasons[key])) ||
        keys.reduce((sum, key) => sum + reasons[key], 0) !== coverage.excluded_messages ||
        coverage.eligible_safe_text + coverage.excluded_messages !== coverage.total_messages ||
        coverage.current_author_messages + reasons.former_author !== coverage.total_messages ||
        !Array.isArray(data.sources) || data.sources.length > 25 ||
        !Number.isSafeInteger(pagination.page_size) || pagination.page_size !== 25 ||
        pagination.page !== requestedPage ||
        !Number.isSafeInteger(pagination.total_pages) ||
        pagination.total_pages < 1 || pagination.total_pages > 400 ||
        pagination.total_eligible_sources !== coverage.eligible_safe_text ||
        typeof pagination.has_more !== "boolean" ||
        pagination.has_more !== (requestedPage < pagination.total_pages) ||
        pagination.total_pages !== Math.max(1, Math.ceil(coverage.eligible_safe_text / 25)) ||
        data.sources.length !== Math.min(25, Math.max(0,
          coverage.eligible_safe_text - (requestedPage - 1) * 25)) ||
        !data.sources.every(item =>
          Number.isSafeInteger(item.id) && item.id > 0 &&
          typeof item.updated_at === "string" && item.updated_at.length < 64) ||
        (pagination.has_more &&
          (typeof data.next_page_token !== "string" ||
          data.next_page_token.length < 1 || data.next_page_token.length > 4096)) ||
        (!pagination.has_more && data.next_page_token !== null)) {
      throw new Error("Invalid coverage response")
    }
  }


  closePreview() {
    this.previewEpoch = (this.previewEpoch || 0) + 1
    this.previewAbort?.abort()
    this.previewAbort = null
    const dialog = this.previewDialog
    this.previewDialog = null
    if (dialog) {
      if (dialog.open) dialog.close()
      dialog.remove()
    }
    const trigger = this.previewTrigger
    this.previewTrigger = null
    if (trigger?.isConnected) trigger.focus({ preventScroll: true })
  }

  async openMessage(event) {
    const id = Number(event.currentTarget.dataset.messageId)
    if (!Number.isSafeInteger(id) || id < 1 || !this.visibleSourceIds?.has(id) ||
        this.resultsTarget.hidden) return
    this.closePreview()
    const trigger = event.currentTarget
    this.previewTrigger = trigger
    const copy = this.copyValue

    // Native modal provides a focus trap and Escape-to-close. Build inert
    // text nodes only; never render source Markdown/HTML as markup.
    const dialog = document.createElement("dialog")
    dialog.className = "sd-ai-coverage-modal"
    dialog.setAttribute("aria-label", copy.preview_title.replace("%{id}", String(id)))
    const panel = document.createElement("div")
    panel.className = "sd-ai-coverage-modal__panel"
    const heading = document.createElement("div")
    heading.className = "sd-ai-coverage-modal__heading"
    const title = document.createElement("h4")
    title.textContent = copy.preview_title.replace("%{id}", String(id))
    const close = document.createElement("button")
    close.type = "button"
    close.className = "sd-ai-coverage-modal__close"
    close.textContent = "×"
    close.setAttribute("aria-label", copy.close_preview)
    close.addEventListener("click", () => dialog.close())
    heading.append(title, close)
    const status = document.createElement("p")
    status.className = "sd-ai-coverage-modal__status"
    status.setAttribute("role", "status")
    status.textContent = copy.loading_message
    const content = document.createElement("pre")
    content.className = "sd-ai-coverage-modal__message"
    content.hidden = true
    const note = document.createElement("p")
    note.className = "sd-ai-coverage-modal__note"
    note.textContent = copy.review_only
    panel.append(heading, status, content, note)
    dialog.append(panel)
    dialog.addEventListener("close", () => {
      if (this.previewDialog === dialog) this.closePreview()
    })
    dialog.addEventListener("click", e => {
      if (e.target === dialog) dialog.close()
    })
    document.body.append(dialog)
    this.previewDialog = dialog
    dialog.showModal()
    close.focus({ preventScroll: true })

    const epoch = ++this.previewEpoch
    const abort = new AbortController()
    this.previewAbort = abort
    try {
      const base = new URL(this.urlValue, window.location.origin)
      if (base.origin !== window.location.origin) throw new Error("Invalid endpoint origin")
      const url = new URL(base.pathname.replace(/\/$/, "") + "/messages/" + id, base.origin)
      const response = await fetch(url.toString(), {
        method: "GET", credentials: "same-origin", cache: "no-store",
        headers: { Accept: "application/json" }, signal: abort.signal
      })
      if (!response.ok) {
        throw new Error(response.status === 429 ? "rate_limit" : "unavailable")
      }
      const data = await response.json()
      if (epoch !== this.previewEpoch || this.previewDialog !== dialog) return
      if (data?.version !== 1 || data?.state !== "local_review_only" ||
          data?.message_id !== id || typeof data?.text !== "string" ||
          data.text.length < 1 || data.text.length > 5000) {
        throw new Error("Invalid message preview")
      }
      content.textContent = data.text
      content.hidden = false
      status.textContent = ""
    } catch (error) {
      if (epoch !== this.previewEpoch || this.previewDialog !== dialog ||
          error.name === "AbortError") return
      content.textContent = ""
      content.hidden = true
      status.textContent = error.message === "rate_limit"
        ? copy.rate_limit : copy.message_unavailable
    } finally {
      if (epoch === this.previewEpoch) this.previewAbort = null
    }
  }

  render(data, page) {
    const coverage = data.coverage
    const copy = this.copyValue
    if (page === 1) {
      const values = [
        [copy.total, coverage.total_messages],
        [copy.eligible, coverage.eligible_safe_text],
        [copy.excluded, coverage.excluded_messages]
      ]
      const metrics = document.createDocumentFragment()
      for (const [label, value] of values) {
        const item = document.createElement("div")
        const amount = document.createElement("strong")
        amount.textContent = String(value)
        const caption = document.createElement("span")
        caption.textContent = label
        item.append(amount, caption)
        metrics.append(item)
      }
      this.metricsTarget.replaceChildren(metrics)

      const reasons = document.createDocumentFragment()
      for (const key of ["former_author", "non_text", "sensitive", "invalid"]) {
        const li = document.createElement("li")
        const label = document.createElement("span")
        label.textContent = copy[key]
        const amount = document.createElement("strong")
        amount.textContent = String(coverage.exclusions[key])
        li.append(label, amount)
        reasons.append(li)
      }
      this.exclusionsTarget.replaceChildren(reasons)
      this.sourcesTarget.replaceChildren()
    }

    const sources = document.createDocumentFragment()
    for (const source of data.sources) {
      const li = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "sd-ai-coverage__message-button"
      button.dataset.messageId = String(source.id)
      button.textContent = copy.message.replace("%{id}", String(source.id))
      button.setAttribute("aria-label", copy.open_message.replace("%{id}", String(source.id)))
      button.addEventListener("click", event => this.openMessage(event))
      this.visibleSourceIds.add(source.id)
      li.append(button)
      sources.append(li)
    }
    this.sourcesTarget.append(sources)
    this.resultsTarget.hidden = false
    this.currentPage = page
    this.receipt = data.next_page_token || null
    this.nextTarget.hidden = !data.pagination.has_more
    this.pageTarget.textContent = copy.page.replace("%{page}", String(page))
      .replace("%{total}", String(data.pagination.total_pages))
    this.statusTarget.textContent = copy.ready
  }
}
