import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["activity"]

  static values = {
    url: String,
    interval: { type: Number, default: 2000 },
    maxAttempts: { type: Number, default: 30 }
  }

  initialize() {
    this.attempts = 0
  }

  connect() {
    this.isConnected = true
    this.scheduleIfActive()
  }

  disconnect() {
    this.isConnected = false
    window.clearTimeout(this.refreshTimer)
    this.abortController?.abort()
  }

  activityTargetConnected() {
    this.scheduleIfActive()
  }

  scheduleIfActive() {
    if (!this.isConnected) return

    window.clearTimeout(this.refreshTimer)
    if (!this.updateActive) return

    if (this.attempts >= this.maxAttemptsValue) {
      this.showLongRunningState()
      return
    }

    this.refreshTimer = window.setTimeout(() => this.refresh(), this.intervalValue)
  }

  async refresh() {
    if (!this.updateActive) return

    this.attempts += 1
    this.abortController = new AbortController()

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin",
        signal: this.abortController.signal
      })

      if (!response.ok) throw new Error("Activity status request failed")

      Turbo.renderStreamMessage(await response.text())
    } catch (error) {
      if (error.name === "AbortError") return
    } finally {
      this.abortController = null
      window.requestAnimationFrame(() => this.scheduleIfActive())
    }
  }

  showLongRunningState() {
    const status = this.activityTarget.querySelector("[data-github-sync-refresh-status]")
    if (!status) return

    status.textContent = "Still updating. This is taking longer than usual; you can leave this page."
    this.activityTarget.dataset.syncActive = "false"
  }

  get updateActive() {
    return this.hasActivityTarget && this.activityTarget.dataset.syncActive === "true"
  }
}
