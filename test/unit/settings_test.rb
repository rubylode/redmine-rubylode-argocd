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

class RubylodeArgocd::SettingsTest < ActiveSupport::TestCase
  def settings_with(values)
    RubylodeArgocd::Settings.new(values)
  end

  {
    "cache_seconds" => 60,
    "failure_cache_seconds" => 30,
    "timeout_seconds" => 3
  }.each do |key, default|
    test "an empty #{key} reads as the default" do
      assert_equal default, settings_with(key => "").public_send(key)
      assert_equal default, settings_with(key => "  ").public_send(key)
    end

    test "a missing or nil #{key} reads as the default" do
      assert_equal default, settings_with({}).public_send(key)
      assert_equal default, settings_with(key => nil).public_send(key)
    end

    test "a typed #{key} wins over the default" do
      assert_equal 7, settings_with(key => "7").public_send(key)
    end

    test "a #{key} that is not a number reads as the default" do
      assert_equal default, settings_with(key => "soon").public_send(key)
    end
  end

  test "a cache time typed as 0 stays 0, which turns caching off" do
    assert_equal 0, settings_with("cache_seconds" => "0").cache_seconds
    assert_equal 0, settings_with("failure_cache_seconds" => "0").failure_cache_seconds
  end

  test "a timeout of 0 is raised to 1 second" do
    assert_equal 1, settings_with("timeout_seconds" => "0").timeout_seconds
  end

  test "the defaults match the ones the plugin registers" do
    registered = Redmine::Plugin.find(RubylodeArgocd::Settings::PLUGIN_ID).settings[:default]
    %w[cache_seconds failure_cache_seconds timeout_seconds].each do |key|
      assert_equal registered[key].to_i, settings_with({}).public_send(key), key
    end
  end
end
