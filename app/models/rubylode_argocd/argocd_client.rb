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

    DEFAULT_APP_NAMESPACE = "argocd".freeze
    # The most of an answer that is read. Past it the call gives up.
    MAX_BODY_BYTES = 10 * 1024 * 1024

    # `fields` is an allowlist on the server: a path not on it drops out silently. `status.health` passes only whole,
    # and `status.sync.revisions` never passes, which is why a multi-source app shows its source count.
    APPLICATION_FIELDS = %w[
      items.metadata.name items.metadata.namespace items.spec.project items.spec.sources
      items.status.health items.status.sync.status items.status.sync.revision
      items.status.operationState.finishedAt items.status.resources
    ].join(",").freeze

    # The token goes only to this instance's address, over https unless the host is loopback or allow_plain_http is
    # true. A redirect is never followed, so the token cannot reach another host. Every message is scrubbed of the token.
    def initialize(instance:, timeout_seconds:, allow_plain_http: false)
      @instance = instance
      @timeout_seconds = timeout_seconds
      @allow_plain_http = allow_plain_http
    end

    # The parsed answer of GET /api/v1/applications.
    def applications
      get_json("/api/v1/applications?#{URI.encode_www_form(fields: APPLICATION_FIELDS)}")
    end

    # The parsed answer of GET /api/v1/applications/<name>/resource-tree. An app outside Argo CD's own namespace is found
    # only when that namespace is named.
    def resource_tree(name:, namespace:)
      query = namespace == DEFAULT_APP_NAMESPACE ? "" : "?#{URI.encode_www_form(appNamespace: namespace)}"
      get_json("/api/v1/applications/#{ERB::Util.url_encode(name)}/resource-tree#{query}")
    end

    private

    def get_json(path_and_query)
      raise Unavailable, I18n.t("rubylode_argocd.errors.token_missing", name: @instance.name) if @instance.token.empty?

      uri = URI("#{@instance.address}#{path_and_query}")
      unless SecureTransport.allowed?(uri, allow_plain_http: @allow_plain_http)
        raise Unavailable, I18n.t("rubylode_argocd.errors.insecure_connection")
      end

      status, body = get(uri)
      raise Unavailable, I18n.t("rubylode_argocd.errors.redirect_refused") if (300..399).cover?(status)
      raise Unavailable, I18n.t("rubylode_argocd.errors.argocd_status", status: status) unless status == 200

      JSON.parse(body)
    rescue Unavailable => error
      raise Unavailable, scrub(error.message)
    rescue JSON::ParserError
      raise Unavailable, I18n.t("rubylode_argocd.errors.answer_unreadable")
    rescue StandardError => error
      raise Unavailable, scrub(I18n.t("rubylode_argocd.errors.unreachable", error_class: error.class))
    end

    def scrub(message)
      token = @instance.token
      token.empty? ? message : message.gsub(token, "[filtered]")
    end

    def get(uri)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@instance.token}"
      request["Accept"] = "application/json"
      # hostname has no brackets round an IPv6 address; nil, nil keeps proxy settings in the environment from being used.
      http = Net::HTTP.new(uri.hostname, uri.port, nil, nil)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds
      # Net::HTTP retries a GET once after a read timeout, which doubles the wait and the calls to a stuck server.
      http.max_retries = 0
      answer = nil
      http.start do |connection|
        connection.request(request) { |response| answer = [response.code.to_i, read_limited_body(response)] }
      end
      answer
    end

    def read_limited_body(response)
      body = +""
      response.read_body do |chunk|
        body << chunk
        raise Unavailable, I18n.t("rubylode_argocd.errors.answer_too_large") if body.bytesize > MAX_BODY_BYTES
      end
      body
    end
  end
end
