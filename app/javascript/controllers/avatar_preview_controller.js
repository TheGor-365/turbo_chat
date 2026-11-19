import { Controller } from "@hotwired/stimulus"

// Local-only preview. The file is uploaded only when the user saves the Devise form.
export default class extends Controller {
  static targets = ["input", "image", "placeholder", "status"]
  static values = { messages: Object }

  connect() {
    this.previewUrl = null
  }

  disconnect() {
    this.releasePreview()
  }

  changed() {
    this.releasePreview()
    const file = this.inputTarget.files?.[0]
    if (!file) {
      this.imageTarget.hidden = !this.imageTarget.getAttribute("src")
      if (this.hasPlaceholderTarget) this.placeholderTarget.hidden = false
      this.statusTarget.textContent = this.messagesValue.none
      return
    }

    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      this.inputTarget.value = ""
      this.statusTarget.textContent = this.messagesValue.invalid_type
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      this.inputTarget.value = ""
      this.statusTarget.textContent = this.messagesValue.too_large
      return
    }

    this.previewUrl = URL.createObjectURL(file)
    this.imageTarget.src = this.previewUrl
    this.imageTarget.hidden = false
    if (this.hasPlaceholderTarget) this.placeholderTarget.hidden = true
    this.statusTarget.textContent = this.messagesValue.selected.replace("{{filename}}", file.name)
  }

  releasePreview() {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
