import { Controller } from "@hotwired/stimulus"

// One native membership <details> is the canonical roster state owner.
// On narrow transformed chat layouts fixed-position children can be
// positioned relative to the transformed ancestor, outside the viewport.
// The native Popover API promotes the SAME menu to the top layer on mobile;
// it does not clone membership, invite forms, ACL checks or click handlers.
export default class extends Controller {
  static values = { membershipUrl: String, roomsUrl: String }

  connect() {
    this.stopped = false
    this.refreshVersion = 0
    this.pendingMarkup = null
    this.onViewportChange = () => this.syncPopover()
    this.onMembershipChanged = () => this.scheduleMembershipRefresh(150)
    this.onFocus = () => this.scheduleMembershipRefresh(0)
    this.onVisibility = () => {
      if (document.visibilityState === "visible") this.scheduleMembershipRefresh(0)
    }
    window.addEventListener("resize", this.onViewportChange)
    window.addEventListener("focus", this.onFocus)
    document.addEventListener("visibilitychange", this.onVisibility)
    document.addEventListener("room-membership:changed", this.onMembershipChanged)
    // Only recover by polling if the room inbox socket is down.
    this.fallbackTimer = window.setInterval(() => {
      const inbox = document.querySelector("[data-controller~='inbox-sync']")
      if (inbox?.dataset.inboxSyncConnected !== "true")
        this.scheduleMembershipRefresh(0)
    }, 15000)
    this.syncPopover()
  }

  disconnect() {
    this.stopped = true
    ++this.refreshVersion
    window.clearInterval(this.fallbackTimer)
    window.clearTimeout(this.refreshTimer)
    this.request?.abort()
    window.removeEventListener("resize", this.onViewportChange)
    window.removeEventListener("focus", this.onFocus)
    document.removeEventListener("visibilitychange", this.onVisibility)
    document.removeEventListener("room-membership:changed", this.onMembershipChanged)
    this.closeTopLayer()
  }

  scheduleMembershipRefresh(delay = 150) {
    if (this.stopped || !this.hasMembershipUrlValue ||
        document.visibilityState !== "visible") return
    window.clearTimeout(this.refreshTimer)
    this.refreshTimer = window.setTimeout(() => this.refreshMembership(), delay)
  }

  async refreshMembership() {
    if (this.stopped || !this.hasMembershipUrlValue) return
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    const version = ++this.refreshVersion
    try {
      const response = await fetch(this.membershipUrlValue, {
        credentials: "same-origin", cache: "no-store", signal: request.signal,
        headers: { Accept: "application/json" }
      })
      if (request.signal.aborted || this.stopped || version !== this.refreshVersion) return
      if ([403, 404].includes(response.status)) {
        // A former member cannot continue using a stale private-room view.
        if (this.hasRoomsUrlValue) window.location.assign(this.roomsUrlValue)
        return
      }
      if (!response.ok) return
      const data = await response.json()
      if (this.stopped || request.signal.aborted || version !== this.refreshVersion ||
          typeof data?.html !== "string" || data.html.length > 100000) return
      this.reconcileMembership(data.html)
    } catch (error) {
      if (error.name !== "AbortError") this.element.dataset.membershipStale = "true"
    } finally {
      if (this.request === request) this.request = null
    }
  }

  reconcileMembership(markup) {
    const parsed = new DOMParser().parseFromString(markup, "text/html")
    const fresh = parsed.querySelector("#private-group-details")
    if (!fresh || fresh.dataset.controller !== "private-group-details") return
    delete this.element.dataset.membershipStale
    const summary = this.element.querySelector(":scope > summary")
    const nextSummary = fresh.querySelector(":scope > summary")
    if (summary && nextSummary) {
      for (const name of ["aria-label", "title"])
        summary.setAttribute(name, nextSummary.getAttribute(name) || "")
      const currentCount = summary.querySelector(".sd-private-group-details__count")
      const nextCount = nextSummary.querySelector(".sd-private-group-details__count")
      if (currentCount && nextCount) currentCount.textContent = nextCount.textContent
    }
    // Do not tear down an open popover while an invite/removal control has focus.
    if (this.element.open && this.element.contains(document.activeElement)) {
      const count = fresh.querySelector(".sd-private-group-details__meta > div:last-child dd")
      const visible = this.element.querySelector(".sd-private-group-details__meta > div:last-child dd")
      if (count && visible) visible.textContent = count.textContent
      this.pendingMarkup = markup
      return
    }
    const wasOpen = this.element.open
    this.closeTopLayer()
    this.element.innerHTML = fresh.innerHTML
    this.element.open = wasOpen
    this.pendingMarkup = null
    this.syncPopover()
  }

  get menu() {
    return this.element.querySelector(":scope > .sd-private-group-details__popover")
  }

  get supportsTopLayer() {
    return typeof this.menu?.showPopover === "function" &&
      typeof this.menu?.hidePopover === "function"
  }

  closeTopLayer() {
    const menu = this.menu
    if (!menu || !this.supportsTopLayer) return
    if (menu.matches(":popover-open")) menu.hidePopover()
    menu.removeAttribute("popover")
    menu.style.removeProperty("--sd-group-roster-top")
  }

  syncPopover() {
    if (!this.element.open && this.pendingMarkup) {
      const markup = this.pendingMarkup
      this.pendingMarkup = null
      this.reconcileMembership(markup)
    }
    const menu = this.menu
    if (!menu || !this.supportsTopLayer) return
    if (!window.matchMedia("(max-width: 620px)").matches) {
      this.closeTopLayer()
      return
    }

    // Only mobile uses the top layer; desktop retains the original compact
    // anchored dropdown and native <details> semantics.
    menu.setAttribute("popover", "manual")
    if (!this.element.open) {
      if (menu.matches(":popover-open")) menu.hidePopover()
      return
    }
    const trigger = this.element.getBoundingClientRect()
    menu.style.setProperty("--sd-group-roster-top",
      `${Math.max(8, Math.min(trigger.bottom + 6, window.innerHeight - 120))}px`)
    if (!menu.matches(":popover-open")) menu.showPopover()
  }

  outside(event) {
    if (this.element.open && !this.element.contains(event.target)) this.element.open = false
  }

  escape(event) {
    if (event.key !== "Escape" || !this.element.open) return
    event.preventDefault()
    this.element.open = false
    this.element.querySelector("summary")?.focus({preventScroll: true})
  }
}
