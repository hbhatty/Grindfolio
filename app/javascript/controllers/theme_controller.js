import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "grindfolio-theme"
const EXPLICIT_THEMES = ["light", "dark"]
const THEME_LABELS = {
  system: "System",
  light: "Light",
  dark: "Dark"
}

export default class extends Controller {
  static targets = ["menu", "option", "trigger"]

  connect() {
    this.apply(this.preference)
    this.close()
  }

  toggle() {
    if (this.isOpen) {
      this.close()
    } else {
      this.open(this.selectedOptionIndex)
    }
  }

  choose(event) {
    this.apply(event.currentTarget.dataset.themeValue)
    this.close()
    this.triggerTarget.focus()
  }

  dismiss(event) {
    if (this.isOpen && !this.element.contains(event.target)) this.close()
  }

  escape(event) {
    if (!this.isOpen) return

    event.preventDefault()
    this.close()
    this.triggerTarget.focus()
  }

  triggerKeydown(event) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return

    event.preventDefault()
    this.open(event.key === "ArrowUp" ? this.optionTargets.length - 1 : 0)
  }

  optionKeydown(event) {
    if (event.key === "Tab") {
      this.close()
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.close()
      this.triggerTarget.focus()
      return
    }

    const currentIndex = this.optionTargets.indexOf(event.currentTarget)
    let nextIndex

    switch (event.key) {
      case "ArrowDown":
        nextIndex = (currentIndex + 1) % this.optionTargets.length
        break
      case "ArrowUp":
        nextIndex = (currentIndex - 1 + this.optionTargets.length) % this.optionTargets.length
        break
      case "Home":
        nextIndex = 0
        break
      case "End":
        nextIndex = this.optionTargets.length - 1
        break
      default:
        return
    }

    event.preventDefault()
    this.focusOption(nextIndex)
  }

  apply(preference) {
    const theme = EXPLICIT_THEMES.includes(preference) ? preference : "system"
    const accessibleName = `Theme: ${THEME_LABELS[theme]}`

    this.triggerTarget.setAttribute("aria-label", accessibleName)
    this.triggerTarget.title = accessibleName
    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-checked", option.dataset.themeValue === theme ? "true" : "false")
    })

    if (theme === "system") {
      document.documentElement.removeAttribute("data-theme")
      this.persist(null)
    } else {
      document.documentElement.dataset.theme = theme
      this.persist(theme)
    }
  }

  open(optionIndex) {
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.focusOption(optionIndex)
  }

  close() {
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  focusOption(index) {
    this.optionTargets[index]?.focus()
  }

  get isOpen() {
    return !this.menuTarget.hidden
  }

  get selectedOptionIndex() {
    const index = this.optionTargets.findIndex((option) => option.getAttribute("aria-checked") === "true")
    return index === -1 ? 0 : index
  }

  get preference() {
    try {
      const storedTheme = window.localStorage.getItem(STORAGE_KEY)
      return EXPLICIT_THEMES.includes(storedTheme) ? storedTheme : "system"
    } catch {
      const documentTheme = document.documentElement.dataset.theme
      return EXPLICIT_THEMES.includes(documentTheme) ? documentTheme : "system"
    }
  }

  persist(theme) {
    try {
      if (theme) {
        window.localStorage.setItem(STORAGE_KEY, theme)
      } else {
        window.localStorage.removeItem(STORAGE_KEY)
      }
    } catch {}
  }
}
