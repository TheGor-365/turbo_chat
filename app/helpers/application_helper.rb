module ApplicationHelper
  include Pagy::Frontend

  # Locale strings are generated server-side and consumed as inert text by Stimulus.
  def theme_labels_for_ui
    { dark: :light, light: :system, system: :dark }.each_with_object({}) do |(mode, following), labels|
      names = {
        current: t("ui.nav.theme_modes.#{mode}"),
        next: t("ui.nav.theme_modes.#{following}")
      }
      labels[mode] = {
        aria: t("ui.nav.theme_aria", **names),
        title: t("ui.nav.theme_title", **names)
      }
    end
  end
end
