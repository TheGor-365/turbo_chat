import { Controller } from "@hotwired/stimulus"

// Reusable, native-backed Activity filters for conversation and date.
// Selecting an option automatically submits the existing authorized GET search.
// JavaScript disabled: the real selects + Search button still work.
export default class extends Controller {
  static targets = ["native", "trigger", "list", "option", "value"]
  static values = { submitOnChange: { type: Boolean, default: true } }

  connect() {
    this.opened = false
    this.typeahead = ""
    this.lastTypedAt = 0
    if (!this.hasNativeTarget || !this.hasTriggerTarget || !this.hasListTarget || !this.hasValueTarget) return

    this.nativeTarget.hidden = true
    this.triggerTarget.hidden = false
    this.listTarget.hidden = true
    this.syncFromNative()
  }

  disconnect() {
    if (this.hasNativeTarget) this.nativeTarget.hidden = false
    if (this.hasTriggerTarget) this.triggerTarget.hidden = true
    if (this.hasListTarget) this.listTarget.hidden = true
  }

  syncFromNative() {
    if (!this.hasNativeTarget || !this.hasOptionTarget) return

    const selected = this.optionTargets.findIndex((option) => option.dataset.value === this.nativeTarget.value)
    this.selectedIndex = selected >= 0 ? selected : 0
    this.activeIndex = this.selectedIndex
    this.valueTarget.textContent = this.optionTargets[this.selectedIndex].querySelector("span")?.textContent.trim() || ""
    this.optionTargets.forEach((option, index) => {
      const unavailable = Boolean(this.nativeTarget.options[index]?.disabled)
      option.hidden = unavailable
      option.setAttribute("aria-disabled", String(unavailable))
    })

    this.optionTargets.forEach((option, index) => {
      option.setAttribute("aria-selected", String(index === this.selectedIndex))
    })
    if (this.opened) this.markActive()
  }

  changed() {
    this.syncFromNative()
    // Keep the query, content kind and companion filter from the same GET form.
    // requestSubmit lets Turbo Drive update the results without an Apply button.
    const form = this.nativeTarget.form
    if (this.submitOnChangeValue && form && form.isConnected) form.requestSubmit()
  }

  focusTrigger(event) {
    if (!this.nativeTarget.hidden) return
    event.preventDefault()
    this.triggerTarget.focus()
  }

  toggle() {
    if (this.opened) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    if (this.opened) return
    this.opened = true
    this.activeIndex = this.selectedIndex
    this.listTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.markActive()
  }

  close(restoreFocus = false) {
    if (!this.opened) return
    this.opened = false
    this.listTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.removeAttribute("aria-activedescendant")
    this.optionTargets.forEach((option) => option.classList.remove("is-highlighted"))
    this.typeahead = ""
    if (restoreFocus) this.triggerTarget.focus()
  }

  markActive() {
    this.optionTargets.forEach((option, index) => {
      option.classList.toggle("is-highlighted", index === this.activeIndex)
    })
    const active = this.optionTargets[this.activeIndex]
    if (active) {
      this.triggerTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    }
  }

  select(index) {
    const option = this.optionTargets[index]
    if (!option || option.hidden) return
    const unchanged = this.nativeTarget.value === option.dataset.value
    this.nativeTarget.value = option.dataset.value
    this.syncFromNative()
    this.close(true)
    // No redundant server navigation when the already-selected value is chosen.
    if (!unchanged) this.nativeTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  choose(event) {
    const index = this.optionTargets.indexOf(event.currentTarget)
    this.select(index)
  }

  onWindowClick(event) {
    if (this.opened && !this.element.contains(event.target)) this.close()
  }

  onKeydown(event) {
    if (event.key === "Tab") {
      this.close()
      return
    }
    if (event.key === "Escape") {
      if (this.opened) {
        event.preventDefault()
        this.close(true)
      }
      return
    }

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (!this.opened) this.open()
      const increment = event.key === "ArrowDown" ? 1 : -1
      this.activeIndex = (this.activeIndex + increment + this.optionTargets.length) % this.optionTargets.length
      this.markActive()
      return
    }
    if (event.key === "Home" || event.key === "End") {
      event.preventDefault()
      if (!this.opened) this.open()
      this.activeIndex = event.key === "Home" ? 0 : this.optionTargets.length - 1
      this.markActive()
      return
    }
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      if (this.opened) this.select(this.activeIndex)
      else this.open()
      return
    }
    if (!event.altKey && !event.ctrlKey && !event.metaKey && event.key.length === 1 && /[\p{L}\p{N}]/u.test(event.key)) {
      event.preventDefault()
      if (!this.opened) this.open()
      const now = Date.now()
      this.typeahead = now - this.lastTypedAt > 700 ? event.key.toLowerCase() : this.typeahead + event.key.toLowerCase()
      this.lastTypedAt = now
      let matched = this.optionTargets.findIndex((option) =>
        option.textContent.trim().toLowerCase().startsWith(this.typeahead))
      if (matched < 0) {
        this.typeahead = event.key.toLowerCase()
        matched = this.optionTargets.findIndex((option) =>
          option.textContent.trim().toLowerCase().startsWith(this.typeahead))
      }
      if (matched >= 0) {
        this.activeIndex = matched
        this.markActive()
      }
    }
  }
}
