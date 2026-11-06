# First-party inline icon primitive. All SVG fragments are static and
# allowlisted, not derived from user input. Same stroke/grid across the UI.
module SignalDeckHelper
  ICONS = {
    "messages" => '<path d="M20 11.5A7.5 7.5 0 0 1 12.5 19H7l-4 3V11.5A7.5 7.5 0 0 1 10.5 4h2a7.5 7.5 0 0 1 7.5 7.5Z"/><path d="M8 12h7"/>',
    "user" => '<circle cx="12" cy="8" r="3.5"/><path d="M5 20v-1a7 7 0 0 1 14 0v1"/>',
    "settings" => '<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="2"/><circle cx="15" cy="17" r="2"/>',
    "sun" => '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.93 4.93l1.41 1.41m11.32 11.32 1.41 1.41M2 12h2m16 0h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>',
    "moon" => '<path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5 8.5 8.5 0 1 0 20.5 14.5Z"/>',
    "monitor" => '<rect x="3" y="4" width="18" height="14" rx="2"/><path d="M8 22h8m-4-4v4"/>',
    "log-out" => '<path d="M9 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h3"/><path d="M14 8l4 4-4 4m4-4H9"/>',
    "arrow-left" => '<path d="m12 19-7-7 7-7m-7 7h14"/>',
    "search" => '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
    "send" => '<path d="m3 11 18-8-8 18-2-8-8-2Zm8 2 10-10"/>',
    "paperclip" => '<path d="m20 11-7.5 7.5a5 5 0 0 1-7-7L13 4a3.5 3.5 0 0 1 5 5l-7.5 7.5a2 2 0 0 1-3-3L15 6"/>',
    "more" => '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    "bell" => '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9m-8 12h4"/>',
    "x" => '<path d="M18 6 6 18M6 6l12 12"/>',
    "chevron-down" => '<path d="m6 9 6 6 6-6"/>',
    "menu" => '<path d="M4 7h16M4 12h16M4 17h16"/>',
    "wifi" => '<path d="M2.5 9a15 15 0 0 1 19 0M5.5 12.5a10.5 10.5 0 0 1 13 0M9 16a5.5 5.5 0 0 1 6 0"/><circle cx="12" cy="20" r="1"/>',
    "refresh-cw" => '<path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.6 9a7 7 0 0 1 12-2L20 12M4 12l2.4 5a7 7 0 0 0 12-2"/>',
    "bell-off" => '<path d="m3 3 18 18M18 9a6 6 0 0 0-10-4M6 8c0 7-3 7-3 9h14M10 20h4"/>',
    "reply" => '<path d="m9 14-5-5 5-5M4 9h9a7 7 0 0 1 7 7v3"/>',
    "pencil" => '<path d="m4 20 4.5-1L20 7.5 16.5 4 5 15.5 4 20ZM14.5 6l3.5 3.5"/>',
    "trash" => '<path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13M10 11v6m4-6v6"/>',
    "smile" => '<circle cx="12" cy="12" r="9"/><path d="M8 14a5 5 0 0 0 8 0M9 9h.01M15 9h.01"/>',
    "camera" => '<path d="M3 7h4l2-3h6l2 3h4v13H3V7Z"/><circle cx="12" cy="13" r="4"/>',
    "play" => '<path d="m8 5 12 7-12 7V5Z"/>',
    "mic" => '<rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0m-7 7v3m-4 0h8"/>'
  }.freeze

  def sd_icon(name, size: 20)
    markup = ICONS.fetch(name.to_s) { raise ArgumentError, "Unknown Signal Deck icon" }
    tag.svg(markup.html_safe, class: "sd-icon", xmlns: "http://www.w3.org/2000/svg",
      width: size, height: size, viewBox: "0 0 24 24", fill: "none",
      stroke: "currentColor", stroke_width: 1.75,
      stroke_linecap: "round", stroke_linejoin: "round",
      "aria-hidden": "true", focusable: "false")
  end
end
