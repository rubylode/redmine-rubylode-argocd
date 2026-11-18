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
    COLUMNS = %w[left right].freeze
    # What an empty or unreadable number setting means. The same values init.rb registers as the settings defaults.
    NUMBER_DEFAULTS = { "cache_seconds" => 60, "failure_cache_seconds" => 30, "timeout_seconds" => 3 }.freeze
    # Only variables meant for this plugin may be read, so the settings cannot send another secret (the secret key
    # base, a database password) to an address of the administrator's choosing.
    TOKEN_VARIABLE_PATTERN = /\AARGOCD_[A-Z0-9_]+\z/

    # One Argo CD instance from a line `Name | address | token variable | link address`. The address is where Redmine
    # calls the API; the optional link address is where people open Argo CD in their browser, for when Redmine reaches
    # Argo CD by a name no browser can resolve (an in-cluster Service). Nothing is ever sent to the link address. The
    # token itself is read from the environment each time it is needed and never stored in the settings.
    Instance = Struct.new(:name, :address, :token_variable, :link_address, keyword_init: true) do
      def token
        return "" unless TOKEN_VARIABLE_PATTERN.match?(token_variable)

        # Spaces or a line break round the value, as a pasted secret often has, are not part of the token.
        ENV.fetch(token_variable, "").to_s.strip
      end

      def link_address
        self[:link_address].to_s.empty? ? address : self[:link_address]
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
        name, address, token_variable, link_address = line.split("|", 4).map(&:strip)
        Instance.new(name: name.to_s, address: address.to_s.chomp("/"), token_variable: token_variable.to_s,
                     link_address: link_address.to_s.chomp("/"))
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

    def show_on_welcome_page?
      flag?("show_on_welcome_page")
    end

    def welcome_page_column
      column("welcome_page_column")
    end

    def show_on_my_page?
      flag?("show_on_my_page")
    end

    def show_on_project_overview?
      flag?("show_on_project_overview")
    end

    def project_overview_column
      column("project_overview_column")
    end

    def show_in_top_menu?
      flag?("show_in_top_menu")
    end

    def show_on_matching_pages?
      flag?("show_on_matching_pages")
    end

    def matching_page_paths_text
      @values["matching_page_paths"].to_s
    end

    def matching_page_patterns
      show_on_matching_pages? ? PathMatcher.parse(matching_page_paths_text).patterns : []
    end

    def allow_plain_http?
      @values["allow_plain_http"].to_s == "1"
    end

    def cache_seconds
      whole_number("cache_seconds", minimum: 0)
    end

    def failure_cache_seconds
      whole_number("failure_cache_seconds", minimum: 0)
    end

    def timeout_seconds
      whole_number("timeout_seconds", minimum: 1)
    end

    private

    def flag?(key)
      @values[key].to_s == "1"
    end

    def column(key)
      COLUMNS.include?(@values[key].to_s) ? @values[key].to_s : "right"
    end

    # A number the person typed, never below the minimum. Empty or not a number means the default, not 0: a timeout of
    # 0 fails every call at once and a cache time of 0 turns caching off.
    def whole_number(key, minimum:)
      [Integer(@values[key].to_s.strip, 10), minimum].max
    rescue ArgumentError
      NUMBER_DEFAULTS.fetch(key)
    end
  end
end
