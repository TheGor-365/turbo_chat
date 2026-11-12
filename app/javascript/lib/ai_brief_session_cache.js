// One-tab recovery of a billable Client Brief after a browser reload.
// Not durable storage. Text stays in sessionStorage on this browser until
// expiry, explicit discard or participant consent revocation.
const TTL_MS = 30 * 60 * 1000
const PREFIX = "turbo-chat-h4-brief-v1"
const MAX_CHARS = 5000
const MAX_BYTES = 20000

export function briefSessionKey(userId, roomId) {
  if (!/^[1-9]\d*$/.test(String(userId)) ||
      !/^[1-9]\d*$/.test(String(roomId))) return null
  return [PREFIX, userId, roomId].join(":")
}

export function storeBrief(storage, key, details, now = Date.now()) {
  if (!storage || !key || !details || details.kind !== "client_brief" ||
      typeof details.text !== "string" || !details.text.trim() ||
      [...details.text].length > MAX_CHARS ||
      new TextEncoder().encode(details.text).length > MAX_BYTES) return false
  const ids = details.sourceIds
  if (!Array.isArray(ids) || !ids.length || ids.length > 9 ||
      !ids.every(id => Number.isSafeInteger(id) && id > 0)) return false
  try {
    storage.setItem(key, JSON.stringify({
      v: 1, at: now, kind: "client_brief", text: details.text,
      sourceIds: [...new Set(ids)], cost: typeof details.cost === "string" &&
        /^\d+\.\d{1,8}$/.test(details.cost) ? details.cost : null
    }))
    return true
  } catch (_) { return false }
}

export function readBrief(storage, key, now = Date.now()) {
  if (!storage || !key) return null
  try {
    const raw = storage.getItem(key)
    if (!raw) return null
    const entry = JSON.parse(raw)
    if (entry?.v !== 1 || entry.kind !== "client_brief" ||
        !Number.isFinite(entry.at) || entry.at > now ||
        now - entry.at > TTL_MS ||
        typeof entry.text !== "string" || !entry.text.trim() ||
        [...entry.text].length > MAX_CHARS ||
        new TextEncoder().encode(entry.text).length > MAX_BYTES ||
        !Array.isArray(entry.sourceIds) || !entry.sourceIds.length ||
        entry.sourceIds.length > 9 ||
        !entry.sourceIds.every(id => Number.isSafeInteger(id) && id > 0)) {
      storage.removeItem(key)
      return null
    }
    return entry
  } catch (_) {
    try { storage.removeItem(key) } catch (_) { /* storage unavailable */ }
    return null
  }
}

export function discardBrief(storage, key) {
  if (!storage || !key) return
  try { storage.removeItem(key) } catch (_) { /* best effort */ }
}
