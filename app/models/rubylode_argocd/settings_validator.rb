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
  # Checks the settings form before it is saved. Returns a list of messages, empty when everything is fine.
  # Empty values are fine where the plugin has a default or the setting is optional.
  class SettingsValidator
    NUMBER_FIELDS = { "cache_seconds" => 0, "failure_cache_seconds" => 0, "timeout_seconds" => 1 }.freeze

    def self.errors_for(raw_settings)
      new(raw_settings).errors
    end

    def initialize(raw_settings)
      @settings = (raw_settings || {}).to_h.stringify_keys
    end

    def errors
      messages = instance_errors
      messages.concat(app_errors)
      messages << t("column_invalid") unless columns_valid?
      messages << t("block_title_blank") if @settings.key?("block_title") && @settings["block_title"].to_s.strip.empty?
      messages << t("visibility_invalid") unless visibility_valid?
      messages.concat(number_errors)
      messages.concat(path_errors)
      messages
    end

    private

    def t(key, **options)
      I18n.t("rubylode_argocd.errors.#{key}", **options)
    end

    # Each line that holds something, with its line number in the text the person typed.
    def numbered_lines(key)
      @settings[key].to_s.lines.each_with_index.filter_map do |line, index|
        text = line.strip
        [index + 1, text] unless text.empty? || text.start_with?(Settings::COMMENT_PREFIX)
      end
    end

    def allow_plain_http?
      @settings["allow_plain_http"].to_s == "1"
    end

    def instance_errors
      names = []
      numbered_lines("instances").flat_map do |line_number, text|
        name, address, variable = text.split("|", 3).map(&:strip)
        problems = instance_line_problems(text, name, address, variable, names)
        names << name
        problems.map { |message| t("instance_line_prefix", line_number: line_number, message: message) }
      end
    end

    def instance_line_problems(text, name, address, variable, names)
      return [t("line_field_count", count: 3, found: text.split("|", -1).size)] unless text.split("|", -1).size == 3

      problems = []
      problems << t("line_name_missing") if name.empty?
      problems << t("line_name_duplicate", name: name) if names.include?(name)
      problems.concat(address_problems(address))
      problems << t("environment_variable_invalid") unless variable.match?(Settings::TOKEN_VARIABLE_PATTERN)
      problems
    end

    def address_problems(address)
      uri = URI.parse(address)
      return [t("address_invalid")] unless %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
      return [t("plain_http_refused")] unless SecureTransport.allowed?(uri, allow_plain_http: allow_plain_http?)

      []
    rescue URI::InvalidURIError
      [t("address_invalid")]
    end

    def app_errors
      known = Settings.new("instances" => @settings["instances"]).instances.map(&:name)
      numbered_lines("apps_to_show").filter_map do |line_number, text|
        instance, app = text.split("|", 3).map(&:strip)
        message = if app.to_s.empty?
          t("app_line_field_count")
        elsif !known.include?(instance)
          t("app_line_unknown_instance", name: instance)
        end
        t("app_line_prefix", line_number: line_number, message: message) if message
      end
    end

    def columns_valid?
      %w[welcome_page_column project_overview_column].all? { |key| !@settings.key?(key) || Settings::COLUMNS.include?(@settings[key].to_s) }
    end

    def path_errors
      PathMatcher.parse(@settings["matching_page_paths"]).errors.map do |line_error|
        line_error.line_number.zero? ? line_error.message : t("path_line_prefix", line_number: line_error.line_number, message: line_error.message)
      end
    end

    def visibility_valid?
      !@settings.key?("visibility") || Settings::VISIBILITIES.include?(@settings["visibility"].to_s)
    end

    def number_errors
      NUMBER_FIELDS.filter_map do |key, minimum|
        value = @settings[key].to_s.strip
        next if value.empty?

        valid = value.match?(/\A\d+\z/) && value.to_i >= minimum
        t("number_invalid", field: I18n.t("rubylode_argocd.settings.#{key}.label"), minimum: minimum) unless valid
      end
    end
  end
end
