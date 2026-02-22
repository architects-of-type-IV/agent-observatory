// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/observatory"
import topbar from "../vendor/topbar"
import TopologyMap from "./hooks/topology_map"

let Hooks = {
  TopologyMap,
  StatePersistence: {
    mounted() {
      // Restore state from localStorage on mount
      const savedState = {
        view_mode: localStorage.getItem("observatory:view_mode"),
        filter_source_app: localStorage.getItem("observatory:filter_source_app"),
        filter_session_id: localStorage.getItem("observatory:filter_session_id"),
        filter_event_type: localStorage.getItem("observatory:filter_event_type"),
        search_feed: localStorage.getItem("observatory:search_feed"),
        search_sessions: localStorage.getItem("observatory:search_sessions"),
        selected_team: localStorage.getItem("observatory:selected_team"),
        sidebar_collapsed: localStorage.getItem("observatory:sidebar_collapsed")
      }

      // Push to LiveView to restore state
      this.pushEvent("restore_state", savedState)

      // Save state on every view mode change
      this.handleEvent("view_mode_changed", ({ view_mode }) => {
        if (view_mode) {
          localStorage.setItem("observatory:view_mode", view_mode)
        }
      })

      // Save state on filter changes
      this.handleEvent("filters_changed", (data) => {
        Object.entries(data).forEach(([key, value]) => {
          if (value === null || value === undefined || value === "") {
            localStorage.removeItem(`observatory:${key}`)
          } else {
            localStorage.setItem(`observatory:${key}`, value)
          }
        })
      })
    }
  },
  Toast: {
    mounted() {
      this.handleToast = (e) => {
        const { message, type } = e.detail
        this.showToast(message, type || "info")
      }
      window.addEventListener("phx:toast", this.handleToast)
    },
    destroyed() {
      window.removeEventListener("phx:toast", this.handleToast)
    },
    showToast(message, type) {
      const toast = document.createElement("div")
      toast.className = `pointer-events-auto px-4 py-3 rounded-lg shadow-lg border transition-all duration-300 transform translate-x-0 opacity-100 ${this.getToastClasses(type)}`
      toast.innerHTML = `
        <div class="flex items-center gap-2">
          <span class="text-sm">${this.escapeHtml(message)}</span>
        </div>
      `

      // Add to container
      this.el.appendChild(toast)

      // Animate in
      requestAnimationFrame(() => {
        toast.style.transform = "translateX(0)"
        toast.style.opacity = "1"
      })

      // Auto-dismiss after 3 seconds
      setTimeout(() => {
        toast.style.transform = "translateX(100%)"
        toast.style.opacity = "0"
        setTimeout(() => {
          if (toast.parentNode === this.el) {
            this.el.removeChild(toast)
          }
        }, 300)
      }, 3000)
    },
    getToastClasses(type) {
      switch (type) {
        case "success":
          return "bg-emerald-500/15 border-emerald-500/30 text-emerald-400"
        case "error":
          return "bg-red-500/15 border-red-500/30 text-red-400"
        case "warning":
          return "bg-amber-500/15 border-amber-500/30 text-amber-400"
        case "info":
        default:
          return "bg-blue-500/15 border-blue-500/30 text-blue-400"
      }
    },
    escapeHtml(text) {
      const div = document.createElement("div")
      div.textContent = text
      return div.innerHTML
    }
  },
  CopyToClipboard: {
    mounted() {
      this.el.addEventListener("click", () => {
        const payload = this.el.dataset.payload
        navigator.clipboard.writeText(payload).then(() => {
          const orig = this.el.textContent
          this.el.textContent = "Copied!"
          setTimeout(() => { this.el.textContent = orig }, 1500)
        })
      })
    }
  },
  BrowserNotifications: {
    mounted() {
      this.permissionGranted = false
      this.handleNotification = (e) => {
        const { title, body } = e.detail
        this.showNotification(title, body)
      }
      window.addEventListener("phx:browser_notify", this.handleNotification)
      this.requestPermission()
    },
    destroyed() {
      window.removeEventListener("phx:browser_notify", this.handleNotification)
    },
    requestPermission() {
      if (!("Notification" in window)) {
        console.log("Browser notifications not supported")
        return
      }

      if (Notification.permission === "granted") {
        this.permissionGranted = true
      } else if (Notification.permission !== "denied") {
        Notification.requestPermission().then((permission) => {
          this.permissionGranted = permission === "granted"
        })
      }
    },
    showNotification(title, body) {
      if (!this.permissionGranted) {
        return
      }

      new Notification(title, {
        body: body,
        icon: "/favicon.ico",
        badge: "/favicon.ico"
      })
    }
  },
  KeyboardShortcuts: {
    mounted() {
      this.handleKeydown = (e) => {
        // Ignore if user is typing in an input
        if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") {
          return
        }

        // ? - show shortcuts help
        if (e.key === "?" && !e.metaKey && !e.ctrlKey) {
          e.preventDefault()
          this.pushEvent("toggle_shortcuts_help", {})
          return
        }

        // f - focus search
        if (e.key === "f" && !e.metaKey && !e.ctrlKey) {
          e.preventDefault()
          const searchInput = document.querySelector('input[name="q"]')
          if (searchInput) searchInput.focus()
          return
        }

        // 1-9,0 - switch view modes
        const viewModes = ["overview", "command", "pipeline", "agents", "protocols", "feed", "tasks", "messages", "errors"]
        const numKey = parseInt(e.key)
        if (numKey >= 0 && numKey <= 9 && !e.metaKey && !e.ctrlKey) {
          const idx = numKey === 0 ? 9 : numKey - 1
          if (idx < viewModes.length) {
            e.preventDefault()
            this.pushEvent("set_view", { mode: viewModes[idx] })
          }
          return
        }

        // Escape - clear selection/filters/detail
        if (e.key === "Escape") {
          e.preventDefault()
          this.pushEvent("keyboard_escape", {})
          return
        }

        // j/k - navigate events
        if ((e.key === "j" || e.key === "k") && !e.metaKey && !e.ctrlKey) {
          e.preventDefault()
          this.pushEvent("keyboard_navigate", { direction: e.key === "j" ? "next" : "prev" })
          return
        }
      }

      window.addEventListener("keydown", this.handleKeydown)
    },
    destroyed() {
      window.removeEventListener("keydown", this.handleKeydown)
    }
  },
  ExportDropdown: {
    mounted() {
      const button = this.el.querySelector("#export-button")
      const menu = this.el.querySelector("#export-menu")

      this.toggleMenu = () => {
        menu.classList.toggle("hidden")
      }

      this.closeMenu = (e) => {
        if (!this.el.contains(e.target)) {
          menu.classList.add("hidden")
        }
      }

      button.addEventListener("click", this.toggleMenu)
      document.addEventListener("click", this.closeMenu)
    },
    destroyed() {
      const button = this.el.querySelector("#export-button")
      if (button) {
        button.removeEventListener("click", this.toggleMenu)
      }
      document.removeEventListener("click", this.closeMenu)
    }
  },
  InspectorDrawer: {
    mounted() {
      const saved = localStorage.getItem("inspector_drawer_state")
      if (saved) {
        this.pushEvent("set_inspector_size", { size: saved })
      }
      this.handleEvent("set_drawer_state", ({ size }) => {
        localStorage.setItem("inspector_drawer_state", size)
      })
    }
  },
  AutoScrollPane: {
    mounted() {
      this.el.scrollTop = this.el.scrollHeight
    },
    updated() {
      const isNearBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 100
      if (isNearBottom) {
        this.el.scrollTop = this.el.scrollHeight
      }
    }
  },
  ClearFormOnSubmit: {
    mounted() {
      const form = this.el.querySelector("form") || this.el.closest("form")
      if (form) {
        form.addEventListener("submit", () => {
          setTimeout(() => {
            form.querySelectorAll('input[type="text"]').forEach(input => {
              input.value = ""
            })
          }, 50)
        })
      }
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

