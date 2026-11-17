# Rubylode Argo CD: app health and sync from Argo CD for Redmine
# Copyright (C) 2026  Nick Gorbikoff
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require_relative "../test_helper"

class RubylodeArgocd::SettingsPageTest < Redmine::IntegrationTest
  include RubylodeArgocdTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles

  SETTINGS_PATH = "/settings/plugin/redmine_rubylode_argocd".freeze
  SECRET_TOKEN = "super.secret.argocd.token-DO-NOT-LEAK".freeze
  SET_VARIABLE = "ARGOCD_SETTINGS_TEST_SET".freeze
  UNSET_VARIABLE = "ARGOCD_SETTINGS_TEST_UNSET".freeze

  setup do
    configure_plugin
    ENV[SET_VARIABLE] = SECRET_TOKEN
    ENV.delete(UNSET_VARIABLE)
  end

  teardown do
    ENV.delete(SET_VARIABLE)
  end

  def good_settings(overrides = {})
    configure_defaults = Redmine::Plugin.find(PLUGIN_ID).settings[:default]
    configure_defaults.merge("instances" => "Production | https://argocd.example.com | #{SET_VARIABLE}\nStaging | https://staging.example.com | #{UNSET_VARIABLE}",
                             "apps_to_show" => "Production | billing-api | Billing").merge(overrides)
  end

  def saved
    Setting.send(:"plugin_#{PLUGIN_ID}")
  end

  def assert_refused(overrides, message_pattern)
    post SETTINGS_PATH, params: { settings: good_settings(overrides) }

    assert_response :unprocessable_entity
    assert_select "#errorExplanation li", text: message_pattern
    assert_equal "", saved["instances"], "nothing was saved"
  end

  test "saving valid instance and app lines stores them as plugin settings" do
    log_user("admin", "admin")
    post SETTINGS_PATH, params: { settings: good_settings("instances" => "# the clusters\n\nProduction | https://argocd.example.com | #{SET_VARIABLE}") }

    assert_redirected_to SETTINGS_PATH
    assert_equal ["Production"], RubylodeArgocd::Settings.current.instances.map(&:name)
    assert_equal({ "billing-api" => "Billing" }, RubylodeArgocd::Settings.current.apps_to_show_for("Production"))
  end

  test "each bad instance line is refused with its line number" do
    log_user("admin", "admin")
    assert_refused({ "instances" => "Production | https://argocd.example.com" }, /Instances, line 1: needs 3 fields/)
    assert_refused({ "instances" => "# note\nProduction | ftp://argocd.example.com | #{SET_VARIABLE}" }, /Instances, line 2: the address must start with http:\/\/ or https:\/\//)
    assert_refused({ "instances" => "Production | http://argocd.example.com | #{SET_VARIABLE}" }, /Instances, line 1: .*Allow plain http/)
    assert_refused({ "instances" => "Production | https://argocd.example.com | SECRET_KEY_BASE" }, /Instances, line 1: .*ARGOCD_/)
    assert_refused({ "instances" => " | https://argocd.example.com | #{SET_VARIABLE}" }, /Instances, line 1: the name is empty/)
    assert_refused({ "instances" => "Production | https://a.example.com | ARGOCD_A\nProduction | https://b.example.com | ARGOCD_B" },
                   /Instances, line 2: .*Production.* already used/)
  end

  test "plain http is accepted when the box is checked, and for localhost" do
    log_user("admin", "admin")
    post SETTINGS_PATH, params: { settings: good_settings("instances" => "Production | http://argocd.svc | #{SET_VARIABLE}", "allow_plain_http" => "1") }
    assert_redirected_to SETTINGS_PATH

    post SETTINGS_PATH, params: { settings: good_settings("instances" => "Production | http://localhost:8080 | #{SET_VARIABLE}") }
    assert_redirected_to SETTINGS_PATH
  end

  test "an apps to show line naming an unknown instance is refused" do
    log_user("admin", "admin")
    assert_refused({ "apps_to_show" => "Production | billing-api\nQa | web | Web" }, /Apps to show, line 2: no instance named Qa/)
    assert_refused({ "apps_to_show" => "Production" }, /Apps to show, line 1: needs at least 2 fields/)
  end

  test "cache, failure cache and timeout outside their bounds are refused" do
    log_user("admin", "admin")
    assert_refused({ "cache_seconds" => "-1" }, /Cache seconds must be a whole number of at least 0/)
    assert_refused({ "failure_cache_seconds" => "soon" }, /Failure cache seconds must be a whole number of at least 0/)
    assert_refused({ "timeout_seconds" => "0" }, /Timeout seconds must be a whole number of at least 1/)
  end

  test "the page says whether each token variable is set and never shows a value" do
    configure_plugin("instances" => good_settings["instances"] + "\nOther | https://o.example.com | SECRET_KEY_BASE")
    log_user("admin", "admin")
    get SETTINGS_PATH

    assert_response :success
    assert_select ".rubylode-argocd-variable-state li", 3
    assert_select ".rubylode-argocd-variable-state li", text: /Production: #{SET_VARIABLE} is set in the environment/
    assert_select ".rubylode-argocd-variable-state li", text: /Staging: #{UNSET_VARIABLE} is not set in the environment/
    assert_select ".rubylode-argocd-variable-state li", text: /Other: .*not allowed/
    assert_not_includes response.body, SECRET_TOKEN
  end

  test "the page has every setting and the placements" do
    log_user("admin", "admin")
    get SETTINGS_PATH

    %w[instances allow_plain_http apps_to_show cache_seconds failure_cache_seconds timeout_seconds block_title visibility
       show_on_welcome_page welcome_page_column show_on_my_page show_on_project_overview project_overview_column
       show_on_matching_pages matching_page_paths show_in_top_menu].each do |field|
      assert_select "[name=?]", "settings[#{field}]"
    end
    assert_select "h3", text: "Show the block on"
    assert_select "body", text: /arrive in a later release/, count: 0
  end

  test "saving clears the cache, so the next page load asks Argo CD again" do
    use_memory_cache
    server = start_fake_argocd
    log_user("admin", "admin")
    get "/status/argocd"
    get "/status/argocd"
    assert_equal 1, server.seen_requests.count { |seen| seen[:path] == "/api/v1/applications" }

    post SETTINGS_PATH, params: { settings: Setting.send(:"plugin_#{PLUGIN_ID}") }
    get "/status/argocd"
    assert_equal 2, server.seen_requests.count { |seen| seen[:path] == "/api/v1/applications" }
  ensure
    stop_fake_argocd
    restore_cache
  end

  test "someone who is not an administrator cannot open or save the settings" do
    log_user("jsmith", "jsmith")
    get SETTINGS_PATH
    assert_response :forbidden
    post SETTINGS_PATH, params: { settings: good_settings }
    assert_equal "", saved["instances"]
  end

  test "the validation patch is applied to the settings controller" do
    assert SettingsController.include?(RubylodeArgocd::SettingsControllerPatch)
  end

  test "an address with credentials, a query or a fragment is refused with its line number" do
    log_user("admin", "admin")
    assert_refused({ "instances" => "Production | https://user:pass@argocd.example.com | #{SET_VARIABLE}" }, /Instances, line 1: .*without a user name, a query or a fragment/)
    assert_refused({ "instances" => "# note\nProduction | https://argocd.example.com?x=1 | #{SET_VARIABLE}" }, /Instances, line 2: .*without a user name, a query or a fragment/)
    assert_refused({ "instances" => "Production | https://argocd.example.com/#top | #{SET_VARIABLE}" }, /Instances, line 1: .*without a user name, a query or a fragment/)
  end

  test "only the value the checkbox posts, 1, turns Allow plain http on" do
    log_user("admin", "admin")
    assert_refused({ "instances" => "Production | http://argocd.svc | #{SET_VARIABLE}", "allow_plain_http" => "true" }, /Allow plain http/)
    assert_equal false, RubylodeArgocd::Settings.new("allow_plain_http" => "true").allow_plain_http?
    assert_equal true, RubylodeArgocd::Settings.new("allow_plain_http" => "1").allow_plain_http?
  end
end
