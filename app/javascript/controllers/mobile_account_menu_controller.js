import { Controller } from "@hotwired/stimulus"

// One theme#cycle controller target, moved responsively rather than cloned.
// Theme preference stays client-local in ThemeController.
export default class extends Controller {
  connect() {
    this.themeToggle = this.element.querySelector(
      ".sd-nav__actions > button[data-theme-target='toggle']")
    this.slot = this.element.querySelector(".sd-nav__account-theme-slot")
    if (!this.themeToggle || !this.slot) return
    this.placeholder = document.createComment("theme toggle desktop location")
    this.themeToggle.before(this.placeholder)
    this.mobile = window.matchMedia("(max-width:620px)")
    this.onChange = () => this.relocate()
    this.mobile.addEventListener("change", this.onChange)
    this.relocate()
  }
  relocate() {
    if (!this.themeToggle || !this.placeholder?.isConnected) return
    if (this.mobile.matches) {
      if (this.themeToggle.parentElement !== this.slot) this.slot.append(this.themeToggle)
    } else if (this.themeToggle.parentElement !== this.placeholder.parentElement) {
      this.placeholder.after(this.themeToggle)
    }
  }
  disconnect() {
    this.mobile?.removeEventListener("change", this.onChange)
    if (this.placeholder?.isConnected && this.themeToggle) {
      this.placeholder.after(this.themeToggle)
      this.placeholder.remove()
    }
  }
}
