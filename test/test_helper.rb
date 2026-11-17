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

require File.expand_path("../../../test/test_helper", __dir__)
require "logger"
require "stringio"
require_relative "support/fake_argocd_server"

module RubylodeArgocdTestHelpers
  PLUGIN_ID = "redmine_rubylode_argocd"
  TOKEN_VARIABLE = "ARGOCD_PRODUCTION_TOKEN"

  # Starts a fake Argo CD on a free port, points one instance line at it and puts its token in the environment.
  def start_fake_argocd(cache_seconds: "60")
    @fake_argocd = FakeArgocdServer.new.start
    ENV[TOKEN_VARIABLE] = FakeArgocdServer::TOKEN
    configure_plugin("instances" => "Production | #{@fake_argocd.url} | #{TOKEN_VARIABLE}", "cache_seconds" => cache_seconds)
    @fake_argocd
  end

  def stop_fake_argocd
    @fake_argocd&.stop
    ENV.delete(TOKEN_VARIABLE)
  end

  def configure_plugin(overrides = {})
    defaults = Redmine::Plugin.find(PLUGIN_ID).settings[:default]
    Setting.send(:"plugin_#{PLUGIN_ID}=", defaults.merge(overrides.transform_keys(&:to_s)))
  end

  def use_memory_cache
    @original_cache = RubylodeArgocd::ApplicationStatus.cache
    RubylodeArgocd::ApplicationStatus.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def restore_cache
    RubylodeArgocd::ApplicationStatus.cache = @original_cache
  end

  # Runs the block with Rails.logger writing into a string, and returns that string.
  def captured_log
    output = StringIO.new
    replacing_method(Rails, :logger, ->(*) { Logger.new(output) }) { yield }
    output.string
  end

  # Minitest 6 ships without stubs, so a singleton method is swapped by hand for the length of the block.
  def replacing_method(target, name, replacement)
    original = target.method(name)
    target.define_singleton_method(name) { |*arguments, &block| replacement.call(*arguments, &block) }
    yield
  ensure
    target.define_singleton_method(name) { |*arguments, &block| original.call(*arguments, &block) }
  end

  # Stands in for the Status plugin's registry for the length of the block, and records what is registered.
  # The Status plugin is not mounted next to this one in the test image, so the real registry is not available here.
  class FakeStatusRegistry
    attr_reader :calls

    def initialize
      @calls = []
    end

    def register(**arguments)
      @calls << arguments
    end
  end

  def with_fake_status_registry
    registry = FakeStatusRegistry.new
    registry_module = Module.new
    registry_module.define_singleton_method(:register) { |**arguments| registry.register(**arguments) }
    Object.const_set(:RubylodeStatus, Module.new)
    RubylodeStatus.const_set(:Registry, registry_module)
    yield registry
  ensure
    Object.send(:remove_const, :RubylodeStatus) if Object.const_defined?(:RubylodeStatus)
  end
end
