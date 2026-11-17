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
  # The saved plugin settings, read into plain values.
  class Settings
    PLUGIN_ID = "redmine_rubylode_argocd".freeze
    COMMENT_PREFIX = "#".freeze
    DEFAULT_BLOCK_TITLE = "Applications".freeze
    VISIBILITIES = %w[logged_in admins].freeze
    # Only variables meant for this plugin may be read, so the settings cannot send another secret (the secret key
    # base, a database password) to an address of the administrator's choosing.
    TOKEN_VARIABLE_PATTERN = /\AARGOCD_[A-Z0-9_]+\z/

    # One Argo CD instance from a line `Name | address | token variable`. The token itself is read from the environment
    # each time it is needed and never stored in the settings.
    Instance = Struct.new(:name, :address, :token_variable, keyword_init: true) do
      def token
        return "" unless TOKEN_VARIABLE_PATTERN.match?(token_variable)

        ENV.fetch(token_variable, "").to_s
      end
    end

    def self.current
      new(Setting.send(:"plugin_#{PLUGIN_ID}") || {})
    end

    def initialize(values)
      @values = values.to_h.transform_keys(&:to_s)
    end

    def instances
      @values["instances"].to_s.lines.map(&:strip).reject { |line| line.empty? || line.start_with?(COMMENT_PREFIX) }.map do |line|
        name, address, token_variable = line.split("|", 3).map(&:strip)
        Instance.new(name: name.to_s, address: address.to_s.chomp("/"), token_variable: token_variable.to_s)
      end
    end

    # Apps to show, for one instance: app name => label. Empty means every app the instance has. A line is
    # `Instance | app name | label`; without a label the app name is the label.
    def apps_to_show_for(instance_name)
      @values["apps_to_show"].to_s.lines.map(&:strip).reject { |line| line.empty? || line.start_with?(COMMENT_PREFIX) }.each_with_object({}) do |line, wanted|
        instance, app, label = line.split("|", 3).map(&:strip)
        next unless instance == instance_name && !app.to_s.empty?

        wanted[app] = label.to_s.empty? ? app : label
      end
    end

    def block_title
      title = @values["block_title"].to_s.strip
      title.empty? ? DEFAULT_BLOCK_TITLE : title
    end

    def visibility
      VISIBILITIES.include?(@values["visibility"].to_s) ? @values["visibility"].to_s : "logged_in"
    end

    # Anonymous never; the signed in, or administrators only.
    def visible_to?(user)
      return false unless user&.logged?

      visibility == "admins" ? user.admin? : true
    end

    def allow_plain_http?
      %w[1 true].include?(@values["allow_plain_http"].to_s)
    end

    def cache_seconds
      whole_number("cache_seconds")
    end

    def failure_cache_seconds
      whole_number("failure_cache_seconds")
    end

    def timeout_seconds
      whole_number("timeout_seconds")
    end

    private

    def whole_number(key)
      @values[key].to_i
    end
  end
end
