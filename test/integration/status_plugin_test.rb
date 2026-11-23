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

class RubylodeArgocdStatusPluginTest < Redmine::IntegrationTest
  include RubylodeArgocdTestHelpers

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles, :issue_statuses, :trackers,
           :projects_trackers, :enumerations, :enabled_modules

  SETTINGS_PATH = "/settings/plugin/redmine_rubylode_argocd".freeze
  NOTICE_INSTALLED = "Rubylode Status is installed, so this block shows on the Status page.".freeze
  NOTICE_MISSING = "Install Rubylode Status to see this with the other status blocks on one page.".freeze

  setup do
    use_memory_cache
    start_fake_argocd
  end

  teardown do
    stop_fake_argocd
    restore_cache
  end

  test "the page and the settings page tell a missing Status plugin to be installed, with a link" do
    log_user("admin", "admin")
    [SETTINGS_PATH, "/status/argocd"].each do |path|
      get path

      assert_select "p.rubylode-status-notice", text: NOTICE_MISSING
      assert_select "p.rubylode-status-notice a[href=?]", "https://github.com/rubylode/redmine-rubylode-status", text: "Rubylode Status"
    end
  end

  test "with the Status plugin there the notice says the block is on the Status page" do
    log_user("admin", "admin")
    with_fake_status_registry do
      [SETTINGS_PATH, "/status/argocd"].each do |path|
        get path

        assert_select "p.rubylode-status-notice", text: NOTICE_INSTALLED
        assert_select "p.rubylode-status-notice a[href=?]", "/status", text: "Status page"
      end
    end
  end

  test "without the Status plugin the top menu item shows when asked for" do
    configure_plugin("instances" => "Production | #{@fake_argocd.url} | #{TOKEN_VARIABLE}", "show_in_top_menu" => "1")
    log_user("jsmith", "jsmith")
    get "/"

    assert_select "#top-menu a[href=?]", "/status/argocd", text: "Applications"
  end

  test "with the Status plugin the top menu item is gone even when asked for" do
    configure_plugin("instances" => "Production | #{@fake_argocd.url} | #{TOKEN_VARIABLE}", "show_in_top_menu" => "1")
    log_user("jsmith", "jsmith")
    with_fake_status_registry do
      get "/"

      assert_select "#top-menu a[href=?]", "/status/argocd", count: 0
    end
  end

  test "on the Status page the partial draws the table and leaves the title and the summary to the page" do
    User.current = User.find(2)
    html = ApplicationController.render(partial: "rubylode_argocd/status", locals: { widget: Object.new, status: Object.new }, assigns: {}, formats: [:html])

    assert_includes html, "rubylode-argocd-table"
    refute_includes html, "rubylode-argocd-summary"
    refute_includes html, "rubylode-argocd-title"
  ensure
    User.current = nil
  end

  test "on the Status page the partial also draws the link to Argo CD" do
    User.current = User.find(2)
    html = ApplicationController.render(partial: "rubylode_argocd/status", locals: { widget: Object.new, status: Object.new }, assigns: {}, formats: [:html])

    assert_includes html, "rubylode-argocd-source-link"
    assert_includes html, "Open Argo CD"
  ensure
    User.current = nil
  end
end
