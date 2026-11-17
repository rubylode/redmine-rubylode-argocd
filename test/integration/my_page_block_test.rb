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

class RubylodeArgocdMyPageBlockTest < Redmine::IntegrationTest
  include RubylodeArgocdTestHelpers

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :issue_statuses, :trackers, :projects_trackers, :enumerations, :enabled_modules

  setup do
    use_memory_cache
    start_fake_argocd
  end

  teardown do
    stop_fake_argocd
    restore_cache
  end

  test "the block is in Redmine's list of My page blocks" do
    assert Redmine::MyPage.blocks.key?("rubylode_argocd_status")
    assert_includes Redmine::MyPage.block_options.map(&:last), "rubylode_argocd_status"
  end

  test "a person who added the block sees the status on My page" do
    preference = User.find(2).pref
    preference.my_page_layout = { "top" => ["rubylode_argocd_status"] }
    preference.save!

    log_user("jsmith", "jsmith")
    get "/my/page"

    assert_response :success
    assert_select "#block-rubylode_argocd_status .rubylode-argocd-summary", text: "3 of 13 need attention"
  end
end
