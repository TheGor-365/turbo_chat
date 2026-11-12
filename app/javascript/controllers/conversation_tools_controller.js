import { Controller } from "@hotwired/stimulus"

// A click-only, keyboard-accessible disclosure for secondary conversation
// actions. The Rails ACL/route/HTTP verb remains the only authority.
// It does not fetch anything on hover or pre-run privileged actions.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.expanded = false
    this.render()
  }

  toggle(event) {
    event.preventDefault()
    this.expanded = !this.expanded
    this.render()
  }

  close() {
    this.expanded = false
    this.render()
  }

  outside(event) {
    if (this.expanded && !this.element.contains(event.target)) this.close()
  }

  escape(event) {
    if (!this.expanded) return
    event.preventDefault()
    event.stopPropagation()
    this.close()
    this.triggerTarget.focus()
  }

  render() {
    this.panelTarget.hidden = !this.expanded
    this.triggerTarget.setAttribute("aria-expanded", String(this.expanded))
  }
}
