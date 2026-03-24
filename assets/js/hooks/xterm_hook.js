import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebglAddon } from "@xterm/addon-webgl"
import "@xterm/xterm/css/xterm.css"

function readThemeFromCSS(el) {
  // Walk up to #terminal-panel (or use document root) and read --term-* vars
  const panel = el.closest("#terminal-panel") || document.documentElement
  const s = getComputedStyle(panel)
  const v = (name) => s.getPropertyValue(name).trim()

  return {
    background: v("--term-bg") || "#0f0f14",
    foreground: v("--term-fg") || "#d4d4d8",
    cursor: v("--term-cursor") || "#a1a1aa",
    cursorAccent: v("--term-bg") || "#0f0f14",
    selectionBackground: v("--term-selection") || "rgba(99, 102, 241, 0.3)",
    selectionForeground: "#ffffff",
    black: v("--term-black") || "#18181b",
    red: v("--term-red") || "#ef4444",
    green: v("--term-green") || "#22c55e",
    yellow: v("--term-yellow") || "#eab308",
    blue: v("--term-blue") || "#3b82f6",
    magenta: v("--term-magenta") || "#a855f7",
    cyan: v("--term-cyan") || "#06b6d4",
    white: v("--term-white") || "#d4d4d8",
    brightBlack: v("--term-bright-black") || "#52525b",
    brightRed: v("--term-bright-red") || "#f87171",
    brightGreen: v("--term-bright-green") || "#4ade80",
    brightYellow: v("--term-bright-yellow") || "#facc15",
    brightBlue: v("--term-bright-blue") || "#60a5fa",
    brightMagenta: v("--term-bright-magenta") || "#c084fc",
    brightCyan: v("--term-bright-cyan") || "#22d3ee",
    brightWhite: v("--term-bright-white") || "#fafafa",
  }
}

export const XtermHook = {
  mounted() {
    const fitAddon = new FitAddon()
    const theme = readThemeFromCSS(this.el)

    this.term = new Terminal({
      theme,
      fontSize: 11,
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

    try {
      const webglAddon = new WebglAddon()
      this.term.loadAddon(webglAddon)
      webglAddon.onContextLoss(() => webglAddon.dispose())
    } catch (e) {
      // Fallback to canvas renderer
    }

    const xtermEl = this.el.querySelector(".xterm")
    if (xtermEl) {
      xtermEl.style.height = "100%"
      xtermEl.style.width = "100%"
      xtermEl.style.padding = "0"
    }

    const doFit = () => {
      if (this.el.offsetWidth > 0 && this.el.offsetHeight > 0) {
        fitAddon.fit()
      }
    }
    requestAnimationFrame(doFit)
    setTimeout(doFit, 100)
    setTimeout(doFit, 500)

    this.handleEvent("terminal_output", ({ session, data }) => {
      const mySession = this.el.dataset.session
      if (!mySession || mySession === session) {
        this.term.write(data)
        this.term.scrollToBottom()
      }
    })

    // Re-read theme from CSS vars when data-theme changes on #terminal-panel
    this.handleEvent("terminal_apply_theme", () => {
      // Small delay to let CSS cascade after data attribute change
      requestAnimationFrame(() => {
        const newTheme = readThemeFromCSS(this.el)
        this.term.options.theme = newTheme
        this.el.style.backgroundColor = newTheme.background
      })
    })

    this._ro = new ResizeObserver(() => {
      doFit()
      const session = this.el.dataset.session
      if (session && this.term.cols && this.term.rows) {
        this.pushEvent("terminal_resized", {
          session: session,
          cols: this.term.cols,
          rows: this.term.rows
        })
      }
    })
    this._ro.observe(this.el)
    this._fitAddon = fitAddon
  },

  destroyed() {
    if (this._ro) this._ro.disconnect()
    if (this.term) this.term.dispose()
  },
}
