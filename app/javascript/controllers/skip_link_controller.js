import { Controller } from "@hotwired/stimulus"

// Keyboard Enter dispatches a normal click. Prevent Turbo navigation and
// explicitly hand focus to the main landmark. The href still works without JS.
export default class extends Controller {
  activate(event) {
    const main = document.getElementById("main-content")
    if (!main) return

    event.preventDefault()
    main.focus()
  }
}
