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

class RubylodeArgocdApplicationStatusTest < ActiveSupport::TestCase
  def applications_answer
    JSON.parse(File.read(File.join(FakeArgocdServer::FIXTURES, "applications.json")))
  end

  def rows
    RubylodeArgocd::ApplicationStatus.rows_from(applications_answer)
  end

  test "each app in the answer becomes a row with its name, namespace, project, health, sync and last sync time" do
    billing = rows.find { |row| row.name == "billing-api" }

    assert_equal 13, rows.size
    assert_equal "argocd", billing.namespace
    assert_equal "default", billing.project
    assert_equal "Degraded", billing.health
    assert_equal "Synced", billing.sync
    assert_equal Time.utc(2026, 11, 16, 1, 36, 17), billing.finished_at
  end

  test "a single-source app shows the first seven characters of its revision" do
    billing = rows.find { |row| row.name == "billing-api" }

    assert_equal "38b95bf", billing.revision
    assert_nil billing.source_count
  end

  test "a multi-source app has no revision and counts its sources instead" do
    job_runner = rows.find { |row| row.name == "job-runner" }

    assert_nil job_runner.revision
    assert_equal 3, job_runner.source_count
    assert_equal "team-apps", job_runner.namespace
  end

  def billing_tree
    JSON.parse(File.read(File.join(FakeArgocdServer::FIXTURES, "resource_trees", "billing-api.json")))
  end

  def answer_with_resources(health, resources, name: "ledger")
    { "items" => [{ "metadata" => { "name" => name, "namespace" => "argocd" }, "spec" => { "project" => "default" },
                    "status" => { "health" => { "status" => health }, "sync" => { "status" => "Synced" }, "resources" => resources } }] }
  end

  test "failing managed resources come from the resources of the applications answer" do
    answer = answer_with_resources("Degraded", [
      { "kind" => "Deployment", "name" => "ledger", "health" => { "status" => "Degraded", "message" => "no minimum availability" } },
      { "kind" => "Service", "name" => "ledger", "health" => { "status" => "Healthy" } },
      { "kind" => "ConfigMap", "name" => "ledger-settings", "status" => "OutOfSync" },
      { "kind" => "Secret", "name" => "ledger-keys", "health" => { "status" => "Missing" } }
    ])

    failing = RubylodeArgocd::ApplicationStatus.rows_from(answer).first.failing_resources

    assert_equal [["Deployment", "ledger", "Degraded", "no minimum availability"], ["Secret", "ledger-keys", "Missing", nil]],
                 failing.map { |resource| [resource.kind, resource.name, resource.health, resource.message] }
  end

  test "the resource tree of a Degraded app adds the pod and its message" do
    answer = answer_with_resources("Degraded", [], name: "billing-api")

    failing = RubylodeArgocd::ApplicationStatus.rows_from(answer, "argocd/billing-api" => billing_tree).first.failing_resources

    assert_equal [["Deployment", "billing-api", "Degraded"], ["Pod", "billing-api-741212b8be-vxl2q", "Degraded"]],
                 failing.map { |resource| [resource.kind, resource.name, resource.health] }
    assert_equal "back-off 5m0s restarting failed container=app pod=billing-api-741212b8be-vxl2q", failing.last.message
  end

  test "a resource in both the managed list and the tree is listed once, with the tree's message" do
    answer = answer_with_resources("Degraded", [{ "kind" => "Deployment", "namespace" => "argocd", "name" => "billing-api",
                                                  "health" => { "status" => "Degraded" } }], name: "billing-api")

    failing = RubylodeArgocd::ApplicationStatus.rows_from(answer, "argocd/billing-api" => billing_tree).first.failing_resources

    assert_equal 2, failing.size
    assert_equal "Deployment \"billing-api\" exceeded its progress deadline", failing.first.message
  end

  test "a Healthy app lists no failing resources and is never marked as skipped" do
    row = RubylodeArgocd::ApplicationStatus.rows_from(answer_with_resources("Healthy", []), {}).first

    assert_empty row.failing_resources
    refute row.detail_skipped
  end

  test "an app that is not Healthy and has no tree among the trees asked for is marked as skipped" do
    row = RubylodeArgocd::ApplicationStatus.rows_from(answer_with_resources("Degraded", []), {}).first

    assert row.detail_skipped
  end

  test "an app whose tree call failed is not marked as skipped" do
    row = RubylodeArgocd::ApplicationStatus.rows_from(answer_with_resources("Degraded", []), "argocd/ledger" => nil).first

    refute row.detail_skipped
  end

  test "an answer that is a list, or whose items are not a list, has no rows" do
    assert_equal [], RubylodeArgocd::ApplicationStatus.rows_from([{ "metadata" => { "name" => "a" } }])
    assert_equal [], RubylodeArgocd::ApplicationStatus.rows_from({ "items" => { "metadata" => { "name" => "a" } } })
    assert_equal [], RubylodeArgocd::ApplicationStatus.rows_from(nil)
  end

  test "an item that is not an object is skipped and the others stay" do
    rows = RubylodeArgocd::ApplicationStatus.rows_from({ "items" => ["text", nil, 7, { "metadata" => { "name" => "alpha", "namespace" => "argocd" } }] })

    assert_equal %w[alpha], rows.map(&:name)
  end

  test "a resource or a tree node that is not an object is skipped and the others stay" do
    answer = answer_with_resources("Degraded", ["text", { "kind" => "Pod", "name" => "web", "health" => { "status" => "Degraded" } }])
    tree = { "nodes" => ["text", nil, { "kind" => "Pod", "name" => "web-2", "health" => { "status" => "Missing" } }] }
    rows = RubylodeArgocd::ApplicationStatus.rows_from(answer, { "argocd/ledger" => tree })

    assert_equal %w[web web-2], rows.first.failing_resources.map(&:name)
    assert_equal %w[web], RubylodeArgocd::ApplicationStatus.rows_from(answer, { "argocd/ledger" => { "nodes" => { "kind" => "Pod" } } }).first.failing_resources.map(&:name)
  end
end

class RubylodeArgocdAttentionTest < ActiveSupport::TestCase
  def answer_with(*apps)
    { "items" => apps.map do |name, health, sync|
      { "metadata" => { "name" => name, "namespace" => "argocd" }, "spec" => { "project" => "default" },
        "status" => { "health" => { "status" => health }, "sync" => { "status" => sync } } }
    end }
  end

  def report_of(rows, unavailable: false)
    RubylodeArgocd::ApplicationStatus::Report.new(rows: rows, unavailable: unavailable, failure_reason: nil)
  end

  test "an app needs attention when it is Degraded, Missing or Unknown, or OutOfSync, and Progressing and Suspended do not count" do
    expected = {
      ["Healthy", "Synced"] => false, ["Healthy", "OutOfSync"] => true, ["Healthy", "Unknown"] => false,
      ["Degraded", "Synced"] => true, ["Degraded", "OutOfSync"] => true,
      ["Missing", "Synced"] => true, ["Missing", "OutOfSync"] => true,
      ["Unknown", "Synced"] => true, ["Unknown", "OutOfSync"] => true,
      ["Progressing", "Synced"] => false, ["Progressing", "OutOfSync"] => true,
      ["Suspended", "Synced"] => false, ["Suspended", "OutOfSync"] => true
    }

    actual = expected.keys.to_h do |health, sync|
      row = RubylodeArgocd::ApplicationStatus.rows_from(answer_with(["app", health, sync])).first
      [[health, sync], row.needs_attention]
    end

    assert_equal expected, actual
  end

  test "rows needing attention come first, then every group by name" do
    rows = RubylodeArgocd::ApplicationStatus.rows_from(answer_with(
      ["zeta", "Healthy", "Synced"], ["beta", "Degraded", "Synced"], ["alpha", "Healthy", "Synced"], ["gamma", "Healthy", "OutOfSync"]
    ))

    assert_equal %w[beta gamma alpha zeta], rows.map(&:name)
  end

  test "the summary says all fine, or how many of the apps need attention" do
    fine = RubylodeArgocd::ApplicationStatus.rows_from(answer_with(["a", "Healthy", "Synced"], ["b", "Progressing", "Synced"]))
    mixed = RubylodeArgocd::ApplicationStatus.rows_from(answer_with(["a", "Healthy", "Synced"], ["b", "Degraded", "Synced"], ["c", "Healthy", "OutOfSync"]))

    assert_equal "All 2 apps healthy and synced", RubylodeArgocd::ApplicationStatus.summary_for([report_of(fine)]).text
    assert_equal "2 of 3 need attention", RubylodeArgocd::ApplicationStatus.summary_for([report_of(mixed)]).text
    assert_equal "2 of 5 need attention", RubylodeArgocd::ApplicationStatus.summary_for([report_of(mixed), report_of(fine)]).text
  end

  test "an unavailable instance is not counted, and the summary says so" do
    mixed = RubylodeArgocd::ApplicationStatus.rows_from(answer_with(["a", "Healthy", "Synced"], ["b", "Degraded", "Synced"]))

    summary = RubylodeArgocd::ApplicationStatus.summary_for([report_of(mixed), report_of([], unavailable: true)])

    assert_equal "1 of 2 need attention. 1 instance is unavailable and its apps are not counted.", summary.text
  end
end
