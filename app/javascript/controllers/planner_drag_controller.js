import { Controller } from "@hotwired/stimulus"

// Drag and drop on the planner board (Slice 10).
//
// Bars on the week timeline and queue rows (by their handle) can be dragged.
// The drop sends PATCH …/drop with a time ("at"), and the server decides what
// it means. A queued block, job or maintenance, is fitted in between two
// blocks and everything after it moves later (§11 Q74, Q80): on the timeline a
// line marks the join it will go in, named in its label, worked out from the
// queue value the way the server does (before the first other queued block
// whose midpoint is after the time under the pointer). A locked block is
// pinned at a new time (§11 Q75), shown by a ghost bar. Nothing is planned in
// the browser; the board comes back as a Turbo Stream.
//
// Pointer events cover mouse, pen and touch. A mouse drag starts after a few
// pixels, so a click still opens the block. On touch a bar needs a short
// press and hold, so the timeline can still be scrolled sideways; the queue's
// handles have touch-action: none and drag at once.
//
// Held near the top or bottom of the window the page scrolls, and near either
// side of the timeline it scrolls sideways, so a drag can reach anywhere. It
// waits a moment first, so passing an edge or dropping near one doesn't scroll.
const SLOT_MS = 30 * 60 * 1000
const HOLD_MS = 350
const MOVE_PX = 6
const EDGE_PX = 48
const SCROLL_PX = 12
const EDGE_WAIT_MS = 300

const timeFormat = new Intl.DateTimeFormat("en-GB", {
  weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Europe/London"
})

export default class extends Controller {
  static targets = ["form", "at", "track", "bar", "row", "scroller"]
  static values = { queue: Array }

  connect() {
    this.onMove = this.move.bind(this)
    this.onUp = this.up.bind(this)
    this.onTouchMove = this.blockScroll.bind(this)
    this.onContextMenu = (event) => this.pending && event.preventDefault()
  }

  disconnect() {
    this.cancel()
  }

  // pointerdown on a bar or a queue handle.
  press(event) {
    // A mouse can't press twice without letting go, so a press still pending
    // lost its release (an alert, or let go outside the window): drop it.
    if (this.pending?.mouse && event.pointerType === "mouse") this.cancel()
    // One pointer at a time (a second finger mid-hold is ignored), and none
    // while a drop is still saving: its time would be read off the old board.
    if (!this.hasFormTarget || this.pending || this.submitting || event.button > 0) return

    const handle = event.currentTarget
    const row = handle.closest("tr")
    this.pending = {
      handle, row, source: row || handle, pointerId: event.pointerId,
      x: event.clientX, y: event.clientY, touch: event.pointerType === "touch" && !row, mouse: event.pointerType === "mouse"
    }
    if (this.pending.touch) this.holdTimer = setTimeout(() => this.begin(event), HOLD_MS)

    window.addEventListener("pointermove", this.onMove)
    window.addEventListener("pointerup", this.onUp)
    window.addEventListener("pointercancel", this.onUp)
    window.addEventListener("touchmove", this.onTouchMove, { passive: false })
    window.addEventListener("contextmenu", this.onContextMenu)
  }

  move(event) {
    const pending = this.pending
    if (!pending || event.pointerId !== pending.pointerId) return
    if (pending.mouse && event.buttons === 0) return this.cancel() // the release was lost

    if (!this.drag) {
      const moved = Math.hypot(event.clientX - pending.x, event.clientY - pending.y) > MOVE_PX
      if (!moved) return
      if (pending.touch) return this.cancel() // moved before the hold: the finger is scrolling
      this.begin(event)
    }
    this.pointer = { clientX: event.clientX, clientY: event.clientY }
    this.over(this.pointer)
  }

  up(event) {
    if (!this.pending || event.pointerId !== this.pending.pointerId) return
    const drag = this.drag
    if (drag && event.type === "pointerup") {
      this.swallowNextClick()
      if (drag.at && drag.at !== drag.from) return this.submit(drag.url, drag.at)
    }
    this.cancel()
  }

  cancelOnEscape(event) {
    if (event.key !== "Escape" || !this.pending) return
    const dragging = this.drag
    this.cancel()
    // Letting go over the bar afterwards mustn't open it.
    if (dragging) window.addEventListener("pointerup", () => this.swallowNextClick(), { capture: true, once: true })
  }

  // turbo:submit-end. A successful drop replaces the board (and this
  // controller); a failed one leaves it, so let it take drags again.
  submitted() {
    this.submitting = false
    this.element.removeAttribute("aria-busy")
  }

  // Private

  over(point) {
    if (this.drag.row) return this.overRow(point)
    this.drag.pin ? this.overTimeline(point) : this.overInsert(point)
  }

  // While dragging, scroll when the pointer has rested near the window's top
  // or bottom, or near either side of the timeline, then re-read what's under it.
  autoScroll(now) {
    if (!this.drag) return
    const [dx, dy] = this.pointer ? this.edgeDirection(this.pointer) : [0, 0]
    if (!dx && !dy) {
      this.edgeSince = null
    } else if (!this.edgeSince) {
      this.edgeSince = now
    } else if (now - this.edgeSince >= EDGE_WAIT_MS) {
      const scrollY = window.scrollY
      window.scrollBy(0, dy * SCROLL_PX)
      let scrolled = window.scrollY !== scrollY
      if (dx) {
        const left = this.scrollerTarget.scrollLeft
        this.scrollerTarget.scrollLeft += dx * SCROLL_PX
        scrolled ||= this.scrollerTarget.scrollLeft !== left
      }
      if (scrolled) this.over(this.pointer)
    }
    this.frame = requestAnimationFrame((time) => this.autoScroll(time))
  }

  // -1, 0 or 1 across (timeline bars only) and down.
  edgeDirection({ clientX: x, clientY: y }) {
    const dy = y < EDGE_PX ? -1 : y > window.innerHeight - EDGE_PX ? 1 : 0
    let dx = 0
    if (!this.drag.row && this.hasScrollerTarget) {
      const rect = this.scrollerTarget.getBoundingClientRect()
      dx = x < rect.left + EDGE_PX ? -1 : x > rect.right - EDGE_PX ? 1 : 0
    }
    return [dx, dy]
  }

  begin(event) {
    const { handle, row, source } = this.pending
    clearTimeout(this.holdTimer)
    this.drag = { url: handle.dataset.dropUrl, row, source }
    source.classList.add("drag-source")
    document.documentElement.classList.add("planner-dragging")
    this.edgeSince = null
    this.frame = requestAnimationFrame((time) => this.autoScroll(time))

    if (!row && handle.dataset.locked !== "true") {
      this.drag.id = Number(handle.dataset.blockId)
      this.ghost = document.createElement("div")
      this.ghost.className = "timeline-insert"
      this.ghost.innerHTML = '<span class="timeline-ghost-label"></span>'
      this.overInsert(event)
    } else if (!row) {
      this.drag.pin = true
      const startsAt = Date.parse(handle.dataset.startsAt)
      const pointerAt = this.timeAt(this.pending.x, this.pending.y) // where it was picked up
      this.drag.minutes = Number(handle.dataset.minutes)
      this.drag.from = new Date(startsAt).toISOString()
      // Keep the bar's start the same distance from the pointer as where it was picked up.
      this.drag.offset = pointerAt ? Math.floor((pointerAt - startsAt) / SLOT_MS) * SLOT_MS : 0
      this.ghost = document.createElement("div")
      this.ghost.className = "timeline-ghost"
      this.ghost.innerHTML = '<span class="timeline-ghost-label"></span>'
      this.overTimeline(event)
    }
  }

  // The bar's new start: the slot under the pointer, less the offset it was picked up at.
  overTimeline(event) {
    const pointerAt = this.timeAt(event.clientX, event.clientY)
    if (pointerAt === null) return this.clearTarget()

    const start = pointerAt - this.drag.offset
    const track = this.trackTargets.find((t) => start >= this.dayStart(t) && start < this.dayEnd(t))
    if (!track) return this.clearTarget()

    const slots = Number(track.dataset.slots)
    const from = Math.round((start - this.dayStart(track)) / SLOT_MS)
    const span = Math.max(1, Math.min(Math.ceil(this.drag.minutes * 60000 / SLOT_MS), slots - from))
    this.ghost.style.gridColumn = `${from + 1} / span ${span}`
    this.ghost.firstChild.textContent = timeFormat.format(start)
    if (this.ghost.parentElement !== track) track.append(this.ghost)
    this.drag.at = new Date(start).toISOString()
  }

  // Where a queued block dropped here would go: between the two queued blocks
  // either side of the time under the pointer, by the server's midpoint rule.
  overInsert(event) {
    const pointerAt = this.timeAt(event.clientX, event.clientY)
    if (pointerAt === null) return this.clearTarget()

    const queue = this.queueValue
    const others = queue.filter((b) => b.id !== this.drag.id)
    const index = others.findIndex((b) => this.midpoint(b) > pointerAt)
    const before = index === -1 ? others.at(-1) : others[index - 1]
    const after = index === -1 ? null : others[index]
    if (!before && !after) return this.clearTarget()

    const here = queue.findIndex((b) => b.id === this.drag.id)
    const unchanged = queue[here - 1]?.id === before?.id && queue[here + 1]?.id === after?.id
    const join = after ? Date.parse(after.startsAt) : this.endOf(before)
    const where = !before ? `First, before ${after.label}` : !after ? `Last, after ${before.label}` : `Between ${before.label} and ${after.label}`
    this.placeInsert(join, pointerAt, unchanged ? `Stays here: ${where.toLowerCase()}` : `${where} · ${timeFormat.format(join)}`)
    this.drag.at = unchanged ? null : new Date(pointerAt).toISOString()
  }

  // The line goes on the join if it's on this week, or else just the label
  // goes under the pointer.
  placeInsert(join, pointerAt, label) {
    let track = this.trackTargets.find((t) => join >= this.dayStart(t) && join < this.dayEnd(t))
    let column, atEnd = false
    if (track) {
      column = Math.round((join - this.dayStart(track)) / SLOT_MS) + 1
    } else if ((track = this.trackTargets.find((t) => join === this.dayEnd(t)))) {
      column = Number(track.dataset.slots)
      atEnd = true
    } else {
      track = this.trackTargets.find((t) => pointerAt >= this.dayStart(t) && pointerAt < this.dayEnd(t))
      column = Math.round((pointerAt - this.dayStart(track)) / SLOT_MS) + 1
    }
    const offWeek = !this.trackTargets.some((t) => join >= this.dayStart(t) && join <= this.dayEnd(t))
    this.ghost.classList.toggle("at-end", atEnd)
    this.ghost.classList.toggle("off-week", offWeek)
    this.ghost.style.gridColumn = `${column} / span 1`
    this.ghost.firstChild.textContent = label
    if (this.ghost.parentElement !== track) track.append(this.ghost)
  }

  midpoint(block) {
    return Date.parse(block.startsAt) + block.minutes * 30000
  }

  endOf(block) {
    return Date.parse(block.startsAt) + block.minutes * 60000
  }

  // A row dragged onto another goes before it when moving up and after it when
  // moving down. Only queued rows are targets: locked blocks and automatic
  // changeovers aren't places in the queue, so dropping there would mislead.
  overRow(event) {
    const target = document.elementFromPoint(event.clientX, event.clientY)?.closest("tr")
    this.rowTargets.forEach((r) => r.classList.remove("drop-before", "drop-after"))
    if (!target || !this.rowTargets.includes(target) || target === this.drag.row) return (this.drag.at = null)

    const rows = this.rowTargets
    const up = rows.indexOf(target) < rows.indexOf(this.drag.row)
    target.classList.add(up ? "drop-before" : "drop-after")
    // Just before the target's start, or at its end: the server puts the
    // block before the first block whose midpoint is after this time.
    this.drag.at = new Date(Date.parse(up ? target.dataset.startsAt : target.dataset.endsAt)).toISOString()
  }

  // The time at the start of the slot under the pointer, or null off the timeline.
  timeAt(x, y) {
    const track = this.trackTargets.find((t) => {
      const rect = t.getBoundingClientRect()
      return y >= rect.top - 4 && y <= rect.bottom + 4
    })
    if (!track) return null

    const rect = track.getBoundingClientRect()
    if (x < rect.left || x > rect.right) return null
    const slots = Number(track.dataset.slots)
    const slot = Math.min(slots - 1, Math.max(0, Math.floor(((x - rect.left) / rect.width) * slots)))
    return this.dayStart(track) + slot * SLOT_MS
  }

  dayStart(track) {
    return Date.parse(track.dataset.dayStart)
  }

  dayEnd(track) {
    return this.dayStart(track) + Number(track.dataset.slots) * SLOT_MS
  }

  clearTarget() {
    this.ghost?.remove()
    this.drag.at = null
  }

  submit(url, at) {
    this.formTarget.action = url
    this.atTarget.value = at
    this.submitting = true
    this.element.setAttribute("aria-busy", "true")
    this.cancel()
    this.formTarget.requestSubmit()
  }

  // Touch: once a drag has begun, the finger moves the bar, not the page.
  blockScroll(event) {
    if (this.drag && event.cancelable) event.preventDefault()
  }

  // A drag that ends over a bar (a link) mustn't also open it.
  swallowNextClick() {
    const swallow = (event) => {
      event.preventDefault()
      event.stopPropagation()
    }
    window.addEventListener("click", swallow, { capture: true, once: true })
    setTimeout(() => window.removeEventListener("click", swallow, { capture: true }), 0)
  }

  cancel() {
    clearTimeout(this.holdTimer)
    cancelAnimationFrame(this.frame)
    this.ghost?.remove()
    this.drag?.source.classList.remove("drag-source")
    this.rowTargets.forEach((r) => r.classList.remove("drop-before", "drop-after"))
    document.documentElement.classList.remove("planner-dragging")
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
    window.removeEventListener("pointercancel", this.onUp)
    window.removeEventListener("touchmove", this.onTouchMove)
    window.removeEventListener("contextmenu", this.onContextMenu)
    this.pending = this.drag = this.ghost = this.pointer = null
  }
}
