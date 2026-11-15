import { Controller } from "@hotwired/stimulus"

// Native-backed Signal Deck combobox. The real select retains form semantics,
// Rails/Stimulus change events and no-JavaScript fallback. The custom list is
// placed in the browser top layer so dialogs and scrolling editors cannot clip it.
let nextId = 0
const KEY_SEARCH = /^[\p{L}\p{N}]$/u

export default class extends Controller {
  connect() {
    this.native = this.element
    if (!(this.native instanceof HTMLSelectElement) || this.native.hidden) return
    this.baseId = this.native.id || "sd-ui-select-" + (++nextId)
    if (!this.native.id) this.native.id = this.baseId
    this.nameText = this.native.getAttribute("aria-label") ||
      this.native.labels?.[0]?.querySelector("span")?.textContent?.trim() ||
      this.native.labels?.[0]?.textContent?.trim().split("\n")[0] ||
      this.native.name || "Select"
    this.shell = document.createElement("span")
    this.shell.className = "sd-ui-select"
    this.trigger = document.createElement("button")
    this.trigger.type = "button"
    this.trigger.className = "sd-ui-select__trigger"
    this.trigger.setAttribute("role", "combobox")
    this.trigger.setAttribute("aria-haspopup", "listbox")
    this.trigger.setAttribute("aria-autocomplete", "none")
    this.trigger.setAttribute("aria-expanded", "false")
    this.trigger.setAttribute("aria-controls", this.baseId + "-options")
    const icon = this.native.labels?.[0]?.querySelector(".sd-icon")?.cloneNode(true)
    if (icon) {
      icon.classList.add("sd-ui-select__icon")
      icon.setAttribute("aria-hidden", "true")
      this.trigger.append(icon)
    }
    this.valueLabel = document.createElement("span")
    this.valueLabel.className = "sd-ui-select__value"
    this.chevron = document.createElement("span")
    this.chevron.className = "sd-ui-select__chevron"
    this.chevron.setAttribute("aria-hidden", "true")
    this.trigger.append(this.valueLabel, this.chevron)

    this.menu = document.createElement("div")
    this.menu.id = this.baseId + "-options"
    this.menu.className = "sd-ui-select__menu"
    this.menu.setAttribute("role", "listbox")
    this.menu.setAttribute("aria-label", this.nameText)
    this.supportsPopover = typeof this.menu.showPopover === "function"
    if (this.supportsPopover) this.menu.popover = "manual"
    else this.menu.hidden = true

    this.shell.append(this.trigger, this.menu)
    this.native.after(this.shell)
    this.native.classList.add("sd-ui-select__native")
    this.native.hidden = true
    this.opened = false
    this.activeIndex = 0
    this.typeahead = ""
    this.typeTime = 0
    this.rebuild()
    this.sync()
    this.onTrigger = () => this.toggle()
    this.onMenuClick = event => {
      const item = event.target.closest("[data-ui-option-index]")
      if (item && this.menu.contains(item)) this.choose(Number(item.dataset.uiOptionIndex))
    }
    this.onMenuHover = event => {
      const item = event.target.closest("[data-ui-option-index]")
      if (item && this.menu.contains(item)) {
        this.activeIndex = Number(item.dataset.uiOptionIndex)
        this.markActive(false)
      }
    }
    this.onOutside = event => {
      if (this.opened && !this.shell.contains(event.target)) this.close(false)
    }
    this.onKeyboard = event => this.keydown(event)
    this.onNativeChange = () => this.sync()
    this.onViewportChange = () => { if (this.opened) this.position() }
    this.onNativeAttribute = new MutationObserver(() => this.sync())
    this.onNativeAttribute.observe(this.native, { attributes: true, attributeFilter: ["disabled"] })
    this.trigger.addEventListener("click", this.onTrigger)
    this.menu.addEventListener("click", this.onMenuClick)
    this.menu.addEventListener("pointerover", this.onMenuHover)
    this.native.addEventListener("change", this.onNativeChange)
    this.native.addEventListener("ui-select:sync", this.onNativeChange)
    document.addEventListener("pointerdown", this.onOutside, true)
    document.addEventListener("keydown", this.onKeyboard, true)
    window.addEventListener("resize", this.onViewportChange)
    window.addEventListener("scroll", this.onViewportChange, true)
  }

  disconnect() {
    if (!this.shell) return
    this.close(false, true)
    clearTimeout(this.closeTimer)
    this.onNativeAttribute?.disconnect()
    this.trigger.removeEventListener("click", this.onTrigger)
    this.menu.removeEventListener("click", this.onMenuClick)
    this.menu.removeEventListener("pointerover", this.onMenuHover)
    this.native.removeEventListener("change", this.onNativeChange)
    this.native.removeEventListener("ui-select:sync", this.onNativeChange)
    document.removeEventListener("pointerdown", this.onOutside, true)
    document.removeEventListener("keydown", this.onKeyboard, true)
    window.removeEventListener("resize", this.onViewportChange)
    window.removeEventListener("scroll", this.onViewportChange, true)
    this.shell.remove()
    this.native.hidden = false
    this.native.classList.remove("sd-ui-select__native")
    this.shell = null
  }

  rebuild() {
    this.menu.replaceChildren()
    this.options = Array.from(this.native.options)
    this.options.forEach((option, index) => {
      const item = document.createElement("div")
      item.id = this.baseId + "-option-" + index
      item.setAttribute("role", "option")
      item.setAttribute("aria-selected", "false")
      item.setAttribute("aria-disabled", String(option.disabled))
      item.tabIndex = -1
      item.dataset.uiOptionIndex = String(index)
      item.className = "sd-ui-select__option"
      item.hidden = Boolean(option.hidden)
      const text = document.createElement("span")
      text.textContent = option.label || option.textContent
      const check = document.createElement("span")
      check.className = "sd-ui-select__check"
      check.setAttribute("aria-hidden", "true")
      check.textContent = "✓"
      item.append(text, check)
      this.menu.append(item)
    })
    this.items = Array.from(this.menu.children)
  }

  sync() {
    if (!this.trigger) return
    if (this.options.length !== this.native.options.length) this.rebuild()
    const index = Math.max(0, this.native.selectedIndex)
    this.selectedIndex = index
    if (!this.opened) this.activeIndex = index
    this.valueLabel.textContent = this.native.options[index]?.label || this.native.options[index]?.textContent || ""
    this.trigger.setAttribute("aria-label", this.nameText + ": " + this.valueLabel.textContent)
    this.trigger.disabled = this.native.disabled
    this.items.forEach((item, i) => {
      item.setAttribute("aria-selected", String(i === index))
      item.setAttribute("aria-disabled", String(this.native.options[i]?.disabled || false))
    })
    if (this.native.disabled && this.opened) this.close(false)
    if (this.opened) this.markActive(false)
  }

  toggle() { this.opened ? this.close(false) : this.open() }

  open() {
    if (this.opened || this.native.disabled) return
    clearTimeout(this.closeTimer)
    this.opened = true
    this.activeIndex = Math.max(0, this.native.selectedIndex)
    this.menu.hidden = false
    if (this.supportsPopover) {
      try { if (!this.menu.matches(":popover-open")) this.menu.showPopover() }
      catch (_) { this.supportsPopover = false; this.menu.removeAttribute("popover") }
    }
    this.trigger.setAttribute("aria-expanded", "true")
    this.position()
    this.markActive(true)
    requestAnimationFrame(() => { if (this.opened) this.menu.classList.add("is-open") })
  }

  close(restoreFocus = false, immediate = false) {
    if (!this.opened && !immediate) return
    this.opened = false
    this.trigger.setAttribute("aria-expanded", "false")
    this.trigger.removeAttribute("aria-activedescendant")
    this.menu.classList.remove("is-open")
    clearTimeout(this.closeTimer)
    const finish = () => {
      if (this.opened) return
      if (this.supportsPopover && this.menu.matches(":popover-open")) this.menu.hidePopover()
      this.menu.hidden = true
    }
    if (immediate || window.matchMedia("(prefers-reduced-motion: reduce)").matches) finish()
    else this.closeTimer = setTimeout(finish, 145)
    if (restoreFocus) this.trigger.focus()
  }

  position() {
    const rect = this.trigger.getBoundingClientRect()
    const maxWidth = Math.max(120, window.innerWidth - 16)
    const width = Math.min(maxWidth, Math.max(rect.width, 214))
    const left = Math.max(8, Math.min(rect.left, window.innerWidth - width - 8))
    const below = window.innerHeight - rect.bottom - 12
    const above = rect.top - 12
    const upward = below < 180 && above > below
    const room = Math.max(70, upward ? above : below)
    const height = Math.min(280, room)
    this.menu.style.width = width + "px"
    this.menu.style.maxHeight = height + "px"
    this.menu.style.left = left + "px"
    this.menu.style.top = (upward ? Math.max(8, rect.top - Math.min(height, this.menu.scrollHeight) - 6) : rect.bottom + 6) + "px"
  }

  markActive(scroll = true) {
    this.items.forEach((item, i) => item.classList.toggle("is-highlighted", i === this.activeIndex))
    const active = this.items[this.activeIndex]
    if (!active) return
    this.trigger.setAttribute("aria-activedescendant", active.id)
    if (scroll) active.scrollIntoView({ block: "nearest" })
  }

  choose(index) {
    const option = this.native.options[index]
    if (!option || option.disabled || option.hidden) return
    const changed = this.native.value !== option.value
    this.native.selectedIndex = index
    this.sync()
    this.close(true)
    if (changed) this.native.dispatchEvent(new Event("change", { bubbles: true }))
  }

  keydown(event) {
    if (!this.opened && event.target !== this.trigger) return
    if (event.key === "Escape") {
      if (this.opened) { event.preventDefault(); this.close(true) }
      return
    }
    if (event.key === "Tab") { if (this.opened) this.close(false); return }
    const direction = event.key === "ArrowDown" ? 1 : event.key === "ArrowUp" ? -1 : 0
    if (direction || event.key === "Home" || event.key === "End") {
      event.preventDefault()
      if (!this.opened) this.open()
      if (event.key === "Home") this.activeIndex = 0
      else if (event.key === "End") this.activeIndex = this.items.length - 1
      else this.activeIndex = (this.activeIndex + direction + this.items.length) % this.items.length
      for (let i = 0; i < this.items.length; i++) {
        if (!this.native.options[this.activeIndex]?.disabled && !this.native.options[this.activeIndex]?.hidden) break
        this.activeIndex = (this.activeIndex + (direction || 1) + this.items.length) % this.items.length
      }
      this.markActive()
      return
    }
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.opened ? this.choose(this.activeIndex) : this.open()
      return
    }
    if (!event.altKey && !event.ctrlKey && !event.metaKey && KEY_SEARCH.test(event.key)) {
      event.preventDefault()
      if (!this.opened) this.open()
      const now = Date.now()
      this.typeahead = now - this.typeTime > 750 ? event.key.toLocaleLowerCase() :
        this.typeahead + event.key.toLocaleLowerCase()
      this.typeTime = now
      const found = this.options.findIndex(opt =>
        !opt.disabled && !opt.hidden && opt.textContent.trim().toLocaleLowerCase().startsWith(this.typeahead))
      if (found >= 0) { this.activeIndex = found; this.markActive() }
    }
  }
}
