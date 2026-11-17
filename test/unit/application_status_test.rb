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
end
