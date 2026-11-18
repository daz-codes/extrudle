import { Controller } from "@hotwired/stimulus"

// Loads the chosen spec's details (read-only) into a Turbo frame next to the select.
export default class extends Controller {
  static targets = ["select", "frame"]
  static values = { url: String }

  load() {
    const id = this.selectTarget.value
    if (id) {
      this.frameTarget.src = this.urlValue.replace("__ID__", id)
    } else {
      this.frameTarget.removeAttribute("src")
      this.frameTarget.innerHTML = ""
    }
  }
}
