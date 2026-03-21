export const TerminalPanelHook = {
  mounted() {
    // Restore state from localStorage
    this.panelState = {
      position: localStorage.getItem("ichor:term_position") || "bottom",
      size: parseInt(localStorage.getItem("ichor:term_size")) || 50,
      visible: localStorage.getItem("ichor:term_visible") !== "false",
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

    // Resize drag handling
    this.setupResize()
  },

  applyLayout() {
    const panel = this.el
    const { position, size, visible } = this.panelState
    const isVertical = position === "left" || position === "right"

    // Remove all position classes
    panel.classList.remove("pos-bottom", "pos-top", "pos-left", "pos-right", "pos-floating",
      "hidden-bottom", "hidden-top", "hidden-left", "hidden-right", "hidden-floating")

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
    const { position, size, visible } = this.panelState
    localStorage.setItem("ichor:term_position", position)
    localStorage.setItem("ichor:term_size", String(size))
    localStorage.setItem("ichor:term_visible", String(visible))
  },

  destroyed() {
    if (this._cleanupResize) this._cleanupResize()
  },
}
