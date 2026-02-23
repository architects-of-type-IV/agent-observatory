// TopologyMap -- ReactFlow-style HTML node cards + SVG bezier edges
// No canvas. No animation. Renders on data change only.

const NODE_W = 160
const NODE_H = 72
const PAD_X = 40
const PAD_Y = 24
const EDGE_CURVE = 60

const STATUS_COLORS = {
  active:           { border: '#3b82f6', bg: '#3b82f620', dot: '#3b82f6', text: '#93c5fd' },
  idle:             { border: '#52525b', bg: '#27272a80', dot: '#6b7280', text: '#a1a1aa' },
  dead:             { border: '#3f3f46', bg: '#18181b80', dot: '#52525b', text: '#71717a' },
  alert_entropy:    { border: '#ef4444', bg: '#ef444420', dot: '#ef4444', text: '#fca5a5' },
  schema_violation: { border: '#f97316', bg: '#f9731620', dot: '#f97316', text: '#fdba74' },
  blocked:          { border: '#f59e0b', bg: '#f59e0b20', dot: '#f59e0b', text: '#fcd34d' },
  success:          { border: '#3b82f6', bg: '#3b82f620', dot: '#3b82f6', text: '#93c5fd' },
  pending:          { border: '#52525b', bg: '#27272a80', dot: '#6b7280', text: '#a1a1aa' },
  failure:          { border: '#ef4444', bg: '#ef444420', dot: '#ef4444', text: '#fca5a5' },
}

const DEFAULT_COLOR = STATUS_COLORS.idle

const TopologyMap = {
  mounted() {
    this.nodes = []
    this.edges = []
    this.selectedId = null

    this.eventName = this.el.dataset.event || 'topology_update'
    this.handleEvent(this.eventName, ({ nodes, edges }) => {
      this.nodes = nodes || []
      this.edges = edges || []
      this.render()
    })

    this._resizeObserver = new ResizeObserver(() => this.render())
    this._resizeObserver.observe(this.el)

    this.render()
  },

  destroyed() {
    if (this._resizeObserver) this._resizeObserver.disconnect()
  },

  render() {
    const container = this.el
    // Clear previous render (keep the h3 title if present)
    const title = container.querySelector('.topo-title')
    container.querySelectorAll('.topo-layer').forEach(el => el.remove())

    const n = this.nodes.length

    if (n === 0) {
      const empty = document.createElement('div')
      empty.className = 'topo-layer'
      empty.style.cssText = 'display:flex;align-items:center;justify-content:center;height:120px;'
      empty.innerHTML = '<span style="color:#52525b;font:12px ui-monospace,monospace">Waiting for sessions...</span>'
      container.appendChild(empty)
      return
    }

    // Compute layout
    const positions = this.layout(n, container.clientWidth)
    const totalH = positions.height

    // SVG edge layer (behind nodes)
    const svgNS = 'http://www.w3.org/2000/svg'
    const svg = document.createElementNS(svgNS, 'svg')
    svg.classList.add('topo-layer')
    svg.style.cssText = `position:absolute;top:0;left:0;width:100%;height:${totalH}px;pointer-events:none;`
    svg.setAttribute('viewBox', `0 0 ${container.clientWidth} ${totalH}`)

    // Defs for arrow marker
    const defs = document.createElementNS(svgNS, 'defs')
    const marker = document.createElementNS(svgNS, 'marker')
    marker.setAttribute('id', 'topo-arrow')
    marker.setAttribute('viewBox', '0 0 10 6')
    marker.setAttribute('refX', '10')
    marker.setAttribute('refY', '3')
    marker.setAttribute('markerWidth', '8')
    marker.setAttribute('markerHeight', '6')
    marker.setAttribute('orient', 'auto-start-reverse')
    const arrow = document.createElementNS(svgNS, 'path')
    arrow.setAttribute('d', 'M 0 0 L 10 3 L 0 6 z')
    arrow.setAttribute('fill', '#3f3f46')
    marker.appendChild(arrow)
    defs.appendChild(marker)
    svg.appendChild(defs)

    // Draw edges as bezier curves
    const nodeIndex = new Map(this.nodes.map((nd, i) => [nd.trace_id, i]))

    this.edges.forEach(edge => {
      const si = nodeIndex.get(edge.from)
      const ti = nodeIndex.get(edge.to)
      if (si === undefined || ti === undefined) return

      const sp = positions.nodes[si]
      const tp = positions.nodes[ti]

      // Source: right center. Target: left center.
      const sx = sp.x + NODE_W
      const sy = sp.y + NODE_H / 2
      const tx = tp.x
      const ty = tp.y + NODE_H / 2

      const path = document.createElementNS(svgNS, 'path')
      const cx = Math.abs(tx - sx) * 0.4
      const d = `M ${sx} ${sy} C ${sx + cx} ${sy}, ${tx - cx} ${ty}, ${tx} ${ty}`
      path.setAttribute('d', d)
      path.setAttribute('fill', 'none')
      path.setAttribute('stroke', '#3f3f46')
      path.setAttribute('stroke-width', '1.5')
      path.setAttribute('marker-end', 'url(#topo-arrow)')
      svg.appendChild(path)
    })

    // Node layer
    const nodeLayer = document.createElement('div')
    nodeLayer.className = 'topo-layer'
    nodeLayer.style.cssText = `position:relative;height:${totalH}px;`

    this.nodes.forEach((node, i) => {
      const pos = positions.nodes[i]
      const colors = STATUS_COLORS[node.state] || DEFAULT_COLOR

      const card = document.createElement('div')
      card.style.cssText = [
        `position:absolute`,
        `left:${pos.x}px`,
        `top:${pos.y}px`,
        `width:${NODE_W}px`,
        `height:${NODE_H}px`,
        `border:1px solid ${colors.border}`,
        `background:${colors.bg}`,
        `border-radius:8px`,
        `padding:8px 10px`,
        `cursor:pointer`,
        `transition:box-shadow 0.15s ease, border-color 0.15s ease`,
        `box-shadow:${this.selectedId === node.trace_id ? `0 0 0 2px ${colors.border}40` : 'none'}`,
        `display:flex`,
        `flex-direction:column`,
        `justify-content:space-between`,
        `overflow:hidden`,
      ].join(';')

      card.addEventListener('mouseenter', () => {
        card.style.boxShadow = `0 0 0 2px ${colors.border}40`
      })
      card.addEventListener('mouseleave', () => {
        if (this.selectedId !== node.trace_id) card.style.boxShadow = 'none'
      })

      card.addEventListener('click', () => {
        this.selectedId = node.trace_id
        this.pushEvent('node_selected', { trace_id: node.trace_id })
        this.render()
      })

      // Row 1: status dot + label
      const row1 = document.createElement('div')
      row1.style.cssText = 'display:flex;align-items:center;gap:6px;'

      const dot = document.createElement('span')
      dot.style.cssText = `width:6px;height:6px;border-radius:50%;background:${colors.dot};flex-shrink:0;`
      row1.appendChild(dot)

      const label = document.createElement('span')
      label.style.cssText = `font:11px/1.2 ui-monospace,monospace;color:${colors.text};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;`
      label.textContent = node.label || shortId(node.agent_id)
      row1.appendChild(label)

      if (node.model) {
        const model = document.createElement('span')
        model.style.cssText = 'font:9px/1 ui-monospace,monospace;color:#6366f1;margin-left:auto;flex-shrink:0;'
        model.textContent = node.model
        row1.appendChild(model)
      }

      card.appendChild(row1)

      // Row 2: meta line
      const row2 = document.createElement('div')
      row2.style.cssText = 'display:flex;align-items:center;gap:6px;'

      const meta = []
      if (node.events) meta.push(`${node.events} ev`)
      if (node.duration) meta.push(node.duration)
      if (node.cwd) meta.push(node.cwd)

      const metaSpan = document.createElement('span')
      metaSpan.style.cssText = 'font:9px/1.2 ui-monospace,monospace;color:#71717a;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;'
      metaSpan.textContent = meta.join(' / ')
      row2.appendChild(metaSpan)

      card.appendChild(row2)

      // Row 3: team badge
      if (node.team) {
        const row3 = document.createElement('div')
        const badge = document.createElement('span')
        badge.style.cssText = 'font:8px/1 ui-monospace,monospace;color:#06b6d4;background:#06b6d410;padding:1px 5px;border-radius:3px;'
        badge.textContent = node.team
        row3.appendChild(badge)
        card.appendChild(row3)
      }

      nodeLayer.appendChild(card)
    })

    container.appendChild(svg)
    container.appendChild(nodeLayer)
  },

  layout(n, containerW) {
    const usable = containerW - PAD_X * 2
    const nodes = []

    if (n <= 6) {
      // Single row
      const totalW = n * NODE_W + (n - 1) * PAD_X
      const startX = Math.max(PAD_X, (containerW - totalW) / 2)
      for (let i = 0; i < n; i++) {
        nodes.push({ x: startX + i * (NODE_W + PAD_X), y: PAD_Y })
      }
      return { nodes, height: NODE_H + PAD_Y * 2 }
    }

    // Multi-row grid
    const cols = Math.min(n, Math.floor(usable / (NODE_W + PAD_X)) || 1)
    const rows = Math.ceil(n / cols)
    const totalW = cols * NODE_W + (cols - 1) * PAD_X
    const startX = Math.max(PAD_X, (containerW - totalW) / 2)

    for (let i = 0; i < n; i++) {
      const col = i % cols
      const row = Math.floor(i / cols)
      nodes.push({
        x: startX + col * (NODE_W + PAD_X),
        y: PAD_Y + row * (NODE_H + PAD_Y),
      })
    }

    return { nodes, height: rows * (NODE_H + PAD_Y) + PAD_Y }
  },
}

function shortId(id) {
  if (!id) return '?'
  return id.length > 10 ? id.slice(0, 8) + '..' : id
}

export default TopologyMap
