// Local-only instruction templates. Never persist private conversation excerpts,
// drafts or generated results. Treat browser storage as untrusted on every read.
export const MAX_TEMPLATES = 12
const CONTROL = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
const EMAIL = /\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b/i
const TOKEN = /\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|AIza[A-Za-z0-9_-]{24,})\b/

export function localTemplateKey(userId, roomId) {
  if (!/^[1-9]\d*$/.test(userId || "") || !/^[1-9]\d*$/.test(roomId || "")) return null
  return "turbo-chat:ai-instructions:v1:user:" + userId + ":room:" + roomId
}

export function validAuthorNote(value) {
  return typeof value === "string" && value.trim().length > 0 &&
    Array.from(value).length <= 700 && new TextEncoder().encode(value).length <= 2800 &&
    !CONTROL.test(value) && !EMAIL.test(value) && !TOKEN.test(value)
}

export function normalizedTemplate(name, note) {
  if (typeof name !== "string") return null
  const cleanName = name.trim()
  if (!cleanName || Array.from(cleanName).length > 60 ||
      CONTROL.test(cleanName) || !validAuthorNote(note)) return null
  return { name: cleanName, instruction: note.trim() }
}

export function readLocalTemplates(key) {
  if (!key) return null
  try {
    const raw = JSON.parse(window.localStorage.getItem(key) || "[]")
    if (!Array.isArray(raw) || raw.length > MAX_TEMPLATES) return []
    const seen = new Set()
    return raw.map(item => normalizedTemplate(item?.name, item?.instruction)).filter(item => {
      if (!item) return false
      const canonical = item.name.toLocaleLowerCase()
      if (seen.has(canonical)) return false
      seen.add(canonical)
      return true
    })
  } catch (_) {
    return null
  }
}

export function writeLocalTemplates(key, templates) {
  if (!key || !Array.isArray(templates) || templates.length > MAX_TEMPLATES ||
      templates.some(item => !normalizedTemplate(item?.name, item?.instruction))) return false
  try {
    window.localStorage.setItem(key, JSON.stringify(templates))
    return true
  } catch (_) {
    return false
  }
}
