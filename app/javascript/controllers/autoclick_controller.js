import { Controller } from '@hotwired/stimulus'
import { useIntersection } from 'stimulus-use'

export default class Autoclick extends Controller {
  options() {
    threshold: 0;
  }

  static messagesContainer;
  static topMessage;
  static throttling = false;

  connect() {
    console.log("Connected to Autoclick!");
    useIntersection(this, this.options)
  }

  appear(entry) {
    if (!Autoclick.throttling) {
      Autoclick.throttling = true;
      Autoclick.messagesContainer = document.getElementById("messages-container");
      Autoclick.topMessage = Autoclick.messagesContainer.children[0];
      Autoclick.throttle(this.element.click(), 300);
    }

    setTimeout(() => {
      Autoclick.topMessage.scrollIntoView({
        behavior: "auto",
        block: "end",
      });
      console.log("Scrolling");
      Autoclick.throttling = false;
    }, 250);
  }

  resize({ height, width }) {

  }

  static throttle(func, wait) {
    let timeout = null;
    let previous = 0;

    let later = function () {
      previous = Date.now();
      timeout = null;
      func();
    };
  }

  return function () {
    let now = Date.now();
    let remaining = wait - (now - previous);

    if (remaining <= 0 || remaining > wait) {
      if (timeout) {
        clearTimeout(timeout);
      }
      later();
    } else if (!timeout) {
      timeout = setTimeout(later, remaining);
    }
  }
}
