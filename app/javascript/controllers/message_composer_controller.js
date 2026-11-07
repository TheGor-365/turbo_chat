import { Controller } from "@hotwired/stimulus"

// File-picker and OS drop, without any external upload SDK.
// The Rails endpoint remains authoritative for file type and room access.
const TYPES = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf", "text/plain", "text/markdown", "audio/webm", "video/webm"])
const MAX_FILES = 5
const MAX_BYTES = 5 * 1024 * 1024

export default class extends Controller {
  static targets = ["files", "body", "previews", "feedback", "submit", "cameraPanel", "cameraVideo",
    "voicePanel", "voiceStatus", "voiceButton", "voiceStop",
    "photoButton", "cameraCancel", "clipRecord", "clipStop", "clipDiscard", "clipStatus",
    "replyTo", "replyPreview", "replyPreviewText"]

  connect() {
    this.selected = []
    this.objectUrls = []
    this.depth = 0
    this.sending = false
    this.cameraRequested = false
    this.cameraStream = null
    this.voiceSequence = 0
    this.voiceRequested = false
    this.voiceRecorder = null
    this.voiceStream = null
    this.voiceChunks = []
    this.voiceBytes = 0
    this.voiceDiscarded = false
    this.voiceTimer = null
    this.clipRecorder = null
    this.clipChunks = []
    this.clipBytes = 0
    this.clipDiscarded = false
    this.clipSequence = 0
    this.clipTimer = null

    // File drops on the message history, sidebar, or chat background
    // must not navigate Chrome away from a private conversation.
    this.boundWindowDragEnter = this.windowDragEnter.bind(this)
    this.boundWindowDragOver = this.windowDragOver.bind(this)
    this.boundWindowDragLeave = this.windowDragLeave.bind(this)
    this.boundWindowDrop = this.windowDrop.bind(this)
    // Reply buttons live outside the composer form and can be replaced at
    // any time by room-scoped Turbo streams. Delegate on this room only.
    this.replyArea = this.dragArea()
    this.boundReplyClick = this.chooseReply.bind(this)
    this.replyArea?.addEventListener("click", this.boundReplyClick)
    window.addEventListener("dragenter", this.boundWindowDragEnter, true)
    window.addEventListener("dragover", this.boundWindowDragOver, true)
    window.addEventListener("dragleave", this.boundWindowDragLeave, true)
    window.addEventListener("drop", this.boundWindowDrop, true)
  }

  disconnect() {
    this.replyArea?.removeEventListener("click", this.boundReplyClick)
    this.replyArea = null
    window.removeEventListener("dragenter", this.boundWindowDragEnter, true)
    window.removeEventListener("dragover", this.boundWindowDragOver, true)
    window.removeEventListener("dragleave", this.boundWindowDragLeave, true)
    window.removeEventListener("drop", this.boundWindowDrop, true)
    this.clearDragOverlay()
    this.discardVoice()
    this.discardClip()
    this.closeCamera()
    this.releaseUrls()
  }

  chooseReply(event) {
    const replyButton = event.target.closest?.("[data-reply-message-id]")
    if (!replyButton || !this.replyArea?.contains(replyButton)) return
    event.preventDefault()

    const id = replyButton.dataset.replyMessageId
    if (!/^\d+$/.test(id)) return
    this.replyToTarget.value = id
    this.replyPreviewTextTarget.textContent =
      "Reply to " + replyButton.dataset.replyAuthor + ": " + replyButton.dataset.replyPreview
    this.replyPreviewTarget.hidden = false
    this.bodyTarget.focus()
  }

  clearReply() {
    this.replyToTarget.value = ""
    this.replyPreviewTarget.hidden = true
    this.replyPreviewTextTarget.textContent = ""
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
    for (const droppedFile of incoming) {
      // Chrome/Linux can report Markdown as text/markdown or an empty MIME.
      // Normalize known text extensions, never arbitrary unrecognized files.
      const textFile = /\.(?:md|markdown|txt)$/i.test(droppedFile.name) &&
        ["", "text/markdown", "text/plain"].includes(droppedFile.type)
      const file = textFile
        ? new File([droppedFile], droppedFile.name, {
            type: "text/plain", lastModified: droppedFile.lastModified
          })
        : droppedFile
      if (!TYPES.has(file.type)) {
        this.feedback("Unsupported file: " + droppedFile.name + ". Use JPG, PNG, WebP, PDF, TXT, Markdown or supported WebM media.", true)
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
      } else if (file.type === "video/webm") {
        const video = document.createElement("video")
        video.controls = true
        video.muted = true
        video.playsInline = true
        video.preload = "metadata"
        video.className = "composer-video-preview"
        video.setAttribute("aria-label", "Video preview: " + file.name)
        video.src = URL.createObjectURL(file)
        this.objectUrls.push(video.src)
        item.appendChild(video)
      } else if (file.type === "audio/webm") {
        const audio = document.createElement("audio")
        audio.controls = true
        audio.preload = "metadata"
        audio.className = "composer-voice-preview"
        audio.setAttribute("aria-label", "Voice note preview: " + file.name)
        const url = URL.createObjectURL(file)
        this.objectUrls.push(url)
        audio.src = url
        item.appendChild(audio)
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
    if (this.cameraRequested || this.sending || this.voiceRequested || this.voiceRecorder) return
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
    if (this.clipRecorder) return
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
    if (this.clipRecorder) {
      this.discardClip()
      return
    }
    this.cameraRequested = false
    if (this.cameraStream) {
      this.cameraStream.getTracks().forEach((track) => track.stop())
      this.cameraStream = null
    }
    if (this.hasCameraVideoTarget) this.cameraVideoTarget.srcObject = null
    if (this.hasCameraPanelTarget) this.cameraPanelTarget.hidden = true
  }

  // Camera permission was already requested in openCamera(). v1 intentionally
  // records video WITHOUT microphone audio; OS input remains a deferred defect.
  startClip() {
    if (!this.cameraStream || this.clipRecorder || this.sending) return
    const mime = "video/webm;codecs=vp8"
    if (!window.MediaRecorder?.isTypeSupported?.(mime)) {
      this.feedback("This browser cannot record WebM/VP8 video clips.", true)
      return
    }

    const sequence = ++this.clipSequence
    this.clipDiscarded = false
    this.clipChunks = []
    this.clipBytes = 0
    try {
      const recorder = new MediaRecorder(this.cameraStream, {
        mimeType: mime,
        videoBitsPerSecond: 350000
      })
      this.clipRecorder = recorder
      recorder.ondataavailable = (event) => {
        if (!event.data?.size || this.clipDiscarded) return
        this.clipChunks.push(event.data)
        this.clipBytes += event.data.size
        if (this.clipBytes > MAX_BYTES) {
          this.clipDiscarded = true
          this.stopClip()
          this.feedback("Video clip exceeded 5 MB; recording discarded.", true)
        }
      }
      recorder.onerror = () => {
        this.clipDiscarded = true
        this.stopClip()
        this.feedback("Video recording failed; no clip attached.", true)
      }
      recorder.onstop = () => {
        if (sequence !== this.clipSequence) return
        this.clipRecorder = null
        this.clearClipTimer()
        const shouldAttach = !this.clipDiscarded && this.element.isConnected
        const video = shouldAttach
          ? new Blob(this.clipChunks, { type: "video/webm" })
          : null
        this.clipChunks = []
        this.updateClipControls(false)
        this.closeCamera()
        if (!shouldAttach) return
        if (!video || !video.size || video.size > MAX_BYTES) {
          this.feedback("Video clip was empty or exceeded the 5 MB limit.", true)
          return
        }
        this.addFiles([new File([video], "clip-" + Date.now() + ".webm", { type: "video/webm" })])
      }
      recorder.start(750)
      this.clipStarted = performance.now()
      this.updateClipControls(true)
      this.clipStatusTarget.textContent = "Recording video (silent) · max 10 seconds"
      this.clipTimer = window.setInterval(() => {
        const elapsed = (performance.now() - this.clipStarted) / 1000
        if (elapsed >= 10) this.stopClip()
        else this.clipStatusTarget.textContent =
          "Silent video · " + elapsed.toFixed(1) + " / 10 seconds"
      }, 200)
      this.feedback("Recording a silent clip. Stop or discard before Send.", false)
    } catch (_) {
      this.clipDiscarded = true
      this.clipRecorder = null
      this.clearClipTimer()
      this.updateClipControls(false)
      this.feedback("Cannot start video recording in this browser.", true)
    }
  }

  stopClip() {
    if (!this.clipRecorder) return
    if (this.clipRecorder.state !== "inactive") this.clipRecorder.stop()
    if (this.hasClipStopTarget) this.clipStopTarget.disabled = true
    // Wait until MediaRecorder emits the final chunk before stopping tracks.
    this.clearClipTimer()
  }

  discardClip() {
    ++this.clipSequence
    this.clipDiscarded = true
    const recorder = this.clipRecorder
    this.clipRecorder = null
    if (recorder && recorder.state !== "inactive") recorder.stop()
    this.clipChunks = []
    this.clearClipTimer()
    this.updateClipControls(false)
    // closeCamera() must not re-enter discardClip() after recorder is cleared.
    this.closeCamera()
  }

  updateClipControls(recording) {
    if (this.hasPhotoButtonTarget) this.photoButtonTarget.hidden = recording
    if (this.hasCameraCancelTarget) this.cameraCancelTarget.hidden = recording
    if (this.hasClipRecordTarget) this.clipRecordTarget.hidden = recording
    if (this.hasClipStopTarget) {
      this.clipStopTarget.hidden = !recording
      this.clipStopTarget.disabled = false
    }
    if (this.hasClipDiscardTarget) this.clipDiscardTarget.hidden = !recording
    if (this.hasClipStatusTarget) this.clipStatusTarget.hidden = !recording
  }

  clearClipTimer() {
    if (this.clipTimer) window.clearInterval(this.clipTimer)
    this.clipTimer = null
  }

  async startVoice() {
    if (this.sending || this.voiceRequested || this.voiceRecorder || this.clipRecorder) return
    const mime = "audio/webm;codecs=opus"
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia ||
        !window.MediaRecorder?.isTypeSupported?.(mime)) {
      this.feedback("Voice recording needs HTTPS/localhost and WebM/Opus support in this browser.", true)
      return
    }

    this.closeCamera()
    this.voiceRequested = true
    this.voiceDiscarded = false
    const sequence = ++this.voiceSequence
    this.feedback("Requesting microphone permission...", false)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true },
        video: false
      })
      if (sequence !== this.voiceSequence || !this.element.isConnected) {
        stream.getTracks().forEach((track) => track.stop())
        return
      }

      this.voiceStream = stream
      this.voiceChunks = []
      this.voiceBytes = 0
      const recorder = new MediaRecorder(stream, {
        mimeType: mime,
        audioBitsPerSecond: 64000
      })
      this.voiceRecorder = recorder
      recorder.ondataavailable = (event) => {
        if (!event.data?.size || this.voiceDiscarded) return
        this.voiceChunks.push(event.data)
        this.voiceBytes += event.data.size
        if (this.voiceBytes > MAX_BYTES) {
          this.voiceDiscarded = true
          this.stopVoice()
          this.feedback("Recording exceeds 5 MB and has been discarded.", true)
        }
      }
      recorder.onerror = () => {
        this.voiceDiscarded = true
        this.stopVoice()
        this.feedback("Microphone recording failed; no audio was attached.", true)
      }
      recorder.onstop = () => {
        this.stopVoiceTracks()
        this.clearVoiceTimer()
        this.voiceRecorder = null
        this.voiceRequested = false
        if (this.hasVoiceButtonTarget) this.voiceButtonTarget.disabled = false
        if (this.hasVoicePanelTarget) this.voicePanelTarget.hidden = true

        if (this.voiceDiscarded || sequence !== this.voiceSequence || !this.element.isConnected) return
        const clip = new Blob(this.voiceChunks, { type: "audio/webm" })
        this.voiceChunks = []
        if (!clip.size || clip.size > MAX_BYTES) {
          this.feedback("Recording is empty or exceeds the 5 MB limit.", true)
          return
        }
        this.addFiles([new File([clip], "voice-" + Date.now() + ".webm", { type: "audio/webm" })])
      }

      recorder.start(1000)
      this.voiceStarted = performance.now()
      this.voicePanelTarget.hidden = false
      this.voiceButtonTarget.disabled = true
      this.voiceStopTarget.disabled = false
      this.voiceStatusTarget.textContent = "Recording 00:00 · max 60 seconds"
      this.voiceTimer = window.setInterval(() => {
        const elapsed = Math.floor((performance.now() - this.voiceStarted) / 1000)
        if (elapsed >= 60) {
          this.stopVoice()
        } else {
          this.voiceStatusTarget.textContent =
            "Recording 00:" + String(elapsed).padStart(2, "0") + " · max 60 seconds"
        }
      }, 250)
      this.feedback("Microphone is recording. Stop or discard before sending.", false)
    } catch (_) {
      this.voiceDiscarded = true
      this.stopVoiceTracks()
      this.clearVoiceTimer()
      this.voiceRequested = false
      this.voiceRecorder = null
      if (this.hasVoicePanelTarget) this.voicePanelTarget.hidden = true
      if (this.hasVoiceButtonTarget) this.voiceButtonTarget.disabled = false
      this.feedback("Microphone unavailable or permission denied. Draft preserved.", true)
    }
  }

  stopVoice() {
    if (!this.voiceRecorder) return
    if (this.voiceRecorder.state !== "inactive") this.voiceRecorder.stop()
    if (this.hasVoiceStopTarget) this.voiceStopTarget.disabled = true
    // Keep the audio stream alive until MediaRecorder emits its final
    // dataavailable and stop events. Tracks are stopped by onstop. 
    this.clearVoiceTimer()
  }

  discardVoice() {
    this.voiceDiscarded = true
    ++this.voiceSequence
    if (this.voiceRecorder && this.voiceRecorder.state !== "inactive") {
      this.voiceRecorder.stop()
    }
    this.stopVoiceTracks()
    this.clearVoiceTimer()
    this.voiceRecorder = null
    this.voiceRequested = false
    this.voiceChunks = []
    if (this.hasVoicePanelTarget) this.voicePanelTarget.hidden = true
    if (this.hasVoiceButtonTarget) this.voiceButtonTarget.disabled = false
  }

  stopVoiceTracks() {
    if (this.voiceStream) {
      this.voiceStream.getTracks().forEach((track) => track.stop())
      this.voiceStream = null
    }
  }

  clearVoiceTimer() {
    if (this.voiceTimer) window.clearInterval(this.voiceTimer)
    this.voiceTimer = null
  }

  removeFile(i) {
    if (this.sending) return
    this.selected.splice(i, 1)
    if (this.syncInput()) this.renderPreviews()
    this.feedback("", false)
  }

  openFiles(event) {
    if (event.type === "keydown") event.preventDefault()
    if (this.hasFilesTarget) this.filesTarget.click()
  }

  beforeSubmit(event) {
    if (this.clipRecorder) {
      event.preventDefault()
      this.feedback("Stop or discard the video clip before sending.", true)
      return
    }
    if (this.voiceRequested || this.voiceRecorder) {
      event.preventDefault()
      this.feedback("Stop or discard the voice recording before sending.", true)
      return
    }
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

  async submitEnd(event) {
    this.sending = false
    this.submitTarget.disabled = false
    if (event.detail.success) {
      this.element.reset()
      this.clearReply()
      this.selected = []
      this.releaseUrls()
      this.previewsTarget.replaceChildren()
      this.previewsTarget.hidden = true
      this.feedback("", false)
      this.bodyTarget.focus()
    } else {
      const response = event.detail.fetchResponse
      let reason = ""
      // Rails exposes a bounded validation/attachment error as plain text.
      // Never inject server text as HTML, or echo an HTML error page into chat.
      if (response?.statusCode === 422 && /^text\/plain\b/i.test(response.contentType || "")) {
        try {
          reason = (await response.responseText).trim().slice(0, 250)
        } catch (_) {
          // A failed network response has no readable validation body.
        }
      }
      this.feedback(
        reason
          ? `Message not sent: ${reason}. Draft retained.`
          : `Message not sent${response?.statusCode ? ` (HTTP ${response.statusCode})` : ""}. Draft retained; check your connection or attachments.`,
        true
      )
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
