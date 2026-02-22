const TopologyMap = {
  mounted() {
    this.canvas = this.el.querySelector('canvas')
    if (this.canvas === null) {
      console.error("TopologyMap: canvas element not found")
      return
    }

    this.ctx = this.canvas.getContext('2d')
    this.nodes = []
    this.edges = []

    // Zoom and pan state
    this.scale = 1.0
    this.offsetX = 0
    this.offsetY = 0
    this.isPanning = false
    this.lastPanX = 0
    this.lastPanY = 0

    // Handle topology updates from server
    this.handleEvent("topology_update", ({nodes, edges}) => {
      this.nodes = nodes
      this.edges = edges
    })

    // Click listener
    this.canvas.addEventListener('click', this.handleClick.bind(this))

    // Zoom listener
    this.canvas.addEventListener('wheel', this.handleWheel.bind(this), { passive: false })

    // Pan listeners
    this.canvas.addEventListener('mousedown', this.handleMouseDown.bind(this))
    this.canvas.addEventListener('mousemove', this.handleMouseMove.bind(this))
    this.canvas.addEventListener('mouseup', this.handleMouseUp.bind(this))

    this.startAnimationLoop()
  },

  startAnimationLoop() {
    this._raf = requestAnimationFrame(() => {
      this.render()
      this.startAnimationLoop()
    })
  },

  destroyed() {
    cancelAnimationFrame(this._raf)
  },

  render() {
    // Initialize node positions if not set
    this.nodes.forEach(node => {
      if (node.x === null || node.x === undefined) {
        node.x = Math.random() * this.canvas.width
        node.y = Math.random() * this.canvas.height
      }
    })

    // Force-directed layout
    this.nodes.forEach((node, i) => {
      // Repulsive forces from all other nodes: F_repel = 500 / distance^2
      let frx = 0
      let fry = 0

      this.nodes.forEach((other, j) => {
        if (i !== j) {
          const dx = node.x - other.x
          const dy = node.y - other.y
          const dist = Math.hypot(dx, dy) || 1
          const force = 500 / (dist * dist)
          frx += (dx / dist) * force
          fry += (dy / dist) * force
        }
      })

      // Cap total repulsive displacement at 10px per frame to prevent explosion
      const repulsMag = Math.hypot(frx, fry)
      if (repulsMag > 10) {
        frx = (frx / repulsMag) * 10
        fry = (fry / repulsMag) * 10
      }

      // Attractive spring forces per edge: F_attract = (distance - 80) * 0.01
      let fax = 0
      let fay = 0

      this.edges.forEach(edge => {
        let other = null
        if (edge.from === node.trace_id) {
          other = this.nodes.find(n => n.trace_id === edge.to)
        } else if (edge.to === node.trace_id) {
          other = this.nodes.find(n => n.trace_id === edge.from)
        }

        if (other) {
          const dx = other.x - node.x
          const dy = other.y - node.y
          const dist = Math.hypot(dx, dy) || 1
          const force = (dist - 80) * 0.01
          fax += (dx / dist) * force
          fay += (dy / dist) * force
        }
      })

      node.x += frx + fax
      node.y += fry + fay
    })

    // Clear canvas
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)

    // Apply transformations
    this.ctx.save()
    this.ctx.translate(this.offsetX, this.offsetY)
    this.ctx.scale(this.scale, this.scale)

    // Draw edges
    this.edges.forEach(edge => {
      const sourceNode = this.nodes.find(n => n.trace_id === edge.from)
      const targetNode = this.nodes.find(n => n.trace_id === edge.to)

      if (sourceNode && targetNode) {
        edge.from_x = sourceNode.x
        edge.from_y = sourceNode.y
        edge.to_x = targetNode.x
        edge.to_y = targetNode.y

        this.ctx.strokeStyle = '#9ca3af'
        this.ctx.lineWidth = 2
        this.ctx.beginPath()
        this.ctx.moveTo(sourceNode.x, sourceNode.y)
        this.ctx.lineTo(targetNode.x, targetNode.y)
        this.ctx.stroke()
      }
    })

    // Draw nodes
    this.nodes.forEach(node => {
      const color = NODE_COLORS[node.state] || NODE_COLORS.idle

      if (node.state === 'alert_entropy') {
        this.ctx.globalAlpha = 0.5 + 0.5 * Math.sin(Date.now() / 300)
      } else {
        this.ctx.globalAlpha = 1.0
      }

      this.ctx.fillStyle = color
      this.ctx.beginPath()
      this.ctx.arc(node.x, node.y, 12, 0, Math.PI * 2)
      this.ctx.fill()
    })

    this.ctx.globalAlpha = 1.0
    this.ctx.restore()
  },

  handleClick(e) {
    const rect = this.canvas.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top

    // Transform coordinates by inverse of zoom and pan
    const canvasX = (x - this.offsetX) / this.scale
    const canvasY = (y - this.offsetY) / this.scale

    const HIT_RADIUS = 14
    const EDGE_TOLERANCE = 6

    // Check node hits first
    for (const node of this.nodes) {
      if (Math.hypot(canvasX - node.x, canvasY - node.y) <= HIT_RADIUS) {
        this.pushEvent("node_selected", { trace_id: node.trace_id })
        return
      }
    }

    // Check edge hits
    for (const edge of this.edges) {
      const dist = this.pointToSegmentDistance(
        canvasX, canvasY,
        edge.from_x || 0, edge.from_y || 0,
        edge.to_x || 0, edge.to_y || 0
      )
      if (dist <= EDGE_TOLERANCE) {
        this.pushEvent("edge_selected", {
          traffic_volume: edge.traffic_volume || 0,
          latency_ms: edge.latency_ms || 0,
          status: edge.status || "unknown"
        })
        return
      }
    }
  },

  pointToSegmentDistance(px, py, x1, y1, x2, y2) {
    const dx = x2 - x1
    const dy = y2 - y1
    const lenSq = dx * dx + dy * dy

    if (lenSq === 0) {
      return Math.hypot(px - x1, py - y1)
    }

    let t = ((px - x1) * dx + (py - y1) * dy) / lenSq
    t = Math.max(0, Math.min(1, t))

    const projX = x1 + t * dx
    const projY = y1 + t * dy

    return Math.hypot(px - projX, py - projY)
  },

  handleWheel(e) {
    e.preventDefault()

    const zoomFactor = e.deltaY > 0 ? 0.9 : 1.1
    const newScale = Math.max(0.1, Math.min(5.0, this.scale * zoomFactor))

    // Zoom toward mouse
    const rect = this.canvas.getBoundingClientRect()
    const mouseX = e.clientX - rect.left
    const mouseY = e.clientY - rect.top

    const scaleDiff = newScale - this.scale
    this.offsetX -= mouseX * scaleDiff / this.scale
    this.offsetY -= mouseY * scaleDiff / this.scale

    this.scale = newScale
  },

  handleMouseDown(e) {
    this.isPanning = true
    this.lastPanX = e.clientX
    this.lastPanY = e.clientY
  },

  handleMouseMove(e) {
    if (this.isPanning) {
      const dx = e.clientX - this.lastPanX
      const dy = e.clientY - this.lastPanY
      this.offsetX += dx
      this.offsetY += dy
      this.lastPanX = e.clientX
      this.lastPanY = e.clientY
    }
  },

  handleMouseUp(e) {
    this.isPanning = false
  }
}

// Colors match ADR-016: idle=#6b7280, active=#3b82f6, alert_entropy=#ef4444, schema_violation=#f97316, dead=#374151, blocked=#f59e0b
const NODE_COLORS = {
  idle: "#6b7280",
  active: "#3b82f6",
  alert_entropy: "#ef4444",
  schema_violation: "#f97316",
  dead: "#374151",
  blocked: "#f59e0b"
}

export default TopologyMap
