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

class RubylodeArgocdWikiMacroTest < Redmine::IntegrationTest
  include RubylodeArgocdTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :issue_statuses, :trackers,
           :projects_trackers, :enumerations, :enabled_modules, :wikis, :wiki_pages, :wiki_contents, :wiki_content_versions

  setup do
    use_memory_cache
    start_fake_argocd
  end

  teardown do
    stop_fake_argocd
    restore_cache
  end

  def get_wiki_page(text, login: "jsmith")
    page = WikiPage.new(wiki: Project.find(1).wiki, title: "Status_#{SecureRandom.hex(3)}")
    page.content = WikiContent.new(text: text, author: User.find(2))
    page.save!
    log_user(login, login)
    get "/projects/ecookbook/wiki/#{page.title}"
    assert_response :success
  end

  test "the macro draws the status block inside the wiki page" do
    get_wiki_page("Our apps:\n\n{{argocd_status}}")

    assert_select ".wiki .rubylode-argocd-summary", text: "3 of 13 need attention"
    assert_select ".wiki td.rubylode-argocd-name a", text: "billing-api"
  end

  test "the macro takes a title" do
    get_wiki_page("{{argocd_status(title=Customer-facing)}}")

    assert_select ".wiki h3.rubylode-argocd-title", text: /\ACustomer-facing/
  end

  test "the macro uses the block title setting when it has no title" do
    configure_plugin("instances" => "Production | #{@fake_argocd.url} | #{TOKEN_VARIABLE}", "block_title" => "Company apps")
    get_wiki_page("{{argocd_status}}")

    assert_select ".wiki h3.rubylode-argocd-title", text: /\ACompany apps/
  end

  test "a person the permission setting excludes sees nothing where the macro stands" do
    configure_plugin("instances" => "Production | #{@fake_argocd.url} | #{TOKEN_VARIABLE}", "visibility" => "admins")
    get_wiki_page("before {{argocd_status}} after")

    assert_select ".wiki .rubylode-argocd", 0
    assert_select ".wiki", text: /before\s+after/
  end

  test "the macro is listed among the wiki macros" do
    assert Redmine::WikiFormatting::Macros.available_macros.key?(:argocd_status)
  end

  test "a wiki page still answers when every instance is down" do
    @fake_argocd.failure = "server_error"
    get_wiki_page("Intro\n\n{{argocd_status}}")

    assert_select ".wiki .rubylode-argocd-unavailable", text: "Status unavailable"
    assert_select ".wiki", text: /Intro/
  end
end
