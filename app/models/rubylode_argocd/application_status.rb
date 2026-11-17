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

module RubylodeArgocd
  # Argo CD's application list in, one row per app out.
  class ApplicationStatus
    SHORT_REVISION_LENGTH = 7

    # source_count is set only for a multi-source app: its revisions cannot pass the `fields` allowlist, so the row
    # shows how many sources it has instead of a revision.
    Row = Struct.new(:name, :namespace, :project, :health, :sync, :finished_at, :revision, :source_count, keyword_init: true)

    class << self
      attr_writer :cache

      def cache
        @cache ||= Rails.cache
      end
    end

    # The rows of one instance. Its Argo CD is asked at most once per Cache seconds.
    def self.rows_for(instance, configuration = Settings.current)
      answer = cache.fetch(cache_key_for(instance), expires_in: configuration.cache_seconds) do
        ArgocdClient.new(instance: instance, timeout_seconds: configuration.timeout_seconds).applications
      end
      rows_from(answer)
    end

    # Two tokens on one address may see different apps, so both are part of the key.
    def self.cache_key_for(instance)
      "rubylode_argocd/applications/#{Digest::SHA256.hexdigest("#{instance.address}|#{instance.token_variable}")[0, 16]}"
    end

    def self.rows_from(answer)
      Array(answer["items"]).map { |application| row_from(application) }
    end

    def self.row_from(application)
      sources = Array(application.dig("spec", "sources"))
      revision = application.dig("status", "sync", "revision").to_s
      Row.new(
        name: application.dig("metadata", "name").to_s,
        namespace: application.dig("metadata", "namespace").to_s,
        project: application.dig("spec", "project").to_s,
        health: application.dig("status", "health", "status").to_s,
        sync: application.dig("status", "sync", "status").to_s,
        finished_at: time_from(application.dig("status", "operationState", "finishedAt")),
        revision: sources.empty? && !revision.empty? ? revision[0, SHORT_REVISION_LENGTH] : nil,
        source_count: sources.empty? ? nil : sources.size
      )
    end
    private_class_method :row_from

    def self.time_from(text)
      Time.iso8601(text.to_s)
    rescue ArgumentError
      nil
    end
    private_class_method :time_from
  end
end
