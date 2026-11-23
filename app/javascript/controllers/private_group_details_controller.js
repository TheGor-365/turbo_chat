import { Controller } from "@hotwired/stimulus"

// One native membership <details> is the canonical roster state owner.
// On narrow transformed chat layouts fixed-position children can be
// positioned relative to the transformed ancestor, outside the viewport.
// The native Popover API promotes the SAME menu to the top layer on mobile;
// it does not clone membership, invite forms, ACL checks or click handlers.
export default class extends Controller {
  connect() {
    this.onViewportChange = () => this.syncPopover()
    window.addEventListener("resize", this.onViewportChange)
    this.syncPopover()
  }

  disconnect() {
    window.removeEventListener("resize", this.onViewportChange)
    this.closeTopLayer()
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
