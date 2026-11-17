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

class RubylodeArgocdFailingResourcesTest < Redmine::IntegrationTest
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

  def tree_requests
    @fake_argocd.seen_requests.select { |seen| seen[:path].end_with?("/resource-tree") }
  end

  def degraded_applications(count)
    items = (1..count).map do |number|
      { "metadata" => { "name" => format("app-%02d", number), "namespace" => "argocd" },
        "spec" => { "project" => "default" },
        "status" => { "health" => { "status" => "Degraded" }, "sync" => { "status" => "Synced", "revision" => "abcdef0123" } } }
    end
    { "items" => items }
  end

  test "the failing pod and its message are listed under the app row" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_select "tr.rubylode-argocd-row:has(a[href$=?]) li.rubylode-argocd-resource", "/applications/argocd/billing-api", 2
    assert_select "li.rubylode-argocd-resource",
                  text: "Pod billing-api-741212b8be-vxl2q Degraded: " \
                        "back-off 5m0s restarting failed container=app pod=billing-api-741212b8be-vxl2q"
  end

  test "an app in another namespace is asked for its tree with appNamespace, one in argocd without" do
    log_user("admin", "admin")
    get "/status/argocd"

    queries = tree_requests.to_h { |seen| [seen[:path], seen[:query]] }
    assert_equal({ "appNamespace" => "team-apps" }, queries["/api/v1/applications/job-runner/resource-tree"])
    assert_equal({}, queries["/api/v1/applications/billing-api/resource-tree"])
    assert_equal ["Bearer fake.argocd.token-not-a-secret"], tree_requests.map { |seen| seen[:authorization] }.uniq
  end

  test "only apps that are not Healthy are asked for their tree" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_equal %w[/api/v1/applications/billing-api/resource-tree /api/v1/applications/job-runner/resource-tree
                    /api/v1/applications/notifications/resource-tree],
                 tree_requests.map { |seen| seen[:path] }.sort
  end

  test "with 12 Degraded apps only 10 trees are asked for and the other two say the detail was skipped" do
    @fake_argocd.applications_answer = degraded_applications(12)

    log_user("admin", "admin")
    get "/status/argocd"

    assert_equal 10, tree_requests.size
    assert_select "tbody tr.rubylode-argocd-row", 12
    assert_select ".rubylode-argocd-note", text: "Detail skipped: too many apps need a look", count: 2
  end

  test "a failing tree call leaves that app with its managed resources and the rest of the instance renders" do
    @fake_argocd.failing_tree_apps = ["billing-api"]

    log_user("admin", "admin")
    get "/status/argocd"

    assert_response :success
    assert_select ".rubylode-argocd-unavailable", 0
    assert_select "tbody tr.rubylode-argocd-row", 13
    assert_select "li.rubylode-argocd-resource", text: /billing-api-741212b8be-vxl2q/, count: 0
    assert_select ".rubylode-argocd-note", 0
    assert_select "li.rubylode-argocd-resource", text: "Deployment job-runner-deployment Missing"
  end

  test "a second look within the cache time makes no calls at all, trees included" do
    log_user("admin", "admin")
    get "/status/argocd"
    first_count = @fake_argocd.seen_requests.size
    get "/status/argocd"

    assert_equal 4, first_count
    assert_equal first_count, @fake_argocd.seen_requests.size
    assert_select "li.rubylode-argocd-resource", text: /billing-api-741212b8be-vxl2q/
  end
end
