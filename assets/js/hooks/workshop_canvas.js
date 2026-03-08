/**
 * WorkshopCanvas -- interactive team builder canvas.
 *
 * Manages draggable agent nodes, spawn hierarchy links, and communication
 * rule links on an SVG-backed canvas. State lives in LiveView; the hook
 * renders from pushed data and pushes user interactions back.
 */

const CAP_COLORS = {
  builder:     { dot: '#22d3ee', badge: 'obs-badge-cyan',   abbr: 'BLD' },
  scout:       { dot: '#34d399', badge: 'obs-badge-green',  abbr: 'SCT' },
  reviewer:    { dot: '#fbbf24', badge: 'obs-badge-amber',  abbr: 'REV' },
  lead:        { dot: '#a78bfa', badge: 'obs-badge-violet', abbr: 'LEAD' },
  coordinator: { dot: '#818cf8', badge: 'obs-badge-indigo', abbr: 'COORD' },
}

function esc(s) {
  const d = document.createElement('div')
  d.textContent = s
  return d.innerHTML
}

export default {
  mounted() {
    this.state = {
      agents: [],
      spawnLinks: [],
      commRules: [],
      selectedAgent: null,
      dragAgent: null,
      dragOffset: { x: 0, y: 0 },
      linkStart: null,
      linkType: null,
      linkTemp: null,
    }

    this.canvas = this.el.querySelector('.ws-canvas')
    this.svg = this.el.querySelector('.ws-lines')

    // Receive state from LiveView
    this.handleEvent('ws_state', (data) => {
      this.state.agents = data.agents || []
      this.state.spawnLinks = data.spawn_links || []
      this.state.commRules = data.comm_rules || []
      this.state.selectedAgent = data.selected_agent
      this.render()
    })

    // Mouse handlers on canvas
    this.canvas.addEventListener('mousemove', (e) => this.onMouseMove(e))
    document.addEventListener('mouseup', (e) => this.onMouseUp(e))

    this.render()
  },

  destroyed() {
    // Cleanup handled by GC
  },

  render() {
    const canvas = this.canvas
    // Remove old nodes
    canvas.querySelectorAll('.agent-node').forEach(n => n.remove())

    this.state.agents.forEach(a => {
      const c = CAP_COLORS[a.capability] || CAP_COLORS.builder
      const el = document.createElement('div')
      el.className = `agent-node${a.id === this.state.selectedAgent ? ' selected' : ''}`
      el.style.left = a.x + 'px'
      el.style.top = a.y + 'px'
      el.dataset.id = a.id

      el.innerHTML = `
        <div class="node-header">
          <span class="node-dot" style="background:${c.dot}"></span>
          <span class="node-name">${esc(a.name)}</span>
          <span class="node-badge ${c.badge}">${c.abbr}</span>
        </div>
        <div class="node-body">
          <div class="node-field"><span class="nf-label">model</span><span class="nf-value" style="color:#818cf8">${a.model}</span></div>
          <div class="node-field"><span class="nf-label">permission</span><span class="nf-value">${a.permission || 'default'}</span></div>
          ${a.persona ? `<div class="node-field"><span class="nf-label">persona</span><span class="nf-value" style="max-width:120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${esc((a.persona || '').substring(0,30))}${(a.persona||'').length>30?'...':''}</span></div>` : ''}
        </div>
        <div class="node-ports">
          <div style="display:flex;align-items:center;gap:4px;">
            <span class="port spawn-port" data-port="spawn" data-agent="${a.id}" title="Drag to set spawn child"></span>
            <span style="font-size:8px;color:#71717a;">spawns</span>
          </div>
          <div style="display:flex;align-items:center;gap:4px;">
            <span style="font-size:8px;color:#71717a;">comms</span>
            <span class="port comm-port" data-port="comm" data-agent="${a.id}" title="Drag to set comm target"></span>
          </div>
        </div>`

      // Node click/drag
      el.addEventListener('mousedown', (e) => {
        if (e.target.classList.contains('port')) return
        this.pushEvent('ws_select_agent', { id: a.id })
        this.state.dragAgent = a.id
        this.state.dragOffset = { x: e.clientX - a.x, y: e.clientY - a.y }
        el.classList.add('dragging')
        e.preventDefault()
      })

      // Port drag start
      el.querySelectorAll('.port').forEach(port => {
        port.addEventListener('mousedown', (e) => {
          const aid = parseInt(port.dataset.agent)
          this.state.linkStart = aid
          this.state.linkType = port.dataset.port
          const rect = canvas.getBoundingClientRect()
          this.state.linkTemp = {
            x: e.clientX - rect.left + canvas.scrollLeft,
            y: e.clientY - rect.top + canvas.scrollTop
          }
          e.stopPropagation()
          e.preventDefault()
        })
      })

      canvas.appendChild(el)
    })

    this.renderLines()
  },

  renderLines() {
    const svg = this.svg
    let paths = ''

    const defs = `<defs>
      <marker id="ag" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6" fill="rgba(52,211,153,0.6)"/></marker>
      <marker id="ac" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6" fill="rgba(34,211,238,0.5)"/></marker>
      <marker id="ar" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6" fill="rgba(248,113,113,0.5)"/></marker>
      <marker id="av" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto"><path d="M0,0 L8,3 L0,6" fill="rgba(167,139,250,0.5)"/></marker>
    </defs>`

    // Spawn links (emerald, solid)
    this.state.spawnLinks.forEach(l => {
      const f = this.state.agents.find(a => a.id === l.from)
      const t = this.state.agents.find(a => a.id === l.to)
      if (!f || !t) return
      const fx = f.x + 15, fy = f.y + 95, tx = t.x + 15, ty = t.y
      const mid = (fy + ty) / 2
      paths += `<path d="M${fx},${fy} C${fx},${mid} ${tx},${mid} ${tx},${ty}" stroke="rgba(52,211,153,0.5)" stroke-width="2" fill="none" marker-end="url(#ag)"/>`
    })

    // Comm rules
    this.state.commRules.forEach(r => {
      const f = this.state.agents.find(a => a.id === r.from)
      const t = this.state.agents.find(a => a.id === r.to)
      if (!f || !t) return
      const fx = f.x + 190, fy = f.y + 70, tx = t.x + 10, ty = t.y + 70
      const mx = (fx + tx) / 2
      if (r.policy === 'allow') {
        paths += `<path d="M${fx},${fy} C${mx},${fy} ${mx},${ty} ${tx},${ty}" stroke="rgba(34,211,238,0.4)" stroke-width="1.5" fill="none" stroke-dasharray="4,3" marker-end="url(#ac)"/>`
      } else if (r.policy === 'deny') {
        paths += `<path d="M${fx},${fy-10} C${mx},${fy-10} ${mx},${ty-10} ${tx},${ty-10}" stroke="rgba(248,113,113,0.4)" stroke-width="1.5" fill="none" stroke-dasharray="2,4" marker-end="url(#ar)"/>`
      } else if (r.policy === 'route') {
        const v = r.via ? this.state.agents.find(a => a.id === r.via) : null
        if (v) {
          const vx = v.x + 100, vy = v.y + 45
          paths += `<path d="M${fx},${fy+10} L${vx},${vy}" stroke="rgba(167,139,250,0.4)" stroke-width="1.5" fill="none" stroke-dasharray="4,3" marker-end="url(#av)"/>`
          paths += `<path d="M${vx},${vy} L${tx},${ty+10}" stroke="rgba(167,139,250,0.4)" stroke-width="1.5" fill="none" stroke-dasharray="4,3" marker-end="url(#av)"/>`
        } else {
          paths += `<path d="M${fx},${fy+10} C${mx},${fy+10} ${mx},${ty+10} ${tx},${ty+10}" stroke="rgba(167,139,250,0.4)" stroke-width="1.5" fill="none" stroke-dasharray="4,3" marker-end="url(#av)"/>`
        }
      }
    })

    // Temp line while drawing
    if (this.state.linkStart && this.state.linkTemp) {
      const f = this.state.agents.find(a => a.id === this.state.linkStart)
      if (f) {
        const isSpawn = this.state.linkType === 'spawn'
        const fx = f.x + (isSpawn ? 15 : 190), fy = f.y + (isSpawn ? 95 : 70)
        const color = isSpawn ? 'rgba(52,211,153,0.3)' : 'rgba(34,211,238,0.3)'
        paths += `<line x1="${fx}" y1="${fy}" x2="${this.state.linkTemp.x}" y2="${this.state.linkTemp.y}" stroke="${color}" stroke-width="2" stroke-dasharray="4,4"/>`
      }
    }

    svg.innerHTML = defs + paths
  },

  onMouseMove(e) {
    const canvas = this.canvas
    const rect = canvas.getBoundingClientRect()

    if (this.state.dragAgent) {
      const a = this.state.agents.find(a => a.id === this.state.dragAgent)
      if (a) {
        a.x = Math.max(0, e.clientX - this.state.dragOffset.x)
        a.y = Math.max(0, e.clientY - this.state.dragOffset.y)
        const node = canvas.querySelector(`[data-id="${a.id}"]`)
        if (node) { node.style.left = a.x + 'px'; node.style.top = a.y + 'px' }
        this.renderLines()
      }
      return
    }

    if (this.state.linkStart) {
      this.state.linkTemp = {
        x: e.clientX - rect.left + canvas.scrollLeft,
        y: e.clientY - rect.top + canvas.scrollTop
      }
      this.renderLines()
    }
  },

  onMouseUp(e) {
    const canvas = this.canvas

    if (this.state.dragAgent) {
      const a = this.state.agents.find(a => a.id === this.state.dragAgent)
      const node = canvas.querySelector(`[data-id="${this.state.dragAgent}"]`)
      if (node) node.classList.remove('dragging')
      if (a) {
        this.pushEvent('ws_move_agent', { id: a.id, x: a.x, y: a.y })
      }
      this.state.dragAgent = null
      return
    }

    if (this.state.linkStart) {
      const target = e.target.closest('.agent-node')
      if (target) {
        const toId = parseInt(target.dataset.id)
        if (toId !== this.state.linkStart) {
          if (this.state.linkType === 'spawn') {
            this.pushEvent('ws_add_spawn_link', { from: this.state.linkStart, to: toId })
          } else {
            this.pushEvent('ws_add_comm_rule', { from: this.state.linkStart, to: toId, policy: 'allow' })
          }
        }
      }
      this.state.linkStart = null
      this.state.linkTemp = null
      this.state.linkType = null
      this.renderLines()
    }
  }
}
