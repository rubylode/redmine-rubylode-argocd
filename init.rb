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

require "redmine"

Redmine::Plugin.register :redmine_rubylode_argocd do
  name "Rubylode Argo CD"
  author "Rubylode"
  author_url "https://github.com/rubylode"
  url "https://github.com/rubylode/redmine-rubylode-argocd"
  description "The health and sync state of the apps in one or more Argo CD instances: a page, a wiki macro, a My page block and a partial"
  version "1.2.0"
  requires_redmine version_or_higher: "5.1.0"

  # A link to the page in the top menu, shown only when the settings ask for it and only to the people allowed to see the block.
  # With Rubylode Status installed the block lives on its page, so this item goes.
  menu :top_menu, :rubylode_argocd_status, { controller: "rubylode_argocd_status", action: "show" },
       caption: proc { RubylodeArgocd::Settings.current.block_title },
       if: proc {
         settings = RubylodeArgocd::Settings.current
         !RubylodeArgocd::StatusWidget.status_plugin_present? && settings.show_in_top_menu? && settings.visible_to?(User.current)
       }

  settings default: { "instances" => "", "cache_seconds" => "60", "failure_cache_seconds" => "30", "timeout_seconds" => "3",
                       "allow_plain_http" => "0", "apps_to_show" => "", "block_title" => "Applications", "visibility" => "logged_in",
                       "show_on_welcome_page" => "0", "welcome_page_column" => "right", "show_on_my_page" => "0",
                       "show_on_project_overview" => "0", "project_overview_column" => "right", "show_in_top_menu" => "0",
                       "show_on_matching_pages" => "0", "matching_page_paths" => "" },
           partial: "settings/rubylode_argocd"
end

require_relative "lib/rubylode_argocd/macros"
RubylodeArgocd::Macros.register
require_relative "lib/rubylode_argocd/hooks"
require_relative "lib/rubylode_argocd/settings_controller_patch"
require_relative "lib/rubylode_argocd/default_my_page_patch"
Redmine::MyPage.singleton_class.prepend(RubylodeArgocd::DefaultMyPagePatch)

# Plugins load after the boot-time prepare callbacks have run, so apply the patch now and again after each code reload.
apply_settings_controller_patch = lambda do
  unless SettingsController.include?(RubylodeArgocd::SettingsControllerPatch)
    SettingsController.prepend RubylodeArgocd::SettingsControllerPatch
  end
end
apply_settings_controller_patch.call
Rails.configuration.to_prepare(&apply_settings_controller_patch)

# Puts the block on the Status page when Rubylode Status is installed. See its docs/widget-contract.md.
# Redmine loads plugins in alphabetical order, so this plugin's init.rb may run before the Status plugin's: wait for all of them.
Rails.application.config.after_initialize do
  RubylodeArgocd::StatusWidget.register
end
