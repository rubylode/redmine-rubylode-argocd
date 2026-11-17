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

class RubylodeArgocdStatusWidgetTest < ActiveSupport::TestCase
  include RubylodeArgocdTestHelpers

  setup do
    use_memory_cache
    start_fake_argocd
  end

  teardown do
    stop_fake_argocd
    restore_cache
  end

  def one_application(name, health, sync)
    { "metadata" => { "name" => name, "namespace" => "argocd" }, "spec" => { "project" => "shop" },
      "status" => { "health" => { "status" => health }, "sync" => { "status" => sync, "revision" => "a1b2c3d4e5f6" } } }
  end

  test "an instance with a Degraded app is down, and the block reports the summary across instances" do
    data = RubylodeArgocd::StatusWidget.data

    assert_equal "down", data[:state]
    assert_equal "3 of 13 need attention", data[:summary]
    assert_equal [{ name: "Production", state: "down", detail: "3 need attention" }], data[:items]
  end

  test "an instance whose apps are all healthy and synced is ok" do
    @fake_argocd.applications_answer = { "items" => [one_application("web", "Healthy", "Synced")] }
    data = RubylodeArgocd::StatusWidget.data

    assert_equal "ok", data[:state]
    assert_equal "All 1 app healthy and synced", data[:summary]
    assert_equal [{ name: "Production", state: "ok", detail: nil }], data[:items]
  end

  test "an app that is only out of sync makes the instance a warning" do
    @fake_argocd.applications_answer = { "items" => [one_application("web", "Healthy", "OutOfSync"), one_application("api", "Healthy", "Synced")] }
    data = RubylodeArgocd::StatusWidget.data

    assert_equal "warning", data[:state]
    assert_equal [{ name: "Production", state: "warning", detail: "1 needs attention" }], data[:items]
  end

  test "the block reports the worst instance, and the worst instance comes first" do
    @fake_argocd.applications_answer = { "items" => [one_application("web", "Healthy", "Synced")] }
    second = FakeArgocdServer.new.start
    configure_plugin("instances" => "Staging | #{@fake_argocd.url} | #{TOKEN_VARIABLE}\nProduction | #{second.url} | #{TOKEN_VARIABLE}")
    data = RubylodeArgocd::StatusWidget.data

    assert_equal "down", data[:state]
    assert_equal %w[Production Staging], data[:items].map { |item| item[:name] }
    assert_equal %w[down ok], data[:items].map { |item| item[:state] }
  ensure
    second&.stop
  end

  test "an instance that cannot be asked is unknown, and the block is a warning when another instance is fine" do
    @fake_argocd.applications_answer = { "items" => [one_application("web", "Healthy", "Synced")] }
    configure_plugin("instances" => "Staging | #{@fake_argocd.url} | #{TOKEN_VARIABLE}\nProduction | http://127.0.0.1:1 | #{TOKEN_VARIABLE}",
                     "allow_plain_http" => "1", "timeout_seconds" => "1")
    data = RubylodeArgocd::StatusWidget.data

    assert_equal "warning", data[:state]
    assert_equal({ name: "Production", state: "unknown", detail: "Status unavailable" }, data[:items].first)
  end

  test "when no instance can be asked the block is unknown" do
    @fake_argocd.failure = "server_error"
    data = RubylodeArgocd::StatusWidget.data

    assert_equal "unknown", data[:state]
    assert_equal [{ name: "Production", state: "unknown", detail: "Status unavailable" }], data[:items]
  end

  test "without instances the block is unknown and says it is not set up" do
    configure_plugin("instances" => "")
    data = RubylodeArgocd::StatusWidget.data

    assert_equal "unknown", data[:state]
    assert_equal "Argo CD is not set up yet", data[:summary]
    assert_empty data[:items]
  end

  test "registering with the Status plugin passes the key, the page path and the settings" do
    configure_plugin("instances" => "Production | #{@fake_argocd.url} | #{TOKEN_VARIABLE}", "block_title" => "Our apps", "visibility" => "admins")
    with_fake_status_registry do |registry|
      assert RubylodeArgocd::StatusWidget.register

      call = registry.calls.fetch(0)
      assert_equal "argocd", call[:key]
      assert_equal "/status/argocd", call[:path]
      assert_equal "rubylode_argocd/status", call[:partial]
      assert_equal "Our apps", call[:title].call
      assert_equal "admins", call[:visibility].call
      assert_equal RubylodeArgocd::StatusWidget.data, call[:data].call
    end
  end

  test "registration is skipped when the Status plugin is not there" do
    refute defined?(RubylodeStatus::Registry)
    refute RubylodeArgocd::StatusWidget.register
  end

  test "the Status plugin counts as present exactly when its registry is defined" do
    refute RubylodeArgocd::StatusWidget.status_plugin_present?
    with_fake_status_registry { assert RubylodeArgocd::StatusWidget.status_plugin_present? }
    refute RubylodeArgocd::StatusWidget.status_plugin_present?
  end
end
