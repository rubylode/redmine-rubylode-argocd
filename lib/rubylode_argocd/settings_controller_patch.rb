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
  # Redmine saves plugin settings without asking the plugin. This checks ours first: when something is wrong the form is
  # shown again with what the person typed and a list of the problems, and nothing is saved. A save that goes through
  # also forgets what was cached, so the next page load asks Argo CD again.
  module SettingsControllerPatch
    def plugin
      return super unless request.post? && params[:id].to_s == RubylodeArgocd::Settings::PLUGIN_ID.to_s

      submitted = params[:settings] ? params[:settings].permit!.to_h : {}
      errors = RubylodeArgocd::SettingsValidator.errors_for(submitted)
      if errors.empty?
        before = RubylodeArgocd::Settings.current.instances
        result = super
        RubylodeArgocd::ApplicationStatus.forget(before + RubylodeArgocd::Settings.current.instances)
        return result
      end

      @plugin = Redmine::Plugin.find(params[:id])
      @partial = @plugin.settings[:partial]
      @settings = submitted
      @validation_errors = errors
      render "settings/plugin", status: :unprocessable_entity
    end
  end
end
