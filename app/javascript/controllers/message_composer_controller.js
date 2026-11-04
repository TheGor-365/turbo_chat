import { Controller } from "@hotwired/stimulus"

// File-picker and OS drop, without any external upload SDK.
// The Rails endpoint remains authoritative for file type and room access.
const TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf", "text/plain"])
const MAX_FILES = 5
const MAX_BYTES = 5 * 1024 * 1024

export default class extends Controller {
  static targets = ["files", "body", "previews", "feedback", "submit", "cameraPanel", "cameraVideo"]

  connect() {
    this.selected = []
    this.objectUrls = []
    this.depth = 0
    this.sending = false
    this.cameraRequested = false
    this.cameraStream = null

    // File drops on the message history, sidebar, or chat background
    // must not navigate Chrome away from a private conversation.
    this.boundWindowDragEnter = this.windowDragEnter.bind(this)
    this.boundWindowDragOver = this.windowDragOver.bind(this)
    this.boundWindowDragLeave = this.windowDragLeave.bind(this)
    this.boundWindowDrop = this.windowDrop.bind(this)
    window.addEventListener("dragenter", this.boundWindowDragEnter, true)
    window.addEventListener("dragover", this.boundWindowDragOver, true)
    window.addEventListener("dragleave", this.boundWindowDragLeave, true)
    window.addEventListener("drop", this.boundWindowDrop, true)
  }

  disconnect() {
    window.removeEventListener("dragenter", this.boundWindowDragEnter, true)
    window.removeEventListener("dragover", this.boundWindowDragOver, true)
    window.removeEventListener("dragleave", this.boundWindowDragLeave, true)
    window.removeEventListener("drop", this.boundWindowDrop, true)
    this.clearDragOverlay()
    this.closeCamera()
    this.releaseUrls()
  }

  filesSelected(event) { this.addFiles(Array.from(event.target.files || [])) }
  fileDrag(event) { return Array.from(event.dataTransfer?.types || []).includes("Files") }

  dragArea() {
    return this.element.closest("#single_room")
  }

  showDragOverlay() {
    this.dragArea()?.classList.add("composer-room-dragging")
  }

  clearDragOverlay() {
    this.depth = 0
    this.dragArea()?.classList.remove("composer-room-dragging")
  }

  windowDragEnter(event) {
    if (!this.fileDrag(event)) return
    event.preventDefault()
    this.depth++
    this.showDragOverlay()
  }

  windowDragOver(event) {
    if (!this.fileDrag(event)) return
    event.preventDefault()
    if (event.dataTransfer) event.dataTransfer.dropEffect = "copy"
    this.showDragOverlay()
  }

  windowDragLeave(event) {
    if (!this.fileDrag(event)) return
    event.preventDefault()
    // Nested elements can generate leave events; only hide when the
    // drag cursor leaves the browser window, not between DOM nodes.
    if (!event.relatedTarget) this.clearDragOverlay()
  }

  windowDrop(event) {
    if (!this.fileDrag(event)) return
    // Capture the event before the browser default file-open behavior.
    // Stop propagation so no nested composer handler adds files twice.
    event.preventDefault()
    event.stopPropagation()
    this.clearDragOverlay()
    this.addFiles(Array.from(event.dataTransfer?.files || []))
  }

  addFiles(incoming) {
    if (this.sending) return
    const next = [...this.selected]
    for (const file of incoming) {
      if (!TYPES.has(file.type)) {
        this.feedback("Only JPEG, PNG, WebP, PDF and UTF-8 text files are supported.", true)
        this.syncInput()
        return
      }
      if (file.size === 0 || file.size > MAX_BYTES) {
        this.feedback("Each file must be between 1 byte and 5 MB.", true)
        this.syncInput()
        return
      }
      const exists = next.some((item) => item.name === file.name &&
        item.size === file.size && item.lastModified === file.lastModified)
      if (!exists) next.push(file)
      if (next.length > MAX_FILES) {
        this.feedback("Up to five attachments per message.", true)
        this.syncInput()
        return
      }
    }
    this.selected = next
    if (this.syncInput()) {
      this.renderPreviews()
      this.feedback(this.selected.length ? this.selected.length + " file(s) ready." : "", false)
    }
  }

  syncInput() {
    try {
      const data = new DataTransfer()
      this.selected.forEach((file) => data.items.add(file))
      this.filesTarget.files = data.files
      return true
    } catch (_) {
      this.selected = []
      this.filesTarget.value = ""
      this.releaseUrls()
      this.previewsTarget.replaceChildren()
      this.previewsTarget.hidden = true
      this.feedback("Drag/drop unsupported by this browser; use the file picker.", true)
      return false
    }
  }

  renderPreviews() {
    this.releaseUrls()
    this.previewsTarget.replaceChildren()
    this.previewsTarget.hidden = !this.selected.length
    this.selected.forEach((file, i) => {
      const item = document.createElement("div")
      item.className = "composer-preview"
      item.setAttribute("role", "listitem")
      if (file.type.startsWith("image/")) {
        const img = document.createElement("img")
        img.className = "composer-preview-image"
        img.alt = ""
        img.src = URL.createObjectURL(file)
        this.objectUrls.push(img.src)
        item.appendChild(img)
      } else {
        const icon = document.createElement("span")
        icon.className = "composer-preview-icon"
        icon.textContent = file.type === "application/pdf" ? "PDF" : "TXT"
        item.appendChild(icon)
      }
      const name = document.createElement("span")
      name.className = "composer-preview-label"
      name.textContent = file.name
      item.appendChild(name)

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "composer-preview-remove"
      remove.textContent = "×"
      remove.title = "Remove " + file.name
      remove.setAttribute("aria-label", "Remove " + file.name)
      remove.addEventListener("click", () => this.removeFile(i))
      item.appendChild(remove)
      this.previewsTarget.appendChild(item)
    })
  }

  async openCamera() {
    if (this.cameraRequested || this.sending) return
    if (!navigator.mediaDevices?.getUserMedia || !window.isSecureContext) {
      this.feedback("Camera requires browser permission and localhost or HTTPS.", true)
      return
    }

    this.cameraRequested = true
    this.feedback("Requesting camera permission...", false)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } },
        audio: false
      })
      if (!this.cameraRequested || !this.element.isConnected) {
        stream.getTracks().forEach((track) => track.stop())
        return
      }

      this.cameraStream = stream
      this.cameraVideoTarget.srcObject = stream
      this.cameraPanelTarget.hidden = false
      await this.cameraVideoTarget.play()
      this.feedback("Camera is active. Capture or cancel.", false)
    } catch (_) {
      this.closeCamera()
      this.feedback("Camera unavailable. Check browser permission and connected camera.", true)
    }
  }

  capturePhoto() {
    if (!this.cameraStream || !this.cameraVideoTarget.videoWidth) {
      this.feedback("Camera preview is not ready yet.", true)
      return
    }
    const video = this.cameraVideoTarget
    const ratio = Math.min(1, 1280 / video.videoWidth)
    const canvas = document.createElement("canvas")
    canvas.width = Math.max(1, Math.round(video.videoWidth * ratio))
    canvas.height = Math.max(1, Math.round(video.videoHeight * ratio))
    const ctx = canvas.getContext("2d")
    if (!ctx) {
      this.feedback("Image capture is unsupported.", true)
      return
    }
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
    canvas.toBlob((blob) => {
      // The stream may have been closed while encoding was pending.
      if (!this.cameraRequested) return
      this.closeCamera()
      if (!blob) {
        this.feedback("Could not encode photo.", true)
        return
      }
      const photo = new File([blob], "camera-" + Date.now() + ".jpg", { type: "image/jpeg" })
      this.addFiles([photo])
    }, "image/jpeg", 0.82)
  }

  closeCamera() {
    this.cameraRequested = false
    if (this.cameraStream) {
      this.cameraStream.getTracks().forEach((track) => track.stop())
      this.cameraStream = null
    }
    if (this.hasCameraVideoTarget) this.cameraVideoTarget.srcObject = null
    if (this.hasCameraPanelTarget) this.cameraPanelTarget.hidden = true
  }

  removeFile(i) {
    if (this.sending) return
    this.selected.splice(i, 1)
    if (this.syncInput()) this.renderPreviews()
    this.feedback("", false)
  }

  beforeSubmit(event) {
    if (this.sending || (!this.bodyTarget.value.trim() && !this.selected.length)) {
      event.preventDefault()
      this.feedback(this.sending ? "Message is sending." : "Enter a message or attach a file.", true)
    }
  }

  submitStart() {
    this.sending = true
    this.submitTarget.disabled = true
    this.feedback("Sending...", false)
  }

  submitEnd(event) {
    this.sending = false
    this.submitTarget.disabled = false
    if (event.detail.success) {
      this.element.reset()
      this.selected = []
      this.releaseUrls()
      this.previewsTarget.replaceChildren()
      this.previewsTarget.hidden = true
      this.feedback("", false)
      this.bodyTarget.focus()
    } else {
      this.feedback("Upload failed. Check file size/type or connection; draft retained.", true)
    }
  }

  feedback(message, error) {
    this.feedbackTarget.hidden = !message
    this.feedbackTarget.textContent = message
    this.feedbackTarget.classList.toggle("text-danger", error)
    this.feedbackTarget.classList.toggle("text-white-50", !error)
  }

  releaseUrls() {
    if (!this.objectUrls) return
    this.objectUrls.forEach((url) => URL.revokeObjectURL(url))
    this.objectUrls = []
  }
}
