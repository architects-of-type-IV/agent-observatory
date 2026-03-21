// Terminal theme presets
const THEMES = {
  ichor: {
    name: "ICHOR",
    background: "#0f0f14",
    foreground: "#d4d4d8",
    cursor: "#a1a1aa",
    cursorAccent: "#0f0f14",
    selectionBackground: "rgba(99, 102, 241, 0.3)",
    selectionForeground: "#ffffff",
    black: "#18181b",
    red: "#ef4444",
    green: "#22c55e",
    yellow: "#eab308",
    blue: "#3b82f6",
    magenta: "#a855f7",
    cyan: "#06b6d4",
    white: "#d4d4d8",
    brightBlack: "#52525b",
    brightRed: "#f87171",
    brightGreen: "#4ade80",
    brightYellow: "#facc15",
    brightBlue: "#60a5fa",
    brightMagenta: "#c084fc",
    brightCyan: "#22d3ee",
    brightWhite: "#fafafa",
  },
  midnight: {
    name: "Midnight",
    background: "#0a0e14",
    foreground: "#b3b1ad",
    cursor: "#e6b450",
    cursorAccent: "#0a0e14",
    selectionBackground: "rgba(230, 180, 80, 0.15)",
    selectionForeground: "#ffffff",
    black: "#01060e",
    red: "#ea6c73",
    green: "#91b362",
    yellow: "#f9af4f",
    blue: "#53bdfa",
    magenta: "#fae994",
    cyan: "#90e1c6",
    white: "#c7c7c7",
    brightBlack: "#686868",
    brightRed: "#f07178",
    brightGreen: "#c2d94c",
    brightYellow: "#ffb454",
    brightBlue: "#59c2ff",
    brightMagenta: "#ffee99",
    brightCyan: "#95e6cb",
    brightWhite: "#ffffff",
  },
  aurora: {
    name: "Aurora",
    background: "#1a1b26",
    foreground: "#a9b1d6",
    cursor: "#c0caf5",
    cursorAccent: "#1a1b26",
    selectionBackground: "rgba(192, 202, 245, 0.15)",
    selectionForeground: "#ffffff",
    black: "#15161e",
    red: "#f7768e",
    green: "#9ece6a",
    yellow: "#e0af68",
    blue: "#7aa2f7",
    magenta: "#bb9af7",
    cyan: "#7dcfff",
    white: "#a9b1d6",
    brightBlack: "#414868",
    brightRed: "#f7768e",
    brightGreen: "#9ece6a",
    brightYellow: "#e0af68",
    brightBlue: "#7aa2f7",
    brightMagenta: "#bb9af7",
    brightCyan: "#7dcfff",
    brightWhite: "#c0caf5",
  },
  phosphor: {
    name: "Phosphor",
    background: "#0c0c0c",
    foreground: "#33ff00",
    cursor: "#33ff00",
    cursorAccent: "#0c0c0c",
    selectionBackground: "rgba(51, 255, 0, 0.15)",
    selectionForeground: "#ffffff",
    black: "#0c0c0c",
    red: "#ff0000",
    green: "#33ff00",
    yellow: "#ffff00",
    blue: "#0066ff",
    magenta: "#cc00ff",
    cyan: "#00ffff",
    white: "#d0d0d0",
    brightBlack: "#808080",
    brightRed: "#ff0000",
    brightGreen: "#33ff00",
    brightYellow: "#ffff00",
    brightBlue: "#0066ff",
    brightMagenta: "#cc00ff",
    brightCyan: "#00ffff",
    brightWhite: "#ffffff",
  },
  solarized: {
    name: "Solarized",
    background: "#002b36",
    foreground: "#839496",
    cursor: "#93a1a1",
    cursorAccent: "#002b36",
    selectionBackground: "rgba(147, 161, 161, 0.2)",
    selectionForeground: "#fdf6e3",
    black: "#073642",
    red: "#dc322f",
    green: "#859900",
    yellow: "#b58900",
    blue: "#268bd2",
    magenta: "#d33682",
    cyan: "#2aa198",
    white: "#eee8d5",
    brightBlack: "#586e75",
    brightRed: "#cb4b16",
    brightGreen: "#586e75",
    brightYellow: "#657b83",
    brightBlue: "#839496",
    brightMagenta: "#6c71c4",
    brightCyan: "#93a1a1",
    brightWhite: "#fdf6e3",
  },
  rose: {
    name: "Rose Pine",
    background: "#191724",
    foreground: "#e0def4",
    cursor: "#524f67",
    cursorAccent: "#191724",
    selectionBackground: "rgba(224, 222, 244, 0.1)",
    selectionForeground: "#e0def4",
    black: "#26233a",
    red: "#eb6f92",
    green: "#31748f",
    yellow: "#f6c177",
    blue: "#9ccfd8",
    magenta: "#c4a7e7",
    cyan: "#ebbcba",
    white: "#e0def4",
    brightBlack: "#6e6a86",
    brightRed: "#eb6f92",
    brightGreen: "#31748f",
    brightYellow: "#f6c177",
    brightBlue: "#9ccfd8",
    brightMagenta: "#c4a7e7",
    brightCyan: "#ebbcba",
    brightWhite: "#e0def4",
  },
}

export { THEMES }

export const TerminalPanelHook = {
  mounted() {
    // Restore state from localStorage
    this.panelState = {
      position: localStorage.getItem("ichor:term_position") || "bottom",
      size: parseInt(localStorage.getItem("ichor:term_size")) || 50,
      visible: localStorage.getItem("ichor:term_visible") !== "false",
      split: localStorage.getItem("ichor:term_split") || "none",
      theme: localStorage.getItem("ichor:term_theme") || "ichor",
    }

    // Push initial state to LiveView
    this.pushEvent("terminal_panel_init", this.panelState)

    // Apply initial layout
    this.applyLayout()

    // Listen for state updates from LiveView
    this.handleEvent("terminal_panel_update", (state) => {
      Object.assign(this.panelState, state)
      this.saveState()
      this.applyLayout()
    })

    // Listen for theme changes -- broadcast to all xterm instances
    this.handleEvent("terminal_theme_changed", ({ theme }) => {
      this.panelState.theme = theme
      this.saveState()
      // Theme application is handled by XtermTerminal hook via its own event
    })

    // Resize drag handling
    this.setupResize()
  },

  applyLayout() {
    const panel = this.el
    const { position, size, visible } = this.panelState
    const isVertical = position === "left" || position === "right"

    // Remove all position classes
    panel.classList.remove(
      "pos-bottom", "pos-top", "pos-left", "pos-right", "pos-floating",
      "hidden-bottom", "hidden-top", "hidden-left", "hidden-right", "hidden-floating"
    )

    panel.classList.add(`pos-${position}`)

    // Size
    panel.style.width = ""
    panel.style.height = ""
    panel.style.top = ""
    panel.style.left = ""
    panel.style.right = ""
    panel.style.bottom = ""
    panel.style.transform = ""

    if (position === "floating") {
      const w = Math.min(size * 1.2, 90)
      panel.style.width = `${w}%`
      panel.style.height = `${size}%`
      panel.style.top = "50%"
      panel.style.left = "50%"
      panel.style.transform = "translate(-50%, -50%)"
    } else if (isVertical) {
      panel.style.width = `${size}%`
    } else {
      panel.style.height = `${size}%`
    }

    // Resize handle orientation
    const rh = panel.querySelector(".resize-handle")
    if (rh) {
      rh.classList.remove("h", "v")
      rh.classList.add(isVertical ? "v" : "h")
      rh.style.display = (position === "floating") ? "none" : ""
    }

    // Hidden state
    if (!visible) {
      const hiddenClass = position === "floating" ? "hidden-floating" : `hidden-${position}`
      panel.classList.add(hiddenClass)
    }
  },

  setupResize() {
    const rh = this.el.querySelector(".resize-handle")
    if (!rh) return

    let dragging = false

    const onMouseDown = (e) => {
      e.preventDefault()
      dragging = true
      document.body.style.cursor = rh.classList.contains("v") ? "col-resize" : "row-resize"
      document.body.style.userSelect = "none"
    }

    const onMouseMove = (e) => {
      if (!dragging) return
      const rect = this.el.parentElement.getBoundingClientRect()
      const { position } = this.panelState
      let pct

      if (position === "bottom") {
        pct = ((rect.bottom - e.clientY) / rect.height) * 100
      } else if (position === "top") {
        pct = ((e.clientY - rect.top) / rect.height) * 100
      } else if (position === "left") {
        pct = ((e.clientX - rect.left) / rect.width) * 100
      } else if (position === "right") {
        pct = ((rect.right - e.clientX) / rect.width) * 100
      } else {
        return
      }

      pct = Math.max(15, Math.min(90, Math.round(pct)))
      this.panelState.size = pct
      this.applyLayout()
    }

    const onMouseUp = () => {
      if (!dragging) return
      dragging = false
      document.body.style.cursor = ""
      document.body.style.userSelect = ""
      this.saveState()
      this.pushEvent("terminal_panel_resize", { size: this.panelState.size })
    }

    rh.addEventListener("mousedown", onMouseDown)
    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("mouseup", onMouseUp)

    this._cleanupResize = () => {
      rh.removeEventListener("mousedown", onMouseDown)
      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)
    }
  },

  saveState() {
    const { position, size, visible, split, theme } = this.panelState
    localStorage.setItem("ichor:term_position", position)
    localStorage.setItem("ichor:term_size", String(size))
    localStorage.setItem("ichor:term_visible", String(visible))
    localStorage.setItem("ichor:term_split", split)
    localStorage.setItem("ichor:term_theme", theme)
  },

  destroyed() {
    if (this._cleanupResize) this._cleanupResize()
  },
}
