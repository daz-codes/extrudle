import { Controller } from "@hotwired/stimulus"

// Design preview switcher. Stores the choice in a cookie so the server
// renders the right data-theme on the next page (no flash).
export default class extends Controller {
  static targets = ["option"]

  pick({ params: { name } }) {
    document.documentElement.dataset.theme = name
    document.cookie = `theme=${name}; path=/; max-age=31536000; samesite=lax`
    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-pressed", option.dataset.themeNameParam === name)
    })
  }
}
