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

class RubylodeArgocdSeveralInstancesTest < Redmine::IntegrationTest
  include RubylodeArgocdTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issue_statuses, :trackers, :projects_trackers, :enumerations, :enabled_modules

  FIRST_TOKEN = "first.argocd.token-DO-NOT-LEAK".freeze
  SECOND_TOKEN = "second.argocd.token-DO-NOT-LEAK".freeze
  FIRST_VARIABLE = "ARGOCD_FIRST_TEST_TOKEN".freeze
  SECOND_VARIABLE = "ARGOCD_SECOND_TEST_TOKEN".freeze

  setup do
    use_memory_cache
    @first = FakeArgocdServer.new(token: FIRST_TOKEN).start
    @second = FakeArgocdServer.new(token: SECOND_TOKEN).start
    ENV[FIRST_VARIABLE] = FIRST_TOKEN
    ENV[SECOND_VARIABLE] = SECOND_TOKEN
    configure_two_instances
  end

  teardown do
    [FIRST_VARIABLE, SECOND_VARIABLE].each { |name| ENV.delete(name) }
    @first.stop
    @second.stop
    restore_cache
  end

  def configure_two_instances(overrides = {})
    configure_plugin({ "instances" => "Production | #{@first.url} | #{FIRST_VARIABLE}\nStaging | #{@second.url} | #{SECOND_VARIABLE}",
                       "cache_seconds" => "60" }.merge(overrides))
  end

  def applications_requests(server)
    server.seen_requests.select { |seen| seen[:path] == "/api/v1/applications" }
  end

  test "two instances give two sections in the order of the settings" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-instance", 2
    assert_select ".rubylode-argocd-instance:nth-of-type(1) h3", text: "Production"
    assert_select ".rubylode-argocd-instance:nth-of-type(2) h3", text: "Staging"
    assert_select "tbody tr", 26
  end

  test "an instance that answers 500 is unavailable alone, and only an administrator sees why" do
    @second.failure = "server_error"

    log_user("admin", "admin")
    get "/status/argocd"

    assert_response :success
    assert_select ".rubylode-argocd-instance:nth-of-type(1) tbody tr", 13
    assert_select ".rubylode-argocd-instance:nth-of-type(2) .rubylode-argocd-unavailable", text: "Status unavailable"
    assert_select ".rubylode-argocd-instance:nth-of-type(2) .rubylode-argocd-hint", text: /Argo CD answered 500/
    assert_select ".rubylode-argocd-instance:nth-of-type(2) tbody tr", 0
  end

  test "a signed in person who is not an administrator sees Status unavailable and never the reason" do
    @second.failure = "server_error"

    log_user("jsmith", "jsmith")
    get "/status/argocd"

    assert_response :success
    assert_select ".rubylode-argocd-instance:nth-of-type(2) .rubylode-argocd-unavailable", text: "Status unavailable"
    assert_select ".rubylode-argocd-hint", 0
    refute_includes response.body, "Argo CD answered 500"
  end

  test "an instance slower than the timeout is unavailable and the page still answers" do
    @second.failure = "timeout"
    @second.timeout_seconds = 3
    configure_two_instances("timeout_seconds" => "1")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_response :success
    assert_select ".rubylode-argocd-instance:nth-of-type(1) tbody tr", 13
    assert_select ".rubylode-argocd-instance:nth-of-type(2) .rubylode-argocd-unavailable", text: "Status unavailable"
  end

  test "after a failure the instance is not called again within the failure cache time" do
    @second.failure = "server_error"
    configure_two_instances("failure_cache_seconds" => "30")

    log_user("admin", "admin")
    2.times { get "/status/argocd" }

    assert_select ".rubylode-argocd-unavailable", 1
    assert_select ".rubylode-argocd-hint", text: /Argo CD answered 500/
    assert_equal 1, applications_requests(@second).size
  end

  test "a failure cache time of 0 asks the failing instance every time and a cache time of 0 asks every time" do
    @second.failure = "server_error"
    configure_two_instances("failure_cache_seconds" => "0", "cache_seconds" => "0")

    log_user("admin", "admin")
    2.times { get "/status/argocd" }

    assert_response :success
    assert_equal 2, applications_requests(@second).size
    assert_equal 2, applications_requests(@first).size
  end

  test "each token is sent only to its own instance" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_equal ["Bearer #{FIRST_TOKEN}"], applications_requests(@first).map { |seen| seen[:authorization] }
    assert_equal ["Bearer #{SECOND_TOKEN}"], applications_requests(@second).map { |seen| seen[:authorization] }
  end

  test "a redirect to another host is not followed with the token" do
    @first.redirect_to = @second.url

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-instance:nth-of-type(1) .rubylode-argocd-unavailable", text: "Status unavailable"
    assert_select ".rubylode-argocd-instance:nth-of-type(1) .rubylode-argocd-hint", text: /redirected/
    assert_equal 1, applications_requests(@second).size
    assert_equal ["Bearer #{SECOND_TOKEN}"], applications_requests(@second).map { |seen| seen[:authorization] }
  end

  test "a plain http address that is not on this machine is refused while Allow plain http is off" do
    configure_plugin("instances" => "Remote | http://argocd.example.invalid | #{FIRST_VARIABLE}")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-unavailable", text: "Status unavailable"
    assert_select ".rubylode-argocd-hint", text: /not https/
  end

  test "with Allow plain http on, a plain http address is tried" do
    configure_plugin("instances" => "Remote | http://argocd.example.invalid | #{FIRST_VARIABLE}", "allow_plain_http" => "1")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-unavailable", text: "Status unavailable"
    assert_select ".rubylode-argocd-hint", text: /could not be reached/
  end

  test "a plain http address on this machine works without Allow plain http" do
    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-unavailable", 0
  end

  test "neither token is in the page, the log or the reason, even when an instance fails" do
    @first.failure = "unauthorized"
    @second.failure = "server_error"

    log_user("admin", "admin")
    log = captured_log { get "/status/argocd" }

    assert_select ".rubylode-argocd-unavailable", 2
    [FIRST_TOKEN, SECOND_TOKEN].each do |token|
      refute_includes response.body, token
      refute_includes log, token
    end
  end

  test "a variable that is unset makes that instance unavailable with a clear reason and is never sent" do
    ENV.delete(SECOND_VARIABLE)

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-instance:nth-of-type(1) tbody tr", 13
    assert_select ".rubylode-argocd-instance:nth-of-type(2) .rubylode-argocd-hint", text: /No token for Staging/
    assert_empty @second.seen_requests
  end

  test "a variable that does not start with ARGOCD_ makes that instance unavailable and is never read" do
    ENV["REDMINE_SECRET_FOR_TEST"] = "must-not-leave-redmine"
    configure_plugin("instances" => "Production | #{@first.url} | #{FIRST_VARIABLE}\nStaging | #{@second.url} | REDMINE_SECRET_FOR_TEST")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select ".rubylode-argocd-instance:nth-of-type(1) tbody tr", 13
    assert_select ".rubylode-argocd-instance:nth-of-type(2) .rubylode-argocd-hint", text: /No token for Staging/
    assert_empty @second.seen_requests
    refute_includes response.body, "must-not-leave-redmine"
  ensure
    ENV.delete("REDMINE_SECRET_FOR_TEST")
  end

  test "an answer bigger than 10 MB is refused, and an administrator is told why" do
    @first.oversized_body_bytes = 11 * 1024 * 1024

    log_user("admin", "admin")
    get "/status/argocd"

    assert_response :success
    assert_select ".rubylode-argocd-instance:nth-of-type(1) .rubylode-argocd-unavailable", text: "Status unavailable"
    assert_select ".rubylode-argocd-hint", text: /Argo CD's answer was too large/
    assert_select ".rubylode-argocd-instance:nth-of-type(2) tbody tr", 13
  end

  test "an answer that is not what Argo CD sends is fetched once across two page loads" do
    @first.applications_body = "null"
    @second.applications_body = "[1, \"two\"]"

    log_user("admin", "admin")
    2.times { get "/status/argocd" }

    assert_response :success
    assert_equal 1, applications_requests(@first).size
    assert_equal 1, applications_requests(@second).size
  end

  test "an unexpected error while fetching is cached as a failure and logs only its class" do
    calls = 0
    exploding = Object.new
    exploding.define_singleton_method(:applications) do
      calls += 1
      raise RuntimeError, "secret detail of the failure"
    end
    log = nil

    replacing_method(RubylodeArgocd::ArgocdClient, :new, ->(**) { exploding }) do
      log = captured_log do
        log_user("admin", "admin")
        2.times { get "/status/argocd" }
      end
    end

    assert_response :success
    assert_select ".rubylode-argocd-unavailable", 2
    assert_equal 2, calls, "one call for each of the two instances, none on the second load"
    assert_includes log, "RuntimeError"
    refute_includes log, "secret detail"
  end

  test "an IPv6 address in brackets is reached" do
    ipv6_server = begin
      FakeArgocdServer.new(host: "::1").start
    rescue SystemCallError, SocketError => error
      skip "::1 cannot be bound in this container (#{error.class})"
    end
    ENV[FIRST_VARIABLE] = FakeArgocdServer::TOKEN
    configure_plugin("instances" => "Production | #{ipv6_server.url} | #{FIRST_VARIABLE}", "cache_seconds" => "60")

    log_user("admin", "admin")
    get "/status/argocd"

    assert_select "tbody tr", 13
    assert_equal ["[::1]:#{ipv6_server.port}"], ipv6_server.seen_requests.map { |seen| seen[:host] }.uniq
  ensure
    ipv6_server&.stop
  end
end
