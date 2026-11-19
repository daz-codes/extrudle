import { Controller } from "@hotwired/stimulus"

// Focuses an input when it appears, including after a Turbo Stream replaces
// the form (the autofocus attribute only works on a full page load).
export default class extends Controller {
  connect() {
    this.element.focus()
  }
}
