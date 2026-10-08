import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "grindfolio-activity-panel"

export default class extends Controller {
  static targets = ["list", "tab", "panel"]

  connect() {
    let selected = "build"
    try {
      selected = sessionStorage.getItem(STORAGE_KEY) || selected
    } catch {}

    if (!this.panelTargets.some((panel) => panel.dataset.activityKey === selected)) selected = "build"

    this.listTarget.setAttribute("role", "tablist")
    this.activate(selected)
  }

  select(event) {
    event.preventDefault()
    this.activate(event.currentTarget.dataset.activityKey)
  }

  navigate(event) {
    const tabs = this.tabTargets
    const index = tabs.indexOf(event.currentTarget)
    let next

    switch (event.key) {
      case "ArrowRight": next = (index + 1) % tabs.length; break
      case "ArrowLeft": next = (index + tabs.length - 1) % tabs.length; break
      case "Home": next = 0; break
      case "End": next = tabs.length - 1; break
      default: return
    }

    event.preventDefault()
    this.activate(tabs[next].dataset.activityKey)
    tabs[next].focus()
  }

  activate(key) {
    this.tabTargets.forEach((tab) => {
      const selected = tab.dataset.activityKey === key
      tab.setAttribute("role", "tab")
      tab.setAttribute("aria-selected", String(selected))
      tab.tabIndex = selected ? 0 : -1
      tab.querySelector(".activity-selector-hint").textContent = selected ? "Viewing" : "View"
    })

    this.panelTargets.forEach((panel) => {
      panel.setAttribute("role", "tabpanel")
      panel.setAttribute("aria-labelledby", `${panel.dataset.activityKey}_activity_tab`)
      panel.tabIndex = 0
      panel.hidden = panel.dataset.activityKey !== key
    })

    try {
      sessionStorage.setItem(STORAGE_KEY, key)
    } catch {}
  }
}
