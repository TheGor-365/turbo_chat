import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  initialize() {
    this.resetScrollWithoutThreshold(messages);
  }

  connect() {
    console.log("Connected");
    const messages = document.getElementById("messages");
    messages.addEventListener("DOMNodeIserted", this.resetScroll);
    this.resetScrollWithoutThreshold(messages);
  }

  disconnect() {
    console.log("Disconnected")

  }

  resetScroll() {
    const bottomOfScroll = messages.scrollHeight - messages.clientHeight;
    const upperScrollThreshold = bottomOfScroll - 500;

    if (messages.scrollTop > upperScrollThreshold) {
      messages.scrollTop = messages.scrollHeight - messages.clientHeight;
    }
  }

  resetScrollWithoutThreshold() {
    messages.scrollTop = messages.scrollHeight - messages.clientHeight;
  }
}
