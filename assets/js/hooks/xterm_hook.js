import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebglAddon } from "@xterm/addon-webgl"
import "@xterm/xterm/css/xterm.css"
import { THEMES } from "./terminal_panel_hook"

function getTheme(name) {
  const t = THEMES[name] || THEMES.ichor
  // Return only xterm theme properties (exclude "name")
  const { name: _, ...theme } = t
  return theme
}

export const XtermHook = {
  mounted() {
    const fitAddon = new FitAddon()
    const themeName = localStorage.getItem("ichor:term_theme") || "ichor"

    this.term = new Terminal({
      theme: getTheme(themeName),
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

    // Listen for theme changes
    this.handleEvent("terminal_apply_theme", ({ theme }) => {
      this.term.options.theme = getTheme(theme)
      // Update background color on the container
      const bg = getTheme(theme).background
      this.el.style.backgroundColor = bg
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
