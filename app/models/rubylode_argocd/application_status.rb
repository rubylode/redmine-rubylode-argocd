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

    # What one instance's section shows: its rows, or the reason it could not be asked.
    Report = Struct.new(:rows, :unavailable, :failure_reason, keyword_init: true) do
      alias_method :unavailable?, :unavailable
    end

    FAILURE_KEY = "failure".freeze

    # The report of one instance. Its Argo CD is asked at most once per Cache seconds, and after a failure not again
    # for Failure cache seconds. Whatever goes wrong, the answer is an unavailable report and never an error.
    def self.report_for(instance, configuration = Settings.current)
      payload = read_cache(instance) || fetch_and_cache(instance, configuration)
      return Report.new(rows: [], unavailable: true, failure_reason: failure_reason_from(payload)) if payload.key?(FAILURE_KEY)

      Report.new(rows: rows_from(payload["answer"]), unavailable: false, failure_reason: nil)
    rescue StandardError => error
      Rails.logger.warn("Rubylode Argo CD: could not build the section for #{instance.name}: #{error.class}")
      Report.new(rows: [], unavailable: true, failure_reason: error.class.name)
    end

    def self.fetch_and_cache(instance, configuration)
      client = ArgocdClient.new(instance: instance, timeout_seconds: configuration.timeout_seconds,
                                allow_plain_http: configuration.allow_plain_http?)
      payload = { "answer" => client.applications }
      write_cache(instance, payload, configuration.cache_seconds)
      payload
    rescue ArgocdClient::Unavailable => error
      payload = { FAILURE_KEY => error.message }
      write_cache(instance, payload, configuration.failure_cache_seconds)
      payload
    end
    private_class_method :fetch_and_cache

    # A cache that cannot be read or written is a miss, not an error. A time of 0 means no caching at all.
    def self.read_cache(instance)
      cache.read(cache_key_for(instance))
    rescue StandardError => error
      Rails.logger.warn("Rubylode Argo CD: cache read failed, carrying on without it: #{error.class}")
      nil
    end
    private_class_method :read_cache

    def self.write_cache(instance, payload, seconds)
      return unless seconds.positive?

      cache.write(cache_key_for(instance), payload, expires_in: seconds)
    rescue StandardError => error
      Rails.logger.warn("Rubylode Argo CD: cache write failed, carrying on without it: #{error.class}")
    end
    private_class_method :write_cache

    def self.failure_reason_from(payload)
      reason = payload[FAILURE_KEY].to_s
      reason.empty? ? I18n.t("rubylode_argocd.errors.argocd_did_not_answer") : reason
    end
    private_class_method :failure_reason_from

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
