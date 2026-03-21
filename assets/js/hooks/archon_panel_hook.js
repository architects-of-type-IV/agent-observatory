export const ArchonPanelHook = {
  mounted() {
    this.panelState = {
      position: localStorage.getItem("ichor:archon_position") || "center",
      size: parseInt(localStorage.getItem("ichor:archon_size")) || 75,
    }

    this.pushEvent("archon_panel_init", this.panelState)

    this.handleEvent("archon_panel_update", (state) => {
      Object.assign(this.panelState, state)
      this.saveState()
    })
  },

  saveState() {
    const { position, size } = this.panelState
    localStorage.setItem("ichor:archon_position", position)
    localStorage.setItem("ichor:archon_size", String(size))
  },

  destroyed() {},
}
