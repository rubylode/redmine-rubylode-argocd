# Rubylode Argo CD: application status from Argo CD for Redmine
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

require "socket"
require "json"
require "uri"

# A tiny stand-in for an Argo CD server, for the demo and the integration tests. Standard library only.
#
# It answers the calls the plugin makes from the scrubbed fixtures in test/support/fixtures/argocd, with the status
# codes and error bodies a real Argo CD 3.6 gives:
#
#   GET /api/version                                   200, no token needed
#   GET /api/v1/applications                           200 with the app list; the `fields` parameter is recorded, not
#                                                      applied (the fixture already has the trimmed shape)
#   GET /api/v1/applications/<name>                    200 with that app
#   GET /api/v1/applications/<name>/resource-tree      200 with its tree; `appNamespace` must name the app's namespace
#                                                      when that is not "argocd"
#
# Every /api/v1 call needs "Authorization: Bearer <token>" and answers 401 without it. An app that does not exist, or is
# asked for in the wrong namespace, answers 403 "permission denied", as Argo CD does.
#
# It can be told to fail: `failure = "server_error"` (500), `"timeout"` (holds the connection for timeout_seconds,
# then closes it without an answer), or `"unauthorized"` (401 even with the right token). `redirect_to = "http://other"`
# makes it answer every /api call with a 302 to that base, which is how tests check that the token never follows a
# redirect to another host. Each request is recorded (method, path, query, Host and Authorization headers) in
# `seen_requests`, so tests can assert where a token went.
#
# For tests: `applications_answer = {...}` replaces the fixture app list, and `failing_tree_apps = ["name"]` makes the
# resource-tree call of those apps answer 500.
#
# The same controls work over HTTP for the demo: POST /__fail/<server_error|timeout|unauthorized|none>,
# POST /__redirect_to (body: a base URL, or empty to clear it), POST /__reset, GET /__requests (JSON).
# Run it on its own:  ruby test/support/fake_argocd_server.rb   (FAKE_ARGOCD_PORT, FAKE_ARGOCD_TOKEN to change them)
class FakeArgocdServer
  TOKEN = "fake.argocd.token-not-a-secret".freeze
  FIXTURES = File.expand_path("fixtures/argocd", __dir__).freeze
  DEFAULT_APP_NAMESPACE = "argocd".freeze
  FAILURES = %w[server_error timeout unauthorized].freeze

  attr_reader :port
  attr_accessor :failure, :redirect_to, :timeout_seconds, :applications_answer, :failing_tree_apps

  def initialize(token: TOKEN, port: 0, host: "127.0.0.1", failure: nil, timeout_seconds: 5)
    @token = token
    @host = host
    @requested_port = port
    @failure = failure
    @timeout_seconds = timeout_seconds
    @seen_requests = []
    @failing_tree_apps = []
    @lock = Mutex.new
  end

  def start
    @server = TCPServer.new(@host, @requested_port)
    @port = @server.addr[1]
    @thread = Thread.new { accept_loop }
    self
  end

  def stop
    @server&.close
    @thread&.join(2)
  end

  def url
    "http://#{@host}:#{@port}"
  end

  def seen_requests
    @lock.synchronize { @seen_requests.dup }
  end

  def reset!
    @lock.synchronize { @seen_requests.clear }
    self.failure = nil
    self.redirect_to = nil
    self.applications_answer = nil
    self.failing_tree_apps = []
  end

  def applications
    (applications_answer || read_fixture("applications.json")).fetch("items")
  end

  private

  def accept_loop
    loop do
      client = @server.accept
      Thread.new(client) { |connection| handle(connection) }
    rescue IOError, Errno::EBADF
      break
    end
  end

  def handle(client)
    request_line = client.gets.to_s
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.downcase] = value.to_s.strip
    end
    body = headers["content-length"] ? client.read(headers["content-length"].to_i).to_s : ""
    method, target = request_line.split(" ")
    status, content_type, payload = respond(method.to_s, target.to_s, headers, body)
    return if status == :hang

    client.write("HTTP/1.1 #{status}\r\nContent-Type: #{content_type}\r\nContent-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n#{payload}")
  rescue StandardError
    nil
  ensure
    client.close
  end

  def respond(method, target, headers, body)
    route, query = target.split("?", 2)
    params = URI.decode_www_form(query.to_s).to_h
    unless route.start_with?("/__")
      @lock.synchronize do
        @seen_requests << { method: method, path: route, query: params, host: headers["host"], authorization: headers["authorization"] }
      end
    end

    return control(method, route, body) if route.start_with?("/__")
    return ["302 Found\r\nLocation: #{redirect_to}#{target}", "text/plain; charset=utf-8", ""] if redirect_to && route.start_with?("/api/")
    return hang if failure == "timeout" && route.start_with?("/api/")
    return json("500 Internal Server Error", "error" => "internal error", "code" => 13, "message" => "internal error") if failure == "server_error" && route.start_with?("/api/")
    return ["200 OK", "application/json", File.read(File.join(FIXTURES, "version.json"))] if method == "GET" && route == "/api/version"
    return not_found unless method == "GET" && route.start_with?("/api/v1/applications")
    return unauthorized if failure == "unauthorized" || headers["authorization"] != "Bearer #{@token}"

    application_route(route, params)
  end

  def application_route(route, params)
    case route
    when "/api/v1/applications"
      json("200 OK", applications_answer || read_fixture("applications.json"))
    when %r{\A/api/v1/applications/([^/]+)/resource-tree\z}
      return json("500 Internal Server Error", "error" => "internal error", "code" => 13) if failing_tree_apps.include?(Regexp.last_match(1))

      app = find_application(Regexp.last_match(1), params["appNamespace"])
      app ? json("200 OK", resource_tree(app.dig("metadata", "name"))) : permission_denied
    when %r{\A/api/v1/applications/([^/]+)\z}
      app = find_application(Regexp.last_match(1), params["appNamespace"])
      app ? json("200 OK", app) : permission_denied
    else
      not_found
    end
  end

  # Argo CD looks an app up in the namespace it is asked for, "argocd" when none is given.
  def find_application(name, app_namespace)
    namespace = app_namespace.to_s.empty? ? DEFAULT_APP_NAMESPACE : app_namespace
    applications.find { |app| app.dig("metadata", "name") == name && app.dig("metadata", "namespace") == namespace }
  end

  def resource_tree(name)
    path = File.join(FIXTURES, "resource_trees", "#{name}.json")
    File.exist?(path) ? JSON.parse(File.read(path)) : { "nodes" => [] }
  end

  def control(method, route, body)
    if method == "POST" && route.start_with?("/__fail/")
      mode = route.delete_prefix("/__fail/")
      return json("404 Not Found", "message" => "unknown failure") unless FAILURES.include?(mode) || mode == "none"

      self.failure = mode == "none" ? nil : mode
      json("200 OK", "failure" => failure)
    elsif method == "POST" && route == "/__redirect_to"
      self.redirect_to = body.strip.empty? ? nil : body.strip
      json("200 OK", "redirect_to" => redirect_to)
    elsif method == "POST" && route == "/__reset"
      reset!
      json("200 OK", "reset" => true)
    elsif route == "/__requests"
      json("200 OK", seen_requests)
    else
      not_found
    end
  end

  def hang
    sleep timeout_seconds
    [:hang]
  end

  def read_fixture(name)
    JSON.parse(File.read(File.join(FIXTURES, name)))
  end

  def json(status, data)
    [status, "application/json", JSON.generate(data)]
  end

  def unauthorized
    ["401 Unauthorized", "application/json", File.read(File.join(FIXTURES, "errors", "unauthorized.json"))]
  end

  def permission_denied
    ["403 Forbidden", "application/json", File.read(File.join(FIXTURES, "errors", "permission_denied.json"))]
  end

  def not_found
    ["404 Not Found", "text/plain; charset=utf-8", "404 page not found\n"]
  end
end

if $PROGRAM_NAME == __FILE__
  server = FakeArgocdServer.new(token: ENV.fetch("FAKE_ARGOCD_TOKEN", FakeArgocdServer::TOKEN),
                                port: ENV.fetch("FAKE_ARGOCD_PORT", "8080").to_i, host: "0.0.0.0").start
  puts "Fake Argo CD on port #{server.port}"
  $stdout.flush
  sleep
end
