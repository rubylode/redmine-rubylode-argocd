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

require_relative "../test_helper"

class RubylodeArgocdApplicationStatusTest < ActiveSupport::TestCase
  def applications_answer
    JSON.parse(File.read(File.join(FakeArgocdServer::FIXTURES, "applications.json")))
  end

  def rows
    RubylodeArgocd::ApplicationStatus.rows_from(applications_answer)
  end

  test "each app in the answer becomes a row with its name, namespace, project, health, sync and last sync time" do
    billing = rows.find { |row| row.name == "billing-api" }

    assert_equal 13, rows.size
    assert_equal "argocd", billing.namespace
    assert_equal "default", billing.project
    assert_equal "Degraded", billing.health
    assert_equal "Synced", billing.sync
    assert_equal Time.utc(2026, 11, 16, 1, 36, 17), billing.finished_at
  end

  test "a single-source app shows the first seven characters of its revision" do
    billing = rows.find { |row| row.name == "billing-api" }

    assert_equal "38b95bf", billing.revision
    assert_nil billing.source_count
  end

  test "a multi-source app has no revision and counts its sources instead" do
    job_runner = rows.find { |row| row.name == "job-runner" }

    assert_nil job_runner.revision
    assert_equal 3, job_runner.source_count
    assert_equal "team-apps", job_runner.namespace
  end
end
