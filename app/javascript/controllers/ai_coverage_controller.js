import { Controller } from "@hotwired/stimulus"

// FCC-2c: user-triggered, metadata-only coverage of a consented room.
// Never retrieves raw message bodies or invokes the model/provider endpoints.
export default class extends Controller {
  static targets = ["status", "results", "metrics", "exclusions", "sources", "next", "refresh", "page"]
  static values = { url: String, roomUrl: String, copy: Object }

  connect() {
    this.requestEpoch = 0
    this.abortController = null
    this.currentPage = 0
    this.receipt = null
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
      const link = document.createElement("a")
      const href = new URL(this.roomUrlValue, window.location.origin)
      if (href.origin !== window.location.origin) throw new Error("Invalid room origin")
      href.searchParams.set("focus", String(source.id))
      link.href = href.toString()
      link.target = "_blank"
      link.rel = "noopener noreferrer"
      link.dataset.turbo = "false"
      link.textContent = copy.message.replace("%{id}", String(source.id))
      li.append(link)
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
