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

class RubylodeArgocdFailureHandlingTest < ActiveSupport::TestCase
  include RubylodeArgocdTestHelpers

  FAILURE_TOKEN_VARIABLE = "ARGOCD_FAILURE_HANDLING_TEST".freeze
  FAILURE_TOKEN = "failure-handling.token-DO-NOT-LEAK".freeze

  class UnexpectedFailure < StandardError; end

  # A cache that fails the way the test asks, on read or on write.
  class FailingCache < ActiveSupport::Cache::MemoryStore
    attr_writer :failing_on

    def initialize(failing_on:, error:)
      super()
      @failing_on = failing_on
      @error = error
    end

    def read(*arguments, **options)
      raise @error if @failing_on == :read

      super
    end

    def write(*arguments, **options)
      raise @error if @failing_on == :write

      super
    end
  end

  setup do
    use_memory_cache
    ENV[FAILURE_TOKEN_VARIABLE] = FAILURE_TOKEN
    @instance = RubylodeArgocd::Settings::Instance.new(name: "Production", address: "https://argocd.example.com",
                                                       token_variable: FAILURE_TOKEN_VARIABLE, link_address: "")
    @configuration = RubylodeArgocd::Settings.new({})
    @applications_calls = 0
  end

  teardown do
    ENV.delete(FAILURE_TOKEN_VARIABLE)
    restore_cache
  end

  def report
    RubylodeArgocd::ApplicationStatus.report_for(@instance, @configuration)
  end

  def cached
    RubylodeArgocd::ApplicationStatus.cache.read(RubylodeArgocd::ApplicationStatus.cache_key_for(@instance))
  end

  def application(name, status)
    { "metadata" => { "name" => name, "namespace" => "argocd" }, "spec" => { "project" => "default" }, "status" => status }
  end

  def healthy_answer
    { "items" => [application("billing", { "health" => { "status" => "Healthy" }, "sync" => { "status" => "Synced" } })] }
  end

  # Runs the block with ArgocdClient.new handing back a client that answers with `answer`, and whose resource-tree
  # call does what `resource_tree` does.
  def answering(answer, resource_tree: ->(**) { { "nodes" => [] } }, &block)
    test = self
    client = Object.new
    client.define_singleton_method(:applications) do
      test.instance_variable_set(:@applications_calls, test.instance_variable_get(:@applications_calls) + 1)
      answer
    end
    client.define_singleton_method(:resource_tree) { |**arguments| resource_tree.call(**arguments) }
    replacing_method(RubylodeArgocd::ArgocdClient, :new, ->(**) { client }, &block)
  end

  test "a caller's time limit is told apart by class name, subclasses included" do
    subclass = Class.new(CallerTimeLimit)

    assert_includes RubylodeArgocd::CallerDeadline.class_names, "RubylodeStatus::WidgetStatus::TookTooLong"
    refute RubylodeArgocd::CallerDeadline.raised?(CallerTimeLimit.new)
    treating_as_caller_deadline do
      assert RubylodeArgocd::CallerDeadline.raised?(CallerTimeLimit.new)
      assert RubylodeArgocd::CallerDeadline.raised?(subclass.new)
      refute RubylodeArgocd::CallerDeadline.raised?(RuntimeError.new)
    end
  end

  test "a caller's time limit inside the call to Argo CD reaches the caller and nothing is cached" do
    treating_as_caller_deadline do
      replacing_method(Net::HTTP, :new, ->(*) { raise CallerTimeLimit }) do
        assert_raises(CallerTimeLimit) { report }
      end
    end

    assert_nil cached
  end

  test "a caller's time limit while the rows are built reaches the caller and no failure is cached" do
    answering(healthy_answer) do
      treating_as_caller_deadline do
        replacing_method(RubylodeArgocd::ApplicationStatus, :rows_from, ->(*) { raise CallerTimeLimit }) do
          assert_raises(CallerTimeLimit) { report }
        end
      end
    end

    refute cached.key?(RubylodeArgocd::ApplicationStatus::FAILURE_KEY)
  end

  test "a caller's time limit while the cache is read reaches the caller and Argo CD is not asked" do
    RubylodeArgocd::ApplicationStatus.cache = FailingCache.new(failing_on: :read, error: CallerTimeLimit)

    answering(healthy_answer) do
      treating_as_caller_deadline { assert_raises(CallerTimeLimit) { report } }
    end

    assert_equal 0, @applications_calls
  end

  test "a caller's time limit while the cache is written reaches the caller and nothing is cached" do
    cache = FailingCache.new(failing_on: :write, error: CallerTimeLimit)
    RubylodeArgocd::ApplicationStatus.cache = cache

    answering(healthy_answer) do
      treating_as_caller_deadline { assert_raises(CallerTimeLimit) { report } }
    end

    cache.failing_on = nil
    assert_nil cached
  end

  test "an unexpected error inside the call to Argo CD is unavailable, named by its class, and cached without the token" do
    calls = 0
    reports = []
    log = captured_log do
      replacing_method(Net::HTTP, :new, ->(*) { calls += 1; raise TypeError, "broke while holding #{FAILURE_TOKEN}" }) do
        2.times { reports << report }
      end
    end

    assert reports.all?(&:unavailable?)
    assert_equal "Argo CD could not be reached (TypeError)", reports.first.failure_reason
    assert_equal 1, calls, "the failure is cached, so the second report does not ask again"
    assert cached.key?(RubylodeArgocd::ApplicationStatus::FAILURE_KEY)
    refute_includes cached.to_s, FAILURE_TOKEN
    refute_includes log, FAILURE_TOKEN
  end

  test "an unexpected error while the rows are built is unavailable, named by its class, and Argo CD is asked once" do
    reports = []
    log = captured_log do
      answering(healthy_answer) do
        replacing_method(RubylodeArgocd::ApplicationStatus, :rows_from, ->(*) { raise UnexpectedFailure, FAILURE_TOKEN }) do
          2.times { reports << report }
        end
      end
    end

    assert reports.all?(&:unavailable?)
    assert_equal UnexpectedFailure.name, reports.first.failure_reason
    assert_equal 1, @applications_calls
    assert_includes log, UnexpectedFailure.name
    refute_includes log, FAILURE_TOKEN
  end

  test "an unexpected error while a resource tree is asked for leaves that app without its tree" do
    answer = { "items" => [application("ledger", { "health" => { "status" => "Degraded" }, "sync" => { "status" => "Synced" } })] }

    result = answering(answer, resource_tree: ->(**) { raise TypeError, "odd tree" }) { report }

    refute result.unavailable?
    assert_equal %w[ledger], result.rows.map(&:name)
    refute result.rows.first.detail_skipped
  end

  test "an app whose status is a string or whose health is a list is shown without a health, and the others stay" do
    answer = { "items" => [application("odd-status", "x"), application("odd-health", { "health" => [] }),
                           *healthy_answer["items"]] }

    result = answering(answer) { report }

    refute result.unavailable?
    assert_equal %w[billing odd-health odd-status], result.rows.map(&:name).sort
    assert_equal ["", ""], result.rows.reject { |row| row.name == "billing" }.map(&:health)
    assert_equal 3, RubylodeArgocd::ApplicationStatus.rows_from(answer, {}).size
  end

  test "a token with a line break in it is refused as unavailable and no request is made" do
    calls = 0
    ENV[FAILURE_TOKEN_VARIABLE] = "first-half\nsecond-half"

    result = replacing_method(Net::HTTP, :new, ->(*) { calls += 1; raise "must not be reached" }) { report }

    assert result.unavailable?
    assert_equal "The token for Production contains a line break, so it is not sent", result.failure_reason
    assert_equal 0, calls
  end

  test "spaces and a line break round the token in the environment are not part of it" do
    ENV[FAILURE_TOKEN_VARIABLE] = "  #{FAILURE_TOKEN}\n"

    assert_equal FAILURE_TOKEN, @instance.token
  end
end
