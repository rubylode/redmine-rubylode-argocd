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
  # What the Argo CD block hands to Rubylode Status: a state (ok, warning, down or unknown), a one-line summary and one item
  # per instance. See the Status plugin's docs/widget-contract.md. Works without the Status plugin; then nothing is registered.
  module StatusWidget
    KEY = "argocd".freeze
    PAGE_PATH = "/status/argocd".freeze
    PARTIAL = "rubylode_argocd/status".freeze
    BROKEN_HEALTHS = %w[Degraded Missing].freeze
    WORSE_FIRST = %w[down warning unknown ok].freeze

    class << self
      def status_plugin_present?
        defined?(RubylodeStatus::Registry) ? true : false
      end

      # Called once every plugin has loaded (see init.rb). Returns whether the widget was registered.
      def register
        return false unless status_plugin_present?

        RubylodeStatus::Registry.register(
          key: KEY,
          title: -> { RubylodeArgocd::Settings.current.block_title },
          path: PAGE_PATH,
          data: -> { data },
          partial: PARTIAL,
          visibility: -> { RubylodeArgocd::Settings.current.visibility }
        )
        true
      end

      def data(settings = RubylodeArgocd::Settings.current)
        instances = settings.instances
        return { state: "unknown", summary: I18n.t("rubylode_argocd.status.not_set_up"), items: [] } if instances.empty?

        reports = instances.to_h { |instance| [instance, RubylodeArgocd::ApplicationStatus.report_for(instance, settings)] }
        items = reports.map { |instance, report| item_for(instance, report) }.sort_by { |item| WORSE_FIRST.index(item[:state]) }
        { state: block_state(items), summary: RubylodeArgocd::ApplicationStatus.summary_for(reports.values).text, items: items }
      end

      private

      def item_for(instance, report)
        return { name: instance.name, state: "unknown", detail: I18n.t("rubylode_argocd.status.unavailable") } if report.unavailable?
        return { name: instance.name, state: "unknown", detail: I18n.t("rubylode_argocd.summary.no_apps") } if report.rows.empty?

        attention = report.rows.count(&:needs_attention)
        state = if report.rows.any? { |row| BROKEN_HEALTHS.include?(row.health) }
          "down"
        elsif attention.positive?
          "warning"
        else
          "ok"
        end
        { name: instance.name, state: state, detail: attention.positive? ? I18n.t("rubylode_argocd.widget.need_attention", count: attention) : nil }
      end

      # The worst item decides. An instance that could not be asked makes a block that is otherwise fine a warning: nothing
      # can be said about its apps. Only when no instance reports anything is the block unknown.
      def block_state(items)
        states = items.map { |item| item[:state] }
        return "down" if states.include?("down")
        return "warning" if states.include?("warning")
        return "unknown" if states.all?("unknown")

        states.include?("unknown") ? "warning" : "ok"
      end
    end
  end
end
