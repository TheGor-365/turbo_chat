import { Controller } from "@hotwired/stimulus"

// Incoming translation is OPT-IN, local to this account's browser and read-only.
// The canonical message (including attachments, replies and signed authorship)
// is never modified. No text or credentials are sent to an external AI API.
//
// Chrome Translator/LanguageDetector availability is checked at runtime: pairs
// and devices that are unsupported show the original, never a fake translation.
const LOCALES = new Set(["ru", "en", "es", "fr", "de", "pt", "uk", "ar", "zh", "ja", "hy"])
const CHROME_LOCALES = new Set(["ru", "en", "es", "fr", "de", "pt", "uk", "ar", "zh", "ja"])
const MAX_VISIBLE = 35
const MAX_CHARS = 5000

export default class extends Controller {
  static targets = ["toggle", "locale", "source", "status", "summaryState"]
  static values = { userId: String }

  connect() {
    this.key = "relay.chat.incoming-translation.v1." + this.userIdValue
    this.enabled = false
    this.locale = "ru"
    this.source = "auto"
    this.detector = null
    this.sessions = new Map()
    this.generation = 0
    this.running = false
    this.needsAnotherPass = false
    this.restorePreference()
    this.renderPreference()

    this.messageList = this.element.querySelector("#messages-container")
    if (this.messageList) {
      this.observer = new MutationObserver(records => {
        const newMessages = records.some(record => [...record.addedNodes].some(node =>
          node.nodeType === 1 && (node.matches?.(".sd-message") || node.querySelector?.(".sd-message"))))
        if (newMessages && this.enabled) this.schedule()
      })
      this.observer.observe(this.messageList, { childList: true, subtree: true })
    }
    if (this.enabled) this.activate(false)
  }

  disconnect() {
    this.generation += 1
    this.observer?.disconnect()
    this.restoreOriginals()
    this.detector?.destroy?.()
    this.sessions.forEach(sessionPromise => {
      Promise.resolve(sessionPromise).then(session => session?.destroy?.()).catch(() => {})
    })
    this.sessions.clear()
  }

  restorePreference() {
    try {
      const raw = localStorage.getItem(this.key)
      const config = raw && JSON.parse(raw)
      if (config && typeof config === "object") {
        this.enabled = config.enabled === true
        if (LOCALES.has(config.locale)) this.locale = config.locale
        if (config.source === "auto" || CHROME_LOCALES.has(config.source)) this.source = config.source
      }
    } catch (_) { /* Blocked local storage must never block the chat. */ }
  }

  persist() {
    try {
      localStorage.setItem(this.key, JSON.stringify({
        enabled: this.enabled, locale: this.locale, source: this.source
      }))
    } catch (_) { /* Browsing works without persistence. */ }
  }

  renderPreference() {
    if (this.hasToggleTarget) this.toggleTarget.checked = this.enabled
    if (this.hasLocaleTarget) this.localeTarget.value = this.locale
    if (this.hasSourceTarget) this.sourceTarget.value = this.source
    this.updateSummary()
    this.status(this.enabled ? "Перевод включён. Проверяем возможности браузера…" : "Перевод выключен.")
  }

  toggle() {
    this.enabled = this.toggleTarget.checked
    this.generation += 1
    this.restoreOriginals()
    this.persist()
    this.updateSummary()
    if (this.enabled) {
      // User gesture: may authorize Chrome to download local language models.
      this.activate(true)
    } else {
      this.status("Перевод выключен. Все сообщения показаны в оригинале.")
    }
  }

  changeLocale() {
    const next = this.localeTarget.value
    if (!LOCALES.has(next)) return
    this.locale = next
    this.generation += 1
    this.restoreOriginals()
    this.persist()
    if (this.enabled) this.activate(true)
  }

  changeSource() {
    const next = this.sourceTarget.value
    if (next !== "auto" && !CHROME_LOCALES.has(next)) return
    this.source = next
    this.generation += 1
    this.restoreOriginals()
    this.persist()
    if (this.enabled) this.activate(true)
  }

  updateSummary() {
    if (!this.hasSummaryStateTarget) return
    this.summaryStateTarget.textContent = this.enabled ? "Включён" : "Выключен"
    this.summaryStateTarget.dataset.enabled = String(this.enabled)
  }

  status(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  async activate(fromUserGesture) {
    if (!this.enabled) return
    if (!globalThis.Translator?.create) {
      this.status("Браузер не поддерживает локальный AI-перевод. Сообщения остаются в оригинале.")
      return
    }
    if (!CHROME_LOCALES.has(this.locale)) {
      this.status("Для выбранного языка нет браузерной модели. Оригиналы сохранены; облачный перевод не включён.")
      return
    }

    // Initiate pack loading synchronously from a user action when source is
    // explicitly known. Auto source detection may require user interaction
    // on the first use of a newly downloaded language pack.
    if (this.source !== "auto" && this.source !== this.locale && fromUserGesture) {
      this.getTranslator(this.source, this.locale).catch(() => {})
    }
    if (this.source === "auto" && !this.detector) {
      if (!globalThis.LanguageDetector?.create) {
        this.status("Автоопределение языка здесь недоступно. Выберите язык отправителя в дополнительных настройках.")
        return
      }
      try {
        this.detector = await globalThis.LanguageDetector.create()
      } catch (_) {
        this.status("Для определения языка может понадобиться загрузка модели. Включите перевод повторно.")
        return
      }
    }

    this.status("Перевод активен в этом браузере. Новые сообщения будут обрабатываться автоматически.")
    this.schedule()
  }

  schedule() {
    if (!this.enabled || !this.messageList) return
    if (this.running) {
      this.needsAnotherPass = true
      return
    }
    this.process()
  }

  async process() {
    this.running = true
    const generation = this.generation
    try {
      do {
        this.needsAnotherPass = false
        const incoming = [...this.messageList.querySelectorAll(
          ".sd-message:not(.sd-message--own) [data-message-readable]"
        )].slice(-MAX_VISIBLE)

        for (const item of incoming) {
          if (!this.enabled || generation !== this.generation || !this.element.isConnected) return
          if (item.dataset.translatedFor === this.locale + ":" + this.source) continue
          item.dataset.translatedFor = this.locale + ":" + this.source
          await this.translateItem(item, generation)
        }
      } while (this.needsAnotherPass && this.enabled && generation === this.generation)
    } finally {
      this.running = false
      if (this.needsAnotherPass && this.enabled) this.schedule()
    }
  }

  async translateItem(item, generation) {
    const original = item.querySelector("[data-message-original]")
    if (!original || !this.enabled) return
    const plain = original.textContent.trim()
    if (!plain || plain.length > MAX_CHARS) return
    if (this.source === "auto" && plain.length < 12) return

    let source = this.source
    if (source === "auto") {
      try {
        const detected = await this.detector?.detect(plain)
        if (!Array.isArray(detected) || !detected[0] ||
            detected[0].confidence < 0.60) return
        source = detected[0].detectedLanguage?.split("-")[0]?.toLowerCase()
      } catch (_) {
        return
      }
    }
    if (!CHROME_LOCALES.has(source) || source === this.locale) return
    try {
      const session = await this.getTranslator(source, this.locale)
      const translated = await session.translate(plain)
      if (!this.enabled || generation !== this.generation ||
          !item.isConnected || typeof translated !== "string" ||
          !translated.trim() || translated.length > MAX_CHARS * 3) return

      const surface = document.createElement("div")
      surface.className = "sd-incoming-translated"
      const text = document.createElement("div")
      text.className = "sd-incoming-translated__text"
      text.textContent = translated
      text.lang = this.locale
      const badge = document.createElement("span")
      badge.className = "sd-incoming-translated__badge"
      badge.textContent = "Перевод · " + source.toUpperCase() + " → " + this.locale.toUpperCase()
      surface.append(text, badge)

      const details = document.createElement("details")
      details.className = "sd-incoming-original"
      const summary = document.createElement("summary")
      summary.textContent = "Оригинал · " + source.toUpperCase()
      details.append(summary, original)
      item.append(surface, details)
    } catch (_) {
      // Never imply success, modify originals or silently dispatch a paid API.
      if (this.enabled && generation === this.generation) {
        this.status("Часть сообщений не переведена: языковая пара недоступна или модель ещё не загружена. Оригиналы доступны.")
      }
    }
  }

  async getTranslator(source, target) {
    const key = source + ":" + target
    if (this.sessions.has(key)) return this.sessions.get(key)
    // Create immediately: Chrome requires a direct user activation to fetch
    // a missing language pack. Awaiting availability() before create() loses
    // that gesture. Unsupported pairs reject and leave the original visible.
    const promise = Promise.resolve(globalThis.Translator.create({
      sourceLanguage: source, targetLanguage: target
    }))
    this.sessions.set(key, promise)
    try {
      return await promise
    } catch (error) {
      this.sessions.delete(key)
      throw error
    }
  }

  restoreOriginals() {
    if (!this.messageList) return
    for (const item of this.messageList.querySelectorAll("[data-message-readable]")) {
      const details = item.querySelector(".sd-incoming-original")
      const original = details?.querySelector("[data-message-original]")
      if (original) item.prepend(original)
      details?.remove()
      item.querySelector(".sd-incoming-translated")?.remove()
      delete item.dataset.translatedFor
    }
  }
}
