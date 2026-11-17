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
  # The "needs attention" rule: an app is broken when its health is Degraded, Missing or Unknown, and out of line when
  # its sync is OutOfSync. Progressing and Suspended are shown but do not count.
  module AttentionRule
    UNHEALTHY = %w[Degraded Missing Unknown].freeze
    OUT_OF_SYNC = "OutOfSync".freeze

    def self.needs_attention?(health, sync)
      UNHEALTHY.include?(health) || sync == OUT_OF_SYNC
    end
  end
end
