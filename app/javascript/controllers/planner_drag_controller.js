import { Controller } from "@hotwired/stimulus"

// Drag and drop on the planner board (Slice 10).
//
// Bars on the week timeline can be dragged to a new start; queue rows can be
// dragged by their handle. Either way the drop sends PATCH …/drop with the new
// start time ("at"), and the server decides what that means: a queued block
// moves to that place in the queue and the line reflows (§11 Q74), a locked
// block is pinned at the new time (§11 Q75). Nothing is planned in the
// browser; the board comes back as a Turbo Stream.
//
// Pointer events cover mouse, pen and touch. A mouse drag starts after a few
// pixels, so a click still opens the block. On touch a bar needs a short
// press and hold, so the timeline can still be scrolled sideways; the queue's
// handles have touch-action: none and drag at once.
const SLOT_MS = 30 * 60 * 1000
const HOLD_MS = 350
const MOVE_PX = 6

const timeFormat = new Intl.DateTimeFormat("en-GB", {
  weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Europe/London"
})

export default class extends Controller {
  static targets = ["form", "at", "track", "bar", "row"]

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
    if (!this.hasFormTarget || this.drag || event.button > 0) return

    const handle = event.currentTarget
    const row = handle.closest("tr")
    this.pending = {
      handle, row, source: row || handle, pointerId: event.pointerId,
      x: event.clientX, y: event.clientY, touch: event.pointerType === "touch" && !row
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

    if (!this.drag) {
      const moved = Math.hypot(event.clientX - pending.x, event.clientY - pending.y) > MOVE_PX
      if (!moved) return
      if (pending.touch) return this.cancel() // moved before the hold: the finger is scrolling
      this.begin(event)
    }
    this.drag.row ? this.overRow(event) : this.overTimeline(event)
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
    if (event.key === "Escape" && this.pending) this.cancel()
  }

  // Private

  begin(event) {
    const { handle, row, source } = this.pending
    clearTimeout(this.holdTimer)
    this.drag = { url: handle.dataset.dropUrl, row, source }
    source.classList.add("drag-source")
    document.documentElement.classList.add("planner-dragging")

    if (!row) {
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

  // A row dragged onto another goes before it when moving up and after it when moving down.
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
    this.ghost?.remove()
    this.drag?.source.classList.remove("drag-source")
    this.rowTargets.forEach((r) => r.classList.remove("drop-before", "drop-after"))
    document.documentElement.classList.remove("planner-dragging")
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
    window.removeEventListener("pointercancel", this.onUp)
    window.removeEventListener("touchmove", this.onTouchMove)
    window.removeEventListener("contextmenu", this.onContextMenu)
    this.pending = this.drag = this.ghost = null
  }
}
