# frozen_string_literal: true
require "test_helper"

class InterfaceLocaleTest < ActionDispatch::IntegrationTest
  test "supported interface locales persist between login and signup" do
    { "en" => ["Log in", "Sign up"], "ru" => ["Войти", "Регистрация"],
      "hy" => ["Մուտք", "Գրանցվել"], "es" => ["Iniciar sesión", "Registrarse"] }.each do |locale, labels|
      get new_user_session_path, params: { ui_locale: locale }
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-auth-heading h1", text: labels.first
      assert_select ".sd-nav__language-menu a[aria-current='page'][lang=?]", locale, count: 1
      get new_user_registration_path
      assert_response :success
      assert_select "html[lang=?]", locale
      assert_select ".sd-auth-heading h1", text: labels.last
      assert_select "form input[type=email][autocomplete=email]", count: 1
    end
  end

  test "unknown locale cannot override the browser choice" do
    get root_path, params: { ui_locale: "en" }
    get new_user_session_path, params: { ui_locale: "../../private" }
    assert_response :success
    assert_select "html[lang=en]", count: 1
    assert_select ".sd-auth-heading h1", text: "Log in"
  end

  test "locale navigation stays on the current local route" do
    get new_user_session_path
    assert_response :success
    assert_select ".sd-nav__language-menu a", count: 4
    assert_select ".sd-nav__language-menu a[lang=hy][href=?]", new_user_session_path(ui_locale: "hy"), count: 1
    assert_select ".sd-nav__language-menu a[lang=es][href=?]", new_user_session_path(ui_locale: "es"), count: 1
  end
end
