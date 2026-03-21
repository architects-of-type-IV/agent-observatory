export const TerminalPanelHook = {
  mounted() {
    this.panelState = {
      position: localStorage.getItem("ichor:term_position") || "center",
      size: parseInt(localStorage.getItem("ichor:term_size")) || 50,
      visible: localStorage.getItem("ichor:term_visible") !== "false",
      split: localStorage.getItem("ichor:term_split") || "none",
      theme: localStorage.getItem("ichor:term_theme") || "ichor",
    }

    // Apply theme as data attribute (CSS drives the palette)
    this.applyTheme(this.panelState.theme)

    this.pushEvent("terminal_panel_init", this.panelState)

    this.handleEvent("terminal_panel_update", (state) => {
      Object.assign(this.panelState, state)
      if (state.theme) this.applyTheme(state.theme)
      this.saveState()
    })
  },

  applyTheme(theme) {
    // "ichor" is the default (no data-theme needed), others set the attribute
    if (theme === "ichor") {
      this.el.removeAttribute("data-theme")
    } else {
      this.el.dataset.theme = theme
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

  destroyed() {},
}
