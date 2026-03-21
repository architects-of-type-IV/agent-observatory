import { Terminal } from "@xterm/xterm"
import "@xterm/xterm/css/xterm.css"

export const XtermHook = {
  mounted() {
    this.term = new Terminal({
      theme: {
        background: "#0f0f14",
        foreground: "#e0e0e8",
        cursor: "#e0e0e8",
        cursorAccent: "#0f0f14",
        black: "#1e1e1e",
        red: "#cd3131",
        green: "#0dbc79",
        yellow: "#e5e510",
        blue: "#2472c8",
        magenta: "#bc3fbc",
        cyan: "#11a8cd",
        white: "#e5e5e5",
        brightBlack: "#666666",
        brightRed: "#f14c4c",
        brightGreen: "#23d18b",
        brightYellow: "#f5f543",
        brightBlue: "#3b8eea",
        brightMagenta: "#d670d6",
        brightCyan: "#29b8db",
        brightWhite: "#e5e5e5",
      },
      fontSize: 12,
      fontFamily: "ui-monospace, 'SF Mono', 'Cascadia Code', 'Fira Code', monospace",
      cursorBlink: false,
      scrollback: 2000,
      convertEol: true,
      disableStdin: true,
    })

    this.term.open(this.el)

    // Receive terminal data from LiveView
    this.handleEvent("terminal_output", ({ session, data }) => {
      const mySession = this.el.dataset.session
      if (!mySession || mySession === session) {
        this.term.write(data)
      }
    })

    // Handle resize via ResizeObserver
    this._ro = new ResizeObserver(() => {
      if (this.term && this.el.offsetWidth > 0 && this.el.offsetHeight > 0) {
        // Compute cols/rows from pixel dimensions
        const core = this.term._core
        if (core && core._renderService) {
          const dims = core._renderService.dimensions
          if (dims && dims.css && dims.css.cell.width > 0) {
            const cols = Math.max(2, Math.floor(this.el.offsetWidth / dims.css.cell.width))
            const rows = Math.max(1, Math.floor(this.el.offsetHeight / dims.css.cell.height))
            this.term.resize(cols, rows)
          }
        }
      }
    })
    this._ro.observe(this.el)
  },

  destroyed() {
    if (this._ro) this._ro.disconnect()
    if (this.term) this.term.dispose()
  },
}
