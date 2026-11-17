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
    # failing_resources lists what is wrong under an app that is not Healthy. detail_skipped is true when the app was
    # left out of the resource-tree calls because the cap was reached.
    Row = Struct.new(:name, :namespace, :project, :health, :sync, :finished_at, :revision, :source_count,
                     :failing_resources, :detail_skipped, :needs_attention, :label, keyword_init: true)

    FailingResource = Struct.new(:kind, :namespace, :name, :health, :message, keyword_init: true)

    FAILING_HEALTHS = %w[Degraded Missing Unknown].freeze
    HEALTHY = "Healthy".freeze

    # Resource-tree calls per instance per refresh. Past it an app shows only its managed resources.
    RESOURCE_TREE_LIMIT = 10

    class << self
      attr_writer :cache

      def cache
        @cache ||= Rails.cache
      end
    end

    # What one instance's section shows: its rows, or the reason it could not be asked. unknown_apps names the apps
    # listed in Apps to show that the instance does not have.
    Report = Struct.new(:rows, :unavailable, :failure_reason, :unknown_apps, keyword_init: true) do
      alias_method :unavailable?, :unavailable

      def unknown_apps
        self[:unknown_apps] || []
      end
    end

    # The line above the sections. Rows of an unavailable instance are not counted.
    Summary = Struct.new(:app_count, :attention_count, :unavailable_instance_count, keyword_init: true) do
      # What the line looks like: the page colours it by this.
      def state
        return :need_attention if attention_count.positive?
        return :unavailable if unavailable_instance_count.positive?

        app_count.zero? ? :no_apps : :all_fine
      end

      def text
        counted = if app_count.zero?
          I18n.t("rubylode_argocd.summary.no_apps")
        elsif attention_count.zero?
          I18n.t("rubylode_argocd.summary.all_fine", count: app_count)
        else
          I18n.t("rubylode_argocd.summary.need_attention", attention: attention_count, total: app_count)
        end
        return counted if unavailable_instance_count.zero?

        "#{counted}. #{I18n.t("rubylode_argocd.summary.unavailable_instances", count: unavailable_instance_count)}"
      end
    end

    def self.summary_for(reports)
      available = reports.reject(&:unavailable?)
      rows = available.flat_map(&:rows)
      Summary.new(app_count: rows.size, attention_count: rows.count(&:needs_attention),
                  unavailable_instance_count: reports.size - available.size)
    end

    FAILURE_KEY = "failure".freeze

    # The report of one instance. Its Argo CD is asked at most once per Cache seconds, and after a failure not again
    # for Failure cache seconds. Whatever goes wrong, the answer is an unavailable report and never an error.
    def self.report_for(instance, configuration = Settings.current)
      payload = read_cache(instance) || fetch_and_cache(instance, configuration)
      return Report.new(rows: [], unavailable: true, failure_reason: failure_reason_from(payload)) if payload.key?(FAILURE_KEY)

      rows = rows_from(payload["answer"], payload["resource_trees"])
      wanted = configuration.apps_to_show_for(instance.name)
      return Report.new(rows: rows, unavailable: false, failure_reason: nil, unknown_apps: []) if wanted.empty?

      Report.new(rows: narrowed_to(rows, wanted), unavailable: false, failure_reason: nil,
                 unknown_apps: wanted.keys - rows.map(&:name))
    rescue StandardError => error
      Rails.logger.warn("Rubylode Argo CD: could not build the section for #{instance.name}: #{error.class}")
      Report.new(rows: [], unavailable: true, failure_reason: error.class.name)
    end

    # Only the wanted apps, each with the label the administrator gave it.
    def self.narrowed_to(rows, wanted)
      rows.select { |row| wanted.key?(row.name) }.each { |row| row.label = wanted[row.name] }
    end
    private_class_method :narrowed_to

    def self.fetch_and_cache(instance, configuration)
      client = ArgocdClient.new(instance: instance, timeout_seconds: configuration.timeout_seconds,
                                allow_plain_http: configuration.allow_plain_http?)
      answer = client.applications
      payload = { "answer" => answer, "resource_trees" => resource_trees_for(client, answer) }
      write_cache(instance, payload, configuration.cache_seconds)
      payload
    rescue ArgocdClient::Unavailable => error
      payload = { FAILURE_KEY => error.message }
      write_cache(instance, payload, configuration.failure_cache_seconds)
      payload
    end
    private_class_method :fetch_and_cache

    # The failing part of the resource tree of each app that is not Healthy, up to the cap and the most broken first.
    # An app whose call failed is stored as nil: it shows its managed resources and no note.
    def self.resource_trees_for(client, answer)
      candidates = Array(answer["items"]).reject { |application| application.dig("status", "health", "status") == HEALTHY }
      candidates = candidates.sort_by { |application| FAILING_HEALTHS.include?(application.dig("status", "health", "status")) ? 0 : 1 }
      candidates.first(RESOURCE_TREE_LIMIT).to_h do |application|
        key = application_key(application)
        [key, failing_part_of(client.resource_tree(name: application.dig("metadata", "name").to_s, namespace: application.dig("metadata", "namespace").to_s))]
      rescue ArgocdClient::Unavailable
        [key, nil]
      end
    end
    private_class_method :resource_trees_for

    def self.failing_part_of(tree)
      { "nodes" => Array(tree["nodes"]).select { |node| FAILING_HEALTHS.include?(node.dig("health", "status")) } }
    end
    private_class_method :failing_part_of

    def self.application_key(application)
      "#{application.dig("metadata", "namespace")}/#{application.dig("metadata", "name")}"
    end
    private_class_method :application_key

    # Drops what is cached for these instances, so the next load asks Argo CD again.
    def self.forget(instances)
      instances.each { |instance| cache.delete(cache_key_for(instance)) }
    rescue StandardError => error
      Rails.logger.warn("Rubylode Argo CD: cache clear failed: #{error.class}")
    end

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

    # resource_trees maps "namespace/name" to the tree asked for that app (nil when the call failed). Leave it nil when
    # no trees were asked for at all.
    def self.rows_from(answer, resource_trees = nil)
      rows = Array(answer["items"]).map { |application| row_from(application, resource_trees) }
      rows.sort_by { |row| [row.needs_attention ? 0 : 1, row.name] }
    end

    def self.row_from(application, resource_trees)
      sources = Array(application.dig("spec", "sources"))
      revision = application.dig("status", "sync", "revision").to_s
      health = application.dig("status", "health", "status").to_s
      key = application_key(application)
      sync = application.dig("status", "sync", "status").to_s
      Row.new(
        name: application.dig("metadata", "name").to_s,
        namespace: application.dig("metadata", "namespace").to_s,
        project: application.dig("spec", "project").to_s,
        health: health,
        sync: sync,
        finished_at: time_from(application.dig("status", "operationState", "finishedAt")),
        revision: sources.empty? && !revision.empty? ? revision[0, SHORT_REVISION_LENGTH] : nil,
        source_count: sources.empty? ? nil : sources.size,
        failing_resources: failing_resources_from(application, resource_trees&.dig(key)),
        detail_skipped: !resource_trees.nil? && health != HEALTHY && !resource_trees.key?(key),
        needs_attention: AttentionRule.needs_attention?(health, sync)
      )
    end
    private_class_method :row_from

    # Managed resources that carry a health (Argo CD 2.x), then the tree's nodes, which win for the same resource
    # because they carry the message.
    def self.failing_resources_from(application, tree)
      found = {}
      Array(application.dig("status", "resources")).each { |resource| add_failing(found, resource) }
      Array(tree && tree["nodes"]).each { |node| add_failing(found, node) }
      found.values
    end
    private_class_method :failing_resources_from

    def self.add_failing(found, resource)
      health = resource.dig("health", "status").to_s
      return unless FAILING_HEALTHS.include?(health)

      found[[resource["kind"], resource["namespace"], resource["name"]]] = FailingResource.new(
        kind: resource["kind"].to_s, namespace: resource["namespace"].to_s, name: resource["name"].to_s,
        health: health, message: resource.dig("health", "message")
      )
    end
    private_class_method :add_failing

    def self.time_from(text)
      Time.iso8601(text.to_s)
    rescue ArgumentError
      nil
    end
    private_class_method :time_from
  end
end
