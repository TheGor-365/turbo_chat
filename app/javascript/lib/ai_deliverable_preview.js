// Rendering never interprets model HTML, URLs, scripts or arbitrary Markdown
// links. Only server-verified message IDs become same-room navigation.
function appendInline(parent, line, links, roomPath) {
  const pieces = String(line).split(/(\*\*[^*\n]+\*\*|\x60[^\x60\n]+\x60|\*[^*\n]+\*|\[M[1-9]\d{0,17}\])/g)
  for (const item of pieces) {
    let node
    if (/^\*\*[^*\n]+\*\*$/.test(item)) {
      node = document.createElement("strong")
      node.textContent = item.slice(2, -2)
    } else if (/^\x60[^\x60\n]+\x60$/.test(item)) {
      node = document.createElement("code")
      node.textContent = item.slice(1, -1)
    } else if (/^\*[^*\n]+\*$/.test(item)) {
      node = document.createElement("em")
      node.textContent = item.slice(1, -1)
    } else {
      const match = item.match(/^\[M([1-9]\d{0,17})\]$/)
      const href = match && safeSourceLink(links[match[1]], roomPath, match[1])
      if (href) {
        node = document.createElement("a")
        node.href = href
        node.target = "_blank"
        node.rel = "noopener noreferrer"
        node.dataset.turbo = "false"
        node.className = "sd-ai-preview-citation"
        node.setAttribute("aria-label", "Open source message M" + match[1] + " in a new tab")
        node.textContent = item
      } else {
        node = document.createTextNode(item)
      }
    }
    parent.append(node)
  }
}

function safeSourceLink(value, roomPath, id) {
  if (typeof value !== "string" || !roomPath) return null
  try {
    const room = new URL(roomPath, document.baseURI)
    const candidate = new URL(value, document.baseURI)
    if (candidate.origin !== room.origin || candidate.pathname !== room.pathname ||
        candidate.hash || candidate.searchParams.size !== 1 ||
        candidate.searchParams.get("focus") !== String(id)) return null
    return candidate.pathname + candidate.search
  } catch (_) {
    return null
  }
}

export function renderDeliverablePreview(container, sourcesContainer, text, sourceLinks, roomPath) {
  const links = sourceLinks && typeof sourceLinks === "object" &&
    !Array.isArray(sourceLinks) ? sourceLinks : {}
  const root = document.createDocumentFragment()
  let list = null
  let listKind = null
  let codeLines = null
  for (const line of String(text).replace(/\r\n?/g, "\n").split("\n")) {
    if (codeLines) {
      if (/^\x60{3}\s*$/.test(line)) {
        const pre = document.createElement("pre")
        const code = document.createElement("code")
        code.textContent = codeLines.join("\n")
        pre.append(code)
        root.append(pre)
        codeLines = null
      } else {
        codeLines.push(line)
      }
      continue
    }
    if (/^\x60{3}[a-zA-Z0-9_-]*\s*$/.test(line)) {
      list = null
      listKind = null
      codeLines = []
      continue
    }
    const unordered = line.match(/^ {0,3}[-*]\s+(.+)$/)
    const ordered = line.match(/^ {0,3}\d{1,2}[.)]\s+(.+)$/)
    if (unordered || ordered) {
      const kind = unordered ? "ul" : "ol"
      if (!list || listKind !== kind) {
        list = document.createElement(kind)
        root.append(list)
        listKind = kind
      }
      const li = document.createElement("li")
      appendInline(li, (unordered || ordered)[1], links, roomPath)
      list.append(li)
      continue
    }
    list = null
    listKind = null
    if (!line.trim()) continue
    const heading = line.match(/^ {0,3}(#{1,3})\s+(.+)$/)
    const node = document.createElement(heading ? ["h4", "h5", "h6"][heading[1].length - 1] : "p")
    appendInline(node, heading ? heading[2] : line, links, roomPath)
    root.append(node)
  }
  if (codeLines) {
    const pre = document.createElement("pre")
    const code = document.createElement("code")
    code.textContent = codeLines.join("\n")
    pre.append(code)
    root.append(pre)
  }
  container.replaceChildren(root)

  const nav = document.createDocumentFragment()
  Object.keys(links).filter(id => /^[1-9]\d{0,17}$/.test(id)).slice(0, 9).forEach(id => {
    const href = safeSourceLink(links[id], roomPath, id)
    if (!href) return
    const link = document.createElement("a")
    link.href = href
    link.target = "_blank"
    link.rel = "noopener noreferrer"
    link.dataset.turbo = "false"
    link.className = "sd-ai-preview-source"
    link.setAttribute("aria-label", "View source message M" + id + " in a new tab")
    link.textContent = "M" + id
    nav.append(link)
  })
  sourcesContainer.replaceChildren(nav)
  sourcesContainer.hidden = sourcesContainer.childElementCount === 0
}
