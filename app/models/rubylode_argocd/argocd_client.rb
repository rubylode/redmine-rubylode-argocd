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

require "net/http"
require "json"

module RubylodeArgocd
  # Asks one Argo CD instance's API for its applications, with the instance's token as a bearer token. Read-only.
  class ArgocdClient
    class Unavailable < StandardError; end

    # `fields` is an allowlist on the server: a path not on it drops out silently. `status.health` passes only whole,
    # and `status.sync.revisions` never passes, which is why a multi-source app shows its source count.
    APPLICATION_FIELDS = %w[
      items.metadata.name items.metadata.namespace items.spec.project items.spec.sources
      items.status.health items.status.sync.status items.status.sync.revision
      items.status.operationState.finishedAt items.status.resources
    ].join(",").freeze

    def initialize(instance:, timeout_seconds:)
      @instance = instance
      @timeout_seconds = timeout_seconds
    end

    # The parsed answer of GET /api/v1/applications.
    def applications
      raise Unavailable, "No token for #{@instance.name}" if @instance.token.empty?

      uri = URI("#{@instance.address}/api/v1/applications?#{URI.encode_www_form(fields: APPLICATION_FIELDS)}")
      status, body = get(uri)
      raise Unavailable, "Argo CD answered #{status}" unless status == 200

      JSON.parse(body)
    end

    private

    def get(uri)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@instance.token}"
      request["Accept"] = "application/json"
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds
      # Net::HTTP retries a GET once after a read timeout, which doubles the wait and the calls to a stuck server.
      http.max_retries = 0
      response = http.start { |connection| connection.request(request) }
      [response.code.to_i, response.body]
    end
  end
end
