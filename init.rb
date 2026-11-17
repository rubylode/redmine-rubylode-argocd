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
  version "0.1.0"
  requires_redmine version_or_higher: "5.1.0"

  settings default: { "instances" => "", "cache_seconds" => "60", "failure_cache_seconds" => "30", "timeout_seconds" => "3",
                       "allow_plain_http" => "0", "apps_to_show" => "", "block_title" => "Applications", "visibility" => "logged_in" },
           partial: "settings/rubylode_argocd"
end
