import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["day", "date", "count", "message", "unit"]

  connect() {
    const selected = this.dayTargets.find((day) => day.getAttribute("aria-pressed") === "true")
    if (!selected) return

    this.updateDetails(selected)
    this.scrollSelectedIntoView(selected)
  }

  select(event) {
    this.dayTargets.forEach((day) => day.setAttribute("aria-pressed", "false"))
    event.currentTarget.setAttribute("aria-pressed", "true")
    this.updateDetails(event.currentTarget)
  }

  scrollSelectedIntoView(day) {
    if (!window.matchMedia("(max-width: 650px)").matches) return

    const calendar = day.closest(".heatmap-calendar")
    if (!calendar) return

    const dayLeft = day.offsetLeft
    const dayRight = dayLeft + day.offsetWidth
    const visibleLeft = calendar.scrollLeft
    const visibleRight = visibleLeft + calendar.clientWidth
    if (dayLeft >= visibleLeft && dayRight <= visibleRight) return

    calendar.scrollLeft = Math.max(0, dayRight - calendar.clientWidth)
  }

  updateDetails(day) {
    const state = day.dataset.state
    const count = day.dataset.count

    this.dateTarget.textContent = day.dataset.label
    this.countTarget.textContent = count
    this.unitTarget.textContent = day.dataset.unit
    this.messageTarget.textContent = day.dataset.message || (state === "untracked"
      ? "Tracking begins on the day you connect GitHub. Earlier dates are intentionally left untracked."
      : state === "future"
        ? "This date has not happened yet."
        : state === "pending"
          ? "This date is inside the tracking window but has not been synchronized yet."
          : `GitHub reported ${count} contribution${count === "1" ? "" : "s"} on this day.`)
  }
}
