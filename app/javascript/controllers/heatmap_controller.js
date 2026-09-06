import { Controller } from "@hotwired/stimulus"

const STATUS_TONES = new Set(["positive", "progress", "negative", "neutral"])

export default class extends Controller {
  static targets = [
    "day",
    "date",
    "count",
    "message",
    "unit",
    "items",
    "applicationsSection",
    "changes",
    "changesSection"
  ]

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
    this.updateItems(day)
  }

  updateItems(day) {
    if (this.hasItemsTarget) {
      const applications = this.itemsFor(day.dataset.applications)
      this.itemsTarget.replaceChildren(...applications.map((application) => this.applicationItem(application)))
      if (this.hasApplicationsSectionTarget) this.applicationsSectionTarget.hidden = applications.length === 0
    }

    if (this.hasChangesTarget) {
      const changes = this.itemsFor(day.dataset.statusChanges)
      this.changesTarget.replaceChildren(...changes.map((change) => this.statusChangeItem(change)))
      if (this.hasChangesSectionTarget) this.changesSectionTarget.hidden = changes.length === 0
    }
  }

  itemsFor(value) {
    try {
      const items = JSON.parse(value || "[]")
      return Array.isArray(items) ? items : []
    } catch {
      return []
    }
  }

  applicationItem(application) {
    const item = document.createElement("li")
    item.className = "notion-application"

    const copy = document.createElement("div")
    copy.className = "notion-application-copy"

    const company = document.createElement("strong")
    company.textContent = application.company_name || ""
    copy.append(company)

    if (application.role) {
      const role = document.createElement("span")
      role.textContent = application.role
      copy.append(role)
    }

    item.append(copy)

    if (application.status) item.append(this.statusBadge(application.status, application.status_tone))

    return item
  }

  statusChangeItem(change) {
    const item = document.createElement("li")
    item.className = "notion-application"

    const copy = document.createElement("div")
    copy.className = "notion-application-copy"

    const company = document.createElement("strong")
    company.textContent = change.company_name || ""
    copy.append(company)

    if (change.role) {
      const role = document.createElement("span")
      role.textContent = change.role
      copy.append(role)
    }

    const fromStatus = change.from_status || "No status"
    const toStatus = change.to_status || "No status"
    const transition = document.createElement("div")
    transition.className = "notion-status-transition"
    transition.setAttribute("aria-label", `Status changed from ${fromStatus} to ${toStatus}`)

    const fromBadge = this.statusBadge(fromStatus, change.from_status_tone)
    fromBadge.setAttribute("aria-hidden", "true")
    transition.append(fromBadge)

    const arrow = document.createElement("span")
    arrow.className = "notion-status-transition-arrow"
    arrow.setAttribute("aria-hidden", "true")
    arrow.textContent = "→"
    transition.append(arrow)

    const toBadge = this.statusBadge(toStatus, change.to_status_tone)
    toBadge.setAttribute("aria-hidden", "true")
    transition.append(toBadge)

    item.append(copy, transition)
    return item
  }

  statusBadge(status, tone) {
    const badge = document.createElement("span")
    const safeTone = STATUS_TONES.has(tone) ? tone : "neutral"
    badge.className = `notion-application-status notion-application-status--${safeTone}`
    badge.textContent = status
    return badge
  }
}
