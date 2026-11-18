#!/usr/bin/env ruby
# frozen_string_literal: true

# Publishes this private Gitea repository to its public GitHub repository, without a mirror.
#
# GitHub keeps its own history. The job finds the newest Gitea commit whose files (minus the private ones) equal GitHub main,
# then adds one GitHub commit per later Gitea commit, with the same message, author and dates, and pushes main. A push to a v* tag
# also puts the tag on the GitHub commit with the same files, which starts the release workflow there.
#
#   ruby .gitea/publish.rb                 # dry run: say what would be published, push nothing
#   ruby .gitea/publish.rb --apply         # publish main (and the tag, when GITHUB_REF is refs/tags/v*)
#
# Environment: PUBLISH_GITHUB_TOKEN (contents and workflows write on the public repository), PUBLISH_GITHUB_REPOSITORY
# (owner/name, for example rubylode/redmine-rubylode-argocd), GITHUB_REF and GITHUB_SHA from the runner.
# It never force-pushes: if GitHub main moved on its own, the push is refused and the job fails.

require "open3"
require "tmpdir"

EXCLUDED_PATHS = %w[.gitea CLAUDE.md .claude .publish-exclude].freeze
PRIVATE_PATTERNS = [/(\A|\/)\.env(\.(?!example(\/|\z))[^\/]*)?(\/|\z)/, /(\A|\/)CLAUDE\.md\z/, /(\A|\/)\.claude\//, /\.(pem|key|p12)\z/, /(\A|\/)id_(rsa|ed25519)/].freeze
SEARCH_DEPTH = 500

apply = ARGV.delete("--apply")
abort "usage: ruby #{$PROGRAM_NAME} [--apply]" unless ARGV.empty?

def fail_with(message)
  warn "FAILED: #{message}"
  exit 1
end

def git(*arguments, environment: {})
  output, status = Open3.capture2e(environment, "git", *arguments)
  fail_with "git #{arguments.first}: #{output.gsub(ENV.fetch('PUBLISH_GITHUB_TOKEN', 'none'), '***')}" unless status.success?
  output.strip
end

# The extra excluded paths as the commit itself lists them in .publish-exclude, so an older commit is judged by its own list
# and not by today's when finding where GitHub stands. What is published leaves out both lists, so a file named in the
# list after it was committed still stays private. The list itself is never published.
def extra_excludes(commit)
  listed, status = Open3.capture2e("git", "show", "#{commit}:.publish-exclude")
  return [] unless status.success?

  listed.lines(chomp: true).map(&:strip).reject { _1.empty? || _1.start_with?("#") }
end

# The tree of a commit as it would look on GitHub: the commit's files minus the excluded paths. The index is a scratch
# file, so -f: without it git refuses when an excluded file differs between this commit, HEAD and the working copy.
def public_tree(commit, index_file, also_excluded = [])
  environment = { "GIT_INDEX_FILE" => index_file }
  git("read-tree", commit, environment: environment)
  git("rm", "--cached", "-r", "-q", "-f", "--ignore-unmatch", "--", *(EXCLUDED_PATHS + extra_excludes(commit) + also_excluded).uniq, environment: environment)
  git("write-tree", environment: environment)
end

token = ENV.fetch("PUBLISH_GITHUB_TOKEN") { fail_with "PUBLISH_GITHUB_TOKEN is not set" }
repository = ENV.fetch("PUBLISH_GITHUB_REPOSITORY") { fail_with "PUBLISH_GITHUB_REPOSITORY is not set" }
reference = ENV.fetch("GITHUB_REF", "refs/heads/main")
source = ENV.fetch("GITHUB_SHA") { git("rev-parse", "HEAD") }
remote = "https://x-access-token:#{token}@github.com/#{repository}.git"
tag = reference.start_with?("refs/tags/v") ? reference.delete_prefix("refs/tags/") : nil

# A tag run publishes main up to the tagged commit, so a tag on a commit that is not on Gitea main would put that commit on
# GitHub main. Refuse it.
if tag
  git("fetch", "--quiet", "--no-tags", "origin", "+refs/heads/main:refs/publish/origin-main")
  _output, on_main = Open3.capture2e("git", "merge-base", "--is-ancestor", source, "refs/publish/origin-main")
  fail_with "#{tag} points at #{source[0, 7]}, which is not on Gitea main; tag a commit on main" unless on_main.success?
end

puts apply ? "APPLY: publishing to github.com/#{repository}" : "DRY RUN: nothing is pushed to github.com/#{repository}"

git("fetch", "--quiet", "--no-tags", remote, "+refs/heads/main:refs/publish/github-main")
github_head = git("rev-parse", "refs/publish/github-main")
github_tree = git("rev-parse", "#{github_head}^{tree}")

current_excludes = extra_excludes(source)

Dir.mktmpdir("publish") do |scratch|
  index_file = File.join(scratch, "index")
  history = git("rev-list", "--first-parent", "--max-count=#{SEARCH_DEPTH}", source).lines.map(&:strip)
  base_position = history.index { public_tree(_1, index_file) == github_tree }
  fail_with "no Gitea commit in the last #{SEARCH_DEPTH} has the same files as GitHub main #{github_head[0, 7]}; publish by hand once" unless base_position

  pending = history.first(base_position).reverse
  puts "GitHub main #{github_head[0, 7]} has the files of Gitea #{history[base_position][0, 7]}; #{pending.size} commit(s) to publish"

  parent = github_head
  parent_tree = github_tree
  pending.each do |commit|
    tree = public_tree(commit, index_file, current_excludes)
    subject = git("log", "-1", "--format=%s", commit)
    if tree == parent_tree
      puts "skip #{commit[0, 7]} #{subject} (only private files changed)"
      next
    end
    # Every path in the public tree, not only the added ones: a rename would not show as an addition.
    # NUL-separated, so unusual names reach the patterns raw and not in git's quoted form.
    leaking = git("ls-tree", "-r", "-z", "--name-only", tree).split("\0").select { |path| PRIVATE_PATTERNS.any? { _1.match?(path) } }
    fail_with "#{commit[0, 7]} would publish private-looking files: #{leaking.join(', ')}; add them to .publish-exclude" unless leaking.empty?

    fields = git("log", "-1", "--format=%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI", commit).split("\0")
    environment = %w[GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE].zip(fields).to_h
    message = git("log", "-1", "--format=%B", commit)
    parent = Open3.capture2(environment, "git", "commit-tree", tree, "-p", parent, stdin_data: "#{message}\n").first.strip
    fail_with "commit-tree failed for #{commit[0, 7]}" if parent.empty?
    parent_tree = tree
    puts "publish #{commit[0, 7]} -> #{parent[0, 7]} #{subject}"
  end

  if parent == github_head
    puts "main: nothing new"
  elsif apply
    git("push", "--quiet", remote, "#{parent}:refs/heads/main")
    puts "ok: pushed main #{github_head[0, 7]}..#{parent[0, 7]}"
  else
    puts "would push main #{github_head[0, 7]}..#{parent[0, 7]}"
  end

  next unless tag

  wanted_tree = public_tree(git("rev-parse", "#{tag}^{commit}"), index_file, current_excludes)
  candidates = git("log", "--format=%H %T", "--max-count=#{SEARCH_DEPTH}", parent).lines.map(&:split)
  target = candidates.find { _2 == wanted_tree }&.first
  fail_with "#{tag}: no published commit has its files; push main first" unless target
  existing = git("ls-remote", "--tags", remote, "refs/tags/#{tag}")
  if !existing.empty?
    puts "#{tag}: already on GitHub, left as it is"
  elsif apply
    # An annotated tag with the Gitea tag's message and tagger, built directly so its name is the real tag name.
    message = git("tag", "-l", "--format=%(contents)", tag)
    message = "#{tag}\n" if message.empty?
    tagger = git("for-each-ref", "--format=%(taggername) %(taggeremail) %(taggerdate:raw)", "refs/tags/#{tag}")
    tagger = git("log", "-1", "--format=%cn <%ce> %ct %cz", target) if tagger.strip.empty? || tagger.start_with?(" ")
    object = "object #{target}\ntype commit\ntag #{tag}\ntagger #{tagger}\n\n#{message.chomp}\n"
    tag_object, status = Open3.capture2("git", "mktag", stdin_data: object)
    fail_with "mktag failed for #{tag}" unless status.success?
    git("push", "--quiet", remote, "#{tag_object.strip}:refs/tags/#{tag}")
    puts "ok: tagged #{tag} on GitHub commit #{target[0, 7]}; the release workflow there builds the zip"
  else
    puts "would tag #{tag} on GitHub commit #{target[0, 7]}"
  end
end
