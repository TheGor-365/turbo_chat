import { Controller } from "@hotwired/stimulus"

// Local-only preview. The file is uploaded only when the user saves the Devise form.
export default class extends Controller {
  static targets = ["input", "image", "placeholder", "status"]

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
      this.statusTarget.textContent = "No new photo selected."
      return
    }

    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      this.inputTarget.value = ""
      this.statusTarget.textContent = "Choose a JPG, PNG or WebP image."
      return
    }
    if (file.size > 5 * 1024 * 1024) {
      this.inputTarget.value = ""
      this.statusTarget.textContent = "The photo must be 5 MB or smaller."
      return
    }

    this.previewUrl = URL.createObjectURL(file)
    this.imageTarget.src = this.previewUrl
    this.imageTarget.hidden = false
    if (this.hasPlaceholderTarget) this.placeholderTarget.hidden = true
    this.statusTarget.textContent = `Selected: ${file.name}. Save changes to upload.`
  }

  releasePreview() {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
