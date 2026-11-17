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

class RubylodeArgocdStatusPageTest < Redmine::IntegrationTest
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

  test "an administrator sees one row per app, each name linked to the app in the Argo CD UI" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_response :success
    assert_select "tbody tr", 13
    assert_select "tr td.rubylode-argocd-name a[href=?]", "#{@fake_argocd.url}/applications/argocd/billing-api", text: "billing-api"
    assert_select "tr td.rubylode-argocd-name a[href=?]", "#{@fake_argocd.url}/applications/team-apps/job-runner", text: "job-runner"
    assert_select "tr td.rubylode-argocd-health", text: "Degraded"
    assert_select "tr td.rubylode-argocd-sync", text: "OutOfSync"
    assert_select "tr td.rubylode-argocd-revision", text: "38b95bf"
    assert_select "tr td.rubylode-argocd-revision", text: "3 sources"
  end

  test "the call to Argo CD carries the token from the named variable and asks only for the fields the page uses" do
    log_user("admin", "admin")
    get "/status/argocd"

    request = @fake_argocd.seen_requests.find { |seen| seen[:path] == "/api/v1/applications" }
    assert_equal "Bearer fake.argocd.token-not-a-secret", request[:authorization]
    assert_equal "items.metadata.name,items.metadata.namespace,items.spec.project,items.spec.sources," \
                 "items.status.health,items.status.sync.status,items.status.sync.revision," \
                 "items.status.operationState.finishedAt,items.status.resources",
                 request[:query]["fields"]
  end

  test "a token variable that does not start with ARGOCD_ is never read or sent" do
    ENV["REDMINE_SECRET_FOR_TEST"] = "must-not-leave-redmine"
    configure_plugin("instances" => "Production | #{@fake_argocd.url} | REDMINE_SECRET_FOR_TEST")

    log_user("admin", "admin")
    begin
      get "/status/argocd"
    rescue RubylodeArgocd::ArgocdClient::Unavailable
      # Until slice 3 gives the instance a "status unavailable" section, the refusal surfaces as this error.
    end

    assert_empty @fake_argocd.seen_requests
  ensure
    ENV.delete("REDMINE_SECRET_FOR_TEST")
  end

  test "a second look within the cache time is answered without asking Argo CD again" do
    log_user("admin", "admin")
    get "/status/argocd"
    get "/status/argocd"

    assert_response :success
    assert_select "tbody tr", 13
    assert_equal 1, @fake_argocd.seen_requests.count { |seen| seen[:path] == "/api/v1/applications" }
  end
end
