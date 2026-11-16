import { Controller } from "@hotwired/stimulus"

// FCC-2d: explicit, non-AI lexical search with tentative speech-act markers.
// Does not select provider sources, send a message, persist a summary or spend.
export default class extends Controller {
  static targets = ["query", "submit", "status", "results", "summary", "items", "conflicts", "disclosure"]
  static values = { url: String, copy: Object }

  connect() {
    this.epoch = 0
    this.abort = null
    this.clear()
  }

  disconnect() {
    this.cancel()
    this.clear()
  }

  toggle(event) {
    if (event.target === this.element && !this.element.open) {
      this.cancel()
      this.clear()
    }
  }

  toggleSearch(event) {
    if (!event.target.open) {
      this.cancel()
      this.clear()
    }
  }

  cancel() {
    this.epoch += 1
    this.abort?.abort()
    this.abort = null
  }

  clear() {
    this.resultsTarget.hidden = true
    this.statusTarget.textContent = ""
    this.summaryTarget.textContent = ""
    this.itemsTarget.replaceChildren()
    this.conflictsTarget.replaceChildren()
    this.submitTarget.disabled = false
    this.dispatch("results", { detail: { ids: [] } })
  }

  async search(event) {
    event.preventDefault()
    event.stopPropagation()
    this.cancel()
    this.clear()
    const copy = this.copyValue
    const query = this.queryTarget.value.trim()
    if (query.length < 3 || query.length > 120) {
      this.statusTarget.textContent = copy.invalid_query
      return
    }

    const epoch = ++this.epoch
    const abort = new AbortController()
    this.abort = abort
    this.submitTarget.disabled = true
    this.statusTarget.textContent = copy.loading
    try {
      const url = new URL(this.urlValue, window.location.origin)
      if (url.origin !== window.location.origin) throw new Error("Invalid origin")
      const csrf = document.querySelector("meta[name='csrf-token']")?.content
      if (!csrf) throw new Error("CSRF token unavailable")
      const response = await fetch(url.toString(), {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ evidence_query: query }), signal: abort.signal
      })
      if (!response.ok) throw new Error(response.status === 429 ? "rate_limit" : "unavailable")
      const data = await response.json()
      if (epoch !== this.epoch) return
      this.validate(data)
      this.render(data)
    } catch (error) {
      if (epoch !== this.epoch || error.name === "AbortError") return
      this.clear()
      this.statusTarget.textContent = error.message === "rate_limit" ?
        copy.rate_limit : copy.unavailable
    } finally {
      if (epoch === this.epoch) {
        this.submitTarget.disabled = false
        this.abort = null
      }
    }
  }

  validate(data) {
    const statuses = new Set(["proposal", "confirmation_candidate",
      "revocation_candidate", "rejection_candidate", "mixed_requires_review", "undetermined"])
    const n = v => Number.isSafeInteger(v) && v >= 0
    if (data?.version !== 1 || data?.state !== "local_lexical_evidence_candidates_not_ai" ||
        data?.review !== "all_candidates_require_human_verification" ||
        data?.retrieval?.method !== "bounded_lexical" ||
        data?.retrieval?.not_an_exhaustive_semantic_search !== true ||
        !n(data?.source_inventory?.total_messages) ||
        !n(data?.source_inventory?.eligible_safe_text) ||
        !n(data?.source_inventory?.excluded_messages) ||
        !n(data?.retrieval?.scanned_matching_rows) ||
        !n(data?.retrieval?.returned) || data.retrieval.returned > 12 ||
        !Array.isArray(data.results) || data.results.length !== data.retrieval.returned ||
        !Array.isArray(data.possible_conflicts) || data.possible_conflicts.length > 8 ||
        typeof data.retrieval.truncated_matching_rows !== "boolean" ||
        !data.results.every(row => n(row.id) && row.id > 0 &&
          typeof row.updated_at === "string" &&
          typeof row.excerpt === "string" && row.excerpt.length <= 242 &&
          n(row.score) && row.score > 0 &&
          statuses.has(row.classification?.state) &&
          row.classification.confidence === "rule_only_unverified") ||
        !data.possible_conflicts.every(item =>
          item?.state === "possible_conflict_requires_review" &&
          Array.isArray(item.source_ids) && item.source_ids.length === 2 &&
          item.source_ids.every(id => data.results.some(row => row.id === id)))) {
      throw new Error("Invalid evidence response")
    }
  }

  render(data) {
    const copy = this.copyValue
    const tr = data.retrieval
    this.summaryTarget.textContent = copy.summary
      .replace("%{count}", String(data.results.length))
      .replace("%{scanned}", String(tr.scanned_matching_rows))
    if (tr.truncated_matching_rows) this.summaryTarget.textContent += " " + copy.truncated

    const list = document.createDocumentFragment()
    for (const result of data.results) {
      const li = document.createElement("li")
      li.className = "sd-ai-evidence__item"
      const heading = document.createElement("div")
      heading.className = "sd-ai-evidence__item-heading"
      const button = document.createElement("button")
      button.type = "button"
      button.className = "sd-ai-coverage__message-button"
      button.dataset.messageId = String(result.id)
      button.dataset.action = "click->ai-coverage#openMessage"
      button.textContent = copy.message.replace("%{id}", String(result.id))
      const tag = document.createElement("span")
      tag.className = "sd-ai-evidence__tag"
      tag.textContent = copy[result.classification.state]
      heading.append(button, tag)
      const excerpt = document.createElement("p")
      excerpt.className = "sd-ai-evidence__excerpt"
      excerpt.textContent = result.excerpt // no HTML rendering of untrusted chat text
      li.append(heading, excerpt)
      list.append(li)
    }
    this.itemsTarget.replaceChildren(list)
    const conflicts = document.createDocumentFragment()
    for (const item of data.possible_conflicts) {
      const li = document.createElement("li")
      li.textContent = copy.potential_conflict
        .replace("%{one}", String(item.source_ids[0]))
        .replace("%{two}", String(item.source_ids[1]))
      conflicts.append(li)
    }
    this.conflictsTarget.replaceChildren(conflicts)
    this.dispatch("results", { detail: { ids: data.results.map(item => item.id) } })
    this.resultsTarget.hidden = false
    this.statusTarget.textContent = data.results.length ? copy.ready : copy.no_matches
  }
}
