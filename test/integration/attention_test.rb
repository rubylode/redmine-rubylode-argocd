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

class RubylodeArgocdAttentionPageTest < Redmine::IntegrationTest
  include RubylodeArgocdTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issue_statuses, :trackers, :projects_trackers, :enumerations, :enabled_modules

  setup do
    use_memory_cache
    start_fake_argocd
  end

  teardown do
    stop_fake_argocd
    restore_cache
  end

  def configure_production(overrides)
    configure_plugin({ "instances" => "Production | #{@fake_argocd.url} | #{TOKEN_VARIABLE}", "cache_seconds" => "60" }.merge(overrides))
  end

  test "the page opens with how many apps need attention, and those apps come first" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-summary", text: "3 of 13 need attention"
    assert_select "tbody tr:nth-of-type(1) td.rubylode-argocd-name a", text: "billing-api"
    assert_select "tbody tr:nth-of-type(2) td.rubylode-argocd-name a", text: "job-runner"
    assert_select "tbody tr:nth-of-type(3) td.rubylode-argocd-name a", text: "web"
    assert_select "tbody tr:nth-of-type(4) td.rubylode-argocd-name a", text: "auth-service"
  end

  test "Apps to show limits the page to those apps and shows their labels" do
    configure_production("apps_to_show" => "Production | billing-api | Billing\nProduction | ledger | Ledger")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select "tbody tr", 2
    assert_select "td.rubylode-argocd-name a[href=?]", "#{@fake_argocd.url}/applications/argocd/billing-api", text: "Billing"
    assert_select "td.rubylode-argocd-name a", text: "Ledger"
    assert_select ".rubylode-argocd-summary", text: "1 of 2 need attention"
  end

  test "an app in Apps to show that the instance does not have is ignored, and an administrator is told" do
    configure_production("apps_to_show" => "Production | ledger | Ledger\nProduction | no-such-app | Ghost")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select "tbody tr", 1
    assert_select ".rubylode-argocd-note", text: "Not found in Production: no-such-app"
  end

  test "a signed in person who is not an administrator is not told about an app that is not there" do
    configure_production("apps_to_show" => "Production | ledger | Ledger\nProduction | no-such-app | Ghost")

    log_user("jsmith", "jsmith")
    get "/status/argocd"

    assert_select "tbody tr", 1
    refute_includes response.body, "no-such-app"
  end

  test "by default any signed in person sees the page, and the reason an instance failed is for administrators alone" do
    @fake_argocd.failure = "server_error"

    log_user("jsmith", "jsmith")
    get "/status/argocd"

    assert_response :success
    assert_select ".rubylode-argocd-unavailable", text: "Status unavailable"
    refute_includes response.body, "Argo CD answered 500"
    assert_select ".rubylode-argocd-hint", 0
  end

  test "Administrators only turns a signed in person away" do
    configure_production("visibility" => "admins")

    log_user("jsmith", "jsmith")
    get "/status/argocd"

    assert_response :forbidden
  end

  test "Administrators only still shows the page to an administrator" do
    configure_production("visibility" => "admins")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_response :success
  end

  test "an anonymous visitor is sent to sign in, whoever the setting allows" do
    get "/status/argocd"

    assert_response :redirect
    assert_match %r{/login}, response.location
  end

  test "Block title is the heading of the page" do
    configure_production("block_title" => "Our deployments")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select "h2", text: "Our deployments"
  end

  test "the heading is Applications when no Block title is set" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_select "h2", text: "Applications"
  end
end
