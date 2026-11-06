import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// Text-only DOM updates. Never insert server labels as HTML.
export default class extends Controller {
  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "ProfileLabelsChannel" },
      {
        connected: () => { this.element.dataset.profileLabelsConnected = "true" },
        disconnected: () => { this.element.dataset.profileLabelsConnected = "false" },
        rejected: () => { this.element.dataset.profileLabelsConnected = "false" },
        received: (payload) => {
          if (payload?.type === "snapshot" && Array.isArray(payload.profiles)) {
            payload.profiles.forEach((profile) => this.apply(profile))
          } else if (payload?.type === "profile_changed") {
            this.apply(payload)
          }
        }
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    delete this.element.dataset.profileLabelsConnected
  }

  apply(profile) {
    const id = profile?.user_id
    const label = profile?.label
    if (!Number.isSafeInteger(id) || id <= 0 ||
        typeof label !== "string" || !label.length || label.length > 80) return

    document.querySelectorAll(`[data-profile-label-user-id="${id}"]`)
      .forEach((node) => { node.textContent = label })
    document.querySelectorAll(`[data-profile-initial-user-id="${id}"]`)
      .forEach((node) => { node.textContent = Array.from(label)[0]?.toUpperCase() || "?" })
    document.querySelectorAll(`[data-profile-start-user-id="${id}"]`)
      .forEach((node) => node.setAttribute("aria-label", "Start conversation with " + label))
    document.querySelectorAll(`[data-profile-reply-user-id="${id}"]`)
      .forEach((node) => {
        node.dataset.replyAuthor = label
        node.setAttribute("aria-label", "Reply to message from " + label)
      })
    document.querySelectorAll(`[data-profile-media-user-id="${id}"]`)
      .forEach((node) => {
        const prefix = node.dataset.profileMediaKind === "video" ? "Video clip from " : "Voice message from "
        node.setAttribute("aria-label", prefix + label)
      })
  }
}
