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

require "timeout"

module RubylodeArgocd
  # Tells a time limit a caller put round the whole call apart from every other error. The plugin turns any other error
  # into an unavailable section, but a caller's time limit belongs to the caller (the Rubylode Status page gives each
  # widget a few seconds and raises its own error when they run out), so it must travel on and never be cached.
  # Classes are compared by name, so the plugin that defines them need not be installed.
  module CallerDeadline
    DEFAULT_CLASS_NAMES = ["RubylodeStatus::WidgetStatus::TookTooLong"].freeze

    class << self
      # The names of the error classes, subclasses included, that are a caller's time limit. Tests add their own.
      def class_names
        @class_names ||= DEFAULT_CLASS_NAMES.dup
      end

      def raised?(error)
        return true if defined?(Timeout::ExitException) && error.is_a?(Timeout::ExitException)

        error.class.ancestors.any? { |ancestor| class_names.include?(ancestor.name) }
      end
    end
  end
end
