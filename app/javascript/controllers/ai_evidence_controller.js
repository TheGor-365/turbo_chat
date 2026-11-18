import { Controller } from "@hotwired/stimulus"

// FCC-2e.2a: lexical evidence, chronological context and explicit personal stances.
// Does not select provider sources, send a message, persist a summary or spend.
export default class extends Controller {
  static targets = ["query", "submit", "status", "results", "summary", "items", "conflicts", "disclosure", "timeline", "relations", "reviewCount"]
  static values = { url: String, reviewUrl: String, copy: Object }

  connect() {
    this.epoch = 0
    this.abort = null
    this.reviewRequest = null
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
    this.reviewRequest?.abort()
    this.reviewRequest = null
  }

  clear() {
    this.resultsTarget.hidden = true
    this.statusTarget.textContent = ""
    this.summaryTarget.textContent = ""
    this.reviewCountTarget.textContent = ""
    this.reviewableIds = new Set()
    this.reviewedIds = new Set()
    this.reviewRows = new Map()
    this.itemsTarget.replaceChildren()
    this.timelineTarget.replaceChildren()
    this.relationsTarget.replaceChildren()
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
          typeof row.source_version === "string" &&
          /^[0-9a-f]{64}$/.test(row.source_version) &&
          ["none", "acknowledged", "disputed"].includes(row.personal_stance) &&
          statuses.has(row.classification?.state) &&
          row.classification.confidence === "rule_only_unverified") ||
        !data.possible_conflicts.every(item =>
          item?.state === "possible_conflict_requires_review" &&
          Array.isArray(item.source_ids) && item.source_ids.length === 2 &&
          item.source_ids.every(id => data.results.some(row => row.id === id))) ||
        !this.validChronology(data.chronology, data.results, statuses)) {
      throw new Error("Invalid evidence response")
    }
  }

  validChronology(chronology, results, statuses) {
    if (!chronology || chronology.version !== 1 ||
        chronology.state !== "unverified_candidate_chronology" ||
        chronology.scope !== "selected_ranked_matches_only" ||
        chronology.order_by !== "message_created_at_utc_then_id" ||
        chronology.approval_state !== "not_determined" ||
        chronology.requires_human_review !== true ||
        !Array.isArray(chronology.events) || chronology.events.length !== results.length ||
        !Array.isArray(chronology.links) || chronology.links.length > 8) return false

    const ids = new Set(results.map(item => item.id))
    const seen = new Set()
    const events = chronology.events
    for (const item of events) {
      if (!ids.has(item?.id) || seen.has(item.id) ||
          typeof item.created_at !== "string" ||
          !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(item.created_at) ||
          !(item.speaker === "you" || /^participant_[1-9]\d?$/.test(item.speaker)) ||
          !statuses.has(item.cue)) return false
      seen.add(item.id)
    }
    for (let i = 1; i < events.length; i += 1) {
      const previous = events[i - 1], current = events[i]
      if (current.created_at < previous.created_at ||
          (current.created_at === previous.created_at && current.id <= previous.id)) return false
    }
    const relations = new Set(["possible_response_to_proposal", "possible_reversal",
      "possible_reconfirmation"])
    return chronology.links.every(edge =>
      edge && Number.isSafeInteger(edge.earlier_id) &&
      Number.isSafeInteger(edge.later_id) &&
      events.findIndex(item => item.id === edge.earlier_id) >= 0 &&
      events.findIndex(item => item.id === edge.earlier_id) <
        events.findIndex(item => item.id === edge.later_id) &&
      relations.has(edge.relation) &&
      edge.certainty === "lexical_candidate_only")
  }

  toggleReviewed(event) {
    const id = Number(event.currentTarget.dataset.messageId)
    if (!this.reviewableIds?.has(id) || this.resultsTarget.hidden) return
    if (this.reviewedIds.has(id)) this.reviewedIds.delete(id)
    else this.reviewedIds.add(id)
    const reviewed = this.reviewedIds.has(id)
    event.currentTarget.setAttribute("aria-pressed", reviewed ? "true" : "false")
    event.currentTarget.textContent = reviewed ?
      this.copyValue.reviewed : this.copyValue.mark_reviewed
    this.renderReviewCount()
  }

  renderReviewCount() {
    this.reviewCountTarget.textContent = this.copyValue.review_count
      .replace("%{done}", String(this.reviewedIds.size))
      .replace("%{total}", String(this.reviewableIds.size))
  }

  personalStanceCard(result, li) {
    const copy = this.copyValue
    const panel = document.createElement("section")
    panel.className = "sd-ai-evidence__personal-stance"
    const state = document.createElement("p")
    state.className = "sd-ai-evidence__stance-status"
    state.setAttribute("role", "status")
    const actions = document.createElement("div")
    actions.className = "sd-ai-evidence__stance-actions"
    for (const [stance, label] of [
      ["acknowledged", "stance_acknowledge"],
      ["disputed", "stance_dispute"],
      ["withdrawn", "stance_withdraw"]
    ]) {
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.messageId = String(result.id)
      button.dataset.stance = stance
      button.dataset.action = "click->ai-evidence#saveStance"
      button.textContent = copy[label]
      actions.append(button)
    }
    const feedback = document.createElement("p")
    feedback.className = "sd-ai-evidence__stance-feedback"
    feedback.setAttribute("role", "status")
    panel.append(state, actions, feedback)
    li.append(panel)
    this.reviewRows.set(result.id, { result, li, state, actions, feedback })
    this.refreshStance(result.id)
  }

  refreshStance(id) {
    const row = this.reviewRows?.get(id)
    if (!row) return
    const { result, state, actions } = row
    state.textContent = this.copyValue.my_stance.replace(
      "%{state}", this.copyValue["stance_" + result.personal_stance])
    for (const button of actions.querySelectorAll("button")) {
      button.disabled = Boolean(this.reviewRequest) ||
        (button.dataset.stance === "withdrawn" ?
          result.personal_stance === "none" :
          button.dataset.stance === result.personal_stance)
    }
  }

  async saveStance(event) {
    event.preventDefault()
    event.stopPropagation()
    const button = event.currentTarget
    const id = Number(button.dataset.messageId)
    const stance = button.dataset.stance
    const row = this.reviewRows?.get(id)
    if (!row || this.resultsTarget.hidden || this.reviewRequest ||
        !["acknowledged", "disputed", "withdrawn"].includes(stance)) return

    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (!csrf || !window.crypto?.randomUUID) {
      row.feedback.textContent = this.copyValue.stance_unavailable
      return
    }
    const epoch = this.epoch
    const request = new AbortController()
    this.reviewRequest = request
    row.feedback.textContent = this.copyValue.stance_saving
    this.refreshStance(id)
    const copy = this.copyValue
    try {
      const url = new URL(this.reviewUrlValue, window.location.origin)
      if (url.origin !== window.location.origin) throw new Error("Invalid origin")
      const response = await fetch(url.toString(), {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { Accept: "application/json", "Content-Type": "application/json",
          "X-CSRF-Token": csrf },
        body: JSON.stringify({ review: { message_id: String(id),
          source_version: row.result.source_version, stance,
          request_key: window.crypto.randomUUID() } }), signal: request.signal
      })
      if (!response.ok) throw new Error("Review unavailable")
      const payload = await response.json()
      if (epoch !== this.epoch || this.reviewRows?.get(id) !== row) return
      if (payload.version !== 1 ||
          payload.state !== "personal_stance_not_room_consensus" ||
          payload.room_approval_state !== "not_determined" ||
          payload.message_id !== id ||
          payload.source_version !== row.result.source_version ||
          !["none", "acknowledged", "disputed"].includes(payload.personal_stance)) {
        throw new Error("Invalid response")
      }
      row.result.personal_stance = payload.personal_stance
      row.feedback.textContent = copy.stance_saved
    } catch (error) {
      if (epoch !== this.epoch || error.name === "AbortError") return
      row.feedback.textContent = copy.stance_unavailable
    } finally {
      if (this.reviewRequest === request) this.reviewRequest = null
      if (epoch === this.epoch) {
        for (const entry of this.reviewRows.values()) this.refreshStance(entry.result.id)
      }
    }
  }

  render(data) {
    const copy = this.copyValue
    const tr = data.retrieval
    this.summaryTarget.textContent = copy.summary
      .replace("%{count}", String(data.results.length))
      .replace("%{scanned}", String(tr.scanned_matching_rows))
    if (tr.truncated_matching_rows) this.summaryTarget.textContent += " " + copy.truncated

    // No durable approval state exists in this slice. A checkmark means only
    // that THIS VIEWER inspected a candidate during this open search.
    this.reviewableIds = new Set(data.results.map(item => item.id))
    this.reviewedIds = new Set()
    this.renderReviewCount()

    const chronologyNodes = document.createDocumentFragment()
    for (const event of data.chronology.events) {
      const li = document.createElement("li")
      li.className = "sd-ai-evidence__timeline-item"
      const button = document.createElement("button")
      button.type = "button"
      button.className = "sd-ai-coverage__message-button"
      button.dataset.messageId = String(event.id)
      button.dataset.action = "click->ai-coverage#openMessage"
      button.textContent = "M" + event.id
      const time = document.createElement("time")
      time.dateTime = event.created_at
      time.textContent = event.created_at.slice(0, 16).replace("T", " ") + " UTC"
      const label = document.createElement("span")
      label.className = "sd-ai-evidence__timeline-cue"
      label.textContent = copy[event.cue]
      const speaker = document.createElement("span")
      speaker.className = "sd-ai-evidence__timeline-speaker"
      speaker.textContent = event.speaker === "you" ?
        copy.speaker_you : copy.speaker_member.replace("%{n}", event.speaker.split("_")[1])
      li.append(button, time, speaker, label)
      chronologyNodes.append(li)
    }
    this.timelineTarget.replaceChildren(chronologyNodes)

    const relationNodes = document.createDocumentFragment()
    for (const edge of data.chronology.links) {
      const li = document.createElement("li")
      li.textContent = copy[edge.relation]
        .replace("%{before}", String(edge.earlier_id))
        .replace("%{after}", String(edge.later_id))
      relationNodes.append(li)
    }
    this.relationsTarget.replaceChildren(relationNodes)

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
      const reviewed = document.createElement("button")
      reviewed.type = "button"
      reviewed.className = "sd-ai-evidence__review-button"
      reviewed.dataset.messageId = String(result.id)
      reviewed.dataset.action = "click->ai-evidence#toggleReviewed"
      reviewed.setAttribute("aria-pressed", "false")
      reviewed.textContent = copy.mark_reviewed
      heading.append(button, tag, reviewed)
      const excerpt = document.createElement("p")
      excerpt.className = "sd-ai-evidence__excerpt"
      excerpt.textContent = result.excerpt // no HTML rendering of untrusted chat text
      li.append(heading, excerpt)
      this.personalStanceCard(result, li)
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
