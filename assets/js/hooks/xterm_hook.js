import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebglAddon } from "@xterm/addon-webgl"
import "@xterm/xterm/css/xterm.css"

export const XtermHook = {
  mounted() {
    const fitAddon = new FitAddon()

    this.term = new Terminal({
      theme: {
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
      fontSize: 13,
      fontFamily: "ui-monospace, 'SF Mono', 'Cascadia Code', 'Fira Code', Consolas, monospace",
      lineHeight: 1.15,
      cursorBlink: true,
      cursorStyle: "bar",
      scrollback: 5000,
      convertEol: true,
      disableStdin: true,
      allowTransparency: false,
      drawBoldTextInBrightColors: true,
    })

    this.term.loadAddon(fitAddon)
    this.term.open(this.el)

    // Try webgl renderer for better performance
    try {
      const webglAddon = new WebglAddon()
      this.term.loadAddon(webglAddon)
      webglAddon.onContextLoss(() => webglAddon.dispose())
    } catch (e) {
      // Fallback to canvas renderer silently
    }

    // Force xterm to fill container edge-to-edge with no gaps
    const xtermEl = this.el.querySelector(".xterm")
    if (xtermEl) {
      xtermEl.style.height = "100%"
      xtermEl.style.width = "100%"
      xtermEl.style.padding = "0"
    }

    // Fit immediately + after render settles
    const doFit = () => {
      if (this.el.offsetWidth > 0 && this.el.offsetHeight > 0) {
        fitAddon.fit()
      }
    }
    requestAnimationFrame(doFit)
    setTimeout(doFit, 100)
    setTimeout(doFit, 500)

    // Receive terminal data from LiveView
    this.handleEvent("terminal_output", ({ session, data }) => {
      const mySession = this.el.dataset.session
      if (!mySession || mySession === session) {
        this.term.write(data)
        // Scroll to bottom to skip empty scrollback lines
        this.term.scrollToBottom()
      }
    })

    // Auto-fit on resize
    this._ro = new ResizeObserver(() => doFit())
    this._ro.observe(this.el)

    this._fitAddon = fitAddon
  },

  destroyed() {
    if (this._ro) this._ro.disconnect()
    if (this.term) this.term.dispose()
  },
}
