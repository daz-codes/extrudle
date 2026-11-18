require "test_helper"

class ThemePreviewTest < ActionDispatch::IntegrationTest
  test "defaults to the first theme" do
    get new_session_path
    assert_select "html[data-theme=highlighter]"
    assert_select ".theme-switcher-option[aria-pressed=true]", text: "Highlighter"
  end

  test "uses the theme cookie when it is a known theme" do
    cookies[:theme] = "lime"
    get new_session_path
    assert_select "html[data-theme=lime]"
  end

  test "ignores unknown theme cookies" do
    cookies[:theme] = "<script>"
    get new_session_path
    assert_select "html[data-theme=highlighter]"
  end
end
