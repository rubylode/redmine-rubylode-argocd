#!/usr/bin/env ruby
# frozen_string_literal: true

# Rubylode Argo CD: application status from Argo CD for Redmine
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

require "json"
require "fileutils"

# Builds the fake Argo CD server's fixtures from answers captured from a real Argo CD.
#
#   ruby script/scrub_fixtures.rb RAW_FOLDER [OUTPUT_FOLDER]
#
# RAW_FOLDER is outside the repository and holds the raw answers, one body per file:
#
#   version.body            GET /api/version
#   applications.body       GET /api/v1/applications with the plugin's `fields` parameter
#   resource_tree.body      GET /api/v1/applications/<name>/resource-tree for one app
#   resource_tree.app       the name of that app, one line
#   bad_token.body          the answer to a bad token
#   missing_app.body        the answer for an app that does not exist
#
# Every object is rebuilt from a list of keys the plugin reads, so whatever the script does not know about (hosts, node
# names, network details, Helm values) is left out rather than copied. Every name, namespace, project, repository,
# image, revision and uid is replaced by a made-up value. The cases a quiet cluster lacks are then filled in: a Degraded
# app with a failing pod, an OutOfSync app, a Missing app outside the default namespace.
#
# Last, every string in the raw answers is looked for in the output. The real values replaced and any that survive
# are written to RAW_FOLDER (never printed), and the script fails if a real value survives that is not ordinary
# Argo CD or Kubernetes vocabulary.
class FixtureScrubber
  APP_NAMES = %w[
    billing-api web job-runner search-index ledger notifications reports gateway inventory checkout mailer scheduler
    auth-service images analytics exporter
  ].freeze
  RESOURCE_NAMESPACES = %w[shop payments storefront telemetry data queue].freeze
  PROJECTS = %w[shop storefront data].freeze
  # A custom resource's group and kind say what software the cluster runs, so any group outside Kubernetes and Argo CD
  # becomes one of these.
  CUSTOM_GROUPS = %w[widgets.example.com gadgets.example.com gizmos.example.com sprockets.example.com].freeze
  CUSTOM_KINDS = %w[Widget Gadget Gizmo Sprocket Doohickey Contraption Thingamajig Whatsit].freeze
  KNOWN_GROUPS = %w[apps batch policy autoscaling argoproj.io].freeze
  DEFAULT_APP_NAMESPACE = "argocd"
  OTHER_APP_NAMESPACE = "team-apps"

  APPLICATION_KEYS = %w[metadata spec status].freeze
  RESOURCE_KEYS = %w[group version kind namespace name status health syncWave hook requiresPruning].freeze
  NODE_KEYS = %w[group version kind namespace name uid parentRefs info images health createdAt resourceVersion].freeze
  POD_INFO_KEYS = ["Status Reason", "Containers"].freeze
  SOURCE_KEYS = %w[repoURL path chart targetRevision ref].freeze

  # Strings in the raw answers that may appear in the fixtures because they name nothing of the cluster's.
  VOCABULARY = %w[
    Healthy Progressing Degraded Suspended Missing Unknown Synced OutOfSync Running Completed Succeeded
    Pod ReplicaSet Deployment StatefulSet DaemonSet Service Endpoints EndpointSlice ConfigMap Secret Job CronJob
    Ingress ServiceAccount Role RoleBinding ClusterRole ClusterRoleBinding PersistentVolumeClaim PodDisruptionBudget
    HorizontalPodAutoscaler NetworkPolicy CustomResourceDefinition Namespace Certificate ServiceMonitor
    Application APIService IngressClass LimitRange ResourceQuota PersistentVolume ValidatingWebhookConfiguration
    ValidatingAdmissionPolicy ValidatingAdmissionPolicyBinding ContainerCreating
    apps batch policy autoscaling argoproj.io networking.k8s.io rbac.authorization.k8s.io discovery.k8s.io
    v1 v2 v1beta1 v1alpha1 default argocd main HEAD values Sync Update Revision Containers
  ].freeze + ["Status Reason", "Waiting for rollout to finish: 1 old replicas are pending termination..."]

  def initialize(raw_folder, output_folder)
    @raw_folder = raw_folder
    @output_folder = output_folder
    @random = Random.new(20_261_116)
    @replacements = Hash.new { |hash, category| hash[category] = {} }
    @app_names_left = APP_NAMES.dup
  end

  def run
    version = read_json("version.body")
    applications = read_json("applications.body").fetch("items")
    tree = read_json("resource_tree.body")
    tree_app = File.read(File.join(@raw_folder, "resource_tree.app")).strip

    # The fixtures are rebuilt whole, so a renamed app leaves no stale resource tree behind.
    Dir[File.join(@output_folder, "**", "*.json")].each { |path| File.delete(path) }

    items = applications.map { |app| scrub_application(app) }
    trees = { fake("app", tree_app) { next_app_name } => scrub_tree(tree, fake("app", tree_app) { next_app_name }) }
    synthesise_cases(items, trees)

    write("version.json", "Version" => version.fetch("Version"))
    write("applications.json", "metadata" => { "resourceVersion" => "1000" }, "items" => items)
    trees.each { |name, nodes| write("resource_trees/#{name}.json", "nodes" => nodes) }
    write("errors/unauthorized.json", read_json("bad_token.body"))
    write("errors/permission_denied.json", read_json("missing_app.body"))

    check_for_survivors
  end

  private

  def read_json(name)
    JSON.parse(File.read(File.join(@raw_folder, name)))
  end

  def write(relative_path, data)
    path = File.join(@output_folder, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{JSON.pretty_generate(data)}\n")
  end

  # The same real value always gets the same made-up one.
  def fake(category, real)
    return real if real.nil? || real == ""

    @replacements[category][real] ||= yield
  end

  def next_app_name
    @app_names_left.shift || "app-#{@random.rand(1000..9999)}"
  end

  def hex(length)
    Array.new(length) { "0123456789abcdef"[@random.rand(16)] }.join
  end

  def alphanumeric(length)
    Array.new(length) { "bcdfghjklmnpqrstvwxz2456789"[@random.rand(27)] }.join
  end

  def uid
    [hex(8), hex(4), hex(4), hex(4), hex(12)].join("-")
  end

  def namespace(real)
    return real if real == DEFAULT_APP_NAMESPACE

    fake("namespace", real) do
      index = @replacements["namespace"].size
      RESOURCE_NAMESPACES[index] || "namespace-#{index + 1}"
    end
  end

  def project(real)
    return real if real == "default"

    fake("project", real) { PROJECTS[@replacements["project"].size] || "project-#{@replacements["project"].size + 1}" }
  end

  # A resource takes its app's name; a second resource of the same name gets its kind added, as charts usually do.
  def resource_name(real, kind, app_name, parent_name = nil)
    # Keyed by app as well: two apps may each have a resource of the same name, and each keeps its own.
    fake("resource", [app_name, real]) do
      candidate =
        case kind
        when "ReplicaSet" then "#{parent_name || app_name}-#{hex(10)}"
        when "Pod" then "#{parent_name || app_name}-#{alphanumeric(5)}"
        else app_name
        end
      candidate = "#{candidate}-#{kind.downcase}" if @replacements["resource"].value?(candidate)
      candidate = "#{candidate}-#{@replacements["resource"].size}" if @replacements["resource"].value?(candidate)
      candidate
    end
  end

  def scrub_application(app)
    name = fake("app", app.dig("metadata", "name")) { next_app_name }
    status = app.fetch("status", {})
    {
      "metadata" => { "name" => name, "namespace" => namespace(app.dig("metadata", "namespace")) },
      "spec" => scrub_spec(app.fetch("spec", {}), name),
      "status" => {
        "health" => scrub_health(status["health"]),
        "sync" => { "status" => status.dig("sync", "status"), "revision" => revision(status.dig("sync", "revision")) }.compact,
        "operationState" => { "finishedAt" => status.dig("operationState", "finishedAt") }.compact,
        "resources" => status.fetch("resources", []).map { |resource| scrub_resource(resource, name) }
      }
    }
  end

  def scrub_spec(spec, app_name)
    scrubbed = { "project" => project(spec["project"]) }
    scrubbed["sources"] = spec["sources"].map { |source| scrub_source(source, app_name) } if spec["sources"]
    scrubbed
  end

  def scrub_source(source, app_name)
    source.slice(*SOURCE_KEYS).to_h do |key, value|
      [key, case key
            when "repoURL" then fake("repository", value) { "https://git.example.com/acme/repository-#{@replacements["repository"].size + 1}.git" }
            when "path" then "deploy/#{app_name}"
            when "chart" then fake("chart", value) { "chart-#{@replacements["chart"].size + 1}" }
            when "targetRevision" then "main"
            when "ref" then "values"
            end]
    end
  end

  def revision(real)
    fake("revision", real) { hex(40) }
  end

  # Argo CD's health messages name the resources they are about, so they are replaced by ordinary ones.
  def scrub_health(health, kind: nil, name: nil)
    return nil unless health

    message = health["message"] && health_message(health["status"], kind, name)
    { "status" => health["status"], "message" => message }.compact
  end

  def health_message(status, kind, name)
    case [status, kind]
    in ["Progressing", "Deployment" | nil] then "Waiting for rollout to finish: 1 old replicas are pending termination..."
    in ["Progressing", _] then "Waiting for #{kind.downcase} #{name} to become ready"
    in ["Degraded", "Pod"] then "back-off 5m0s restarting failed container=app pod=#{name}"
    in ["Degraded", _] then "Deployment \"#{name}\" exceeded its progress deadline"
    in ["Healthy", "Job"] then "Job has reached the specified number of completions"
    in ["Missing", _] then nil
    else nil
    end
  end

  def known_group?(group)
    group.nil? || group == "" || KNOWN_GROUPS.include?(group) || group.end_with?(".k8s.io")
  end

  # Replaces a custom resource's group and kind in place; Kubernetes and Argo CD ones stay.
  def scrub_group_and_kind(object)
    return object if known_group?(object["group"])

    object["group"] = fake("group", object["group"]) { CUSTOM_GROUPS[@replacements["group"].size] || "group-#{@replacements["group"].size + 1}.example.com" }
    object["kind"] = fake("kind", object["kind"]) { CUSTOM_KINDS[@replacements["kind"].size] || "Kind#{@replacements["kind"].size + 1}" }
    object
  end

  def scrub_resource(resource, app_name)
    scrubbed = scrub_group_and_kind(resource.slice(*RESOURCE_KEYS))
    scrubbed["namespace"] = namespace(resource["namespace"]) if resource["namespace"]
    scrubbed["name"] = resource_name(resource["name"], scrubbed["kind"], app_name)
    scrubbed["health"] = scrub_health(resource["health"], kind: scrubbed["kind"], name: scrubbed["name"]) if resource["health"]
    scrubbed
  end

  # Parents first, so a pod's name can grow out of its replica set's.
  def scrub_tree(tree, app_name)
    nodes = tree.fetch("nodes")
    by_uid = nodes.to_h { |node| [node["uid"], node] }
    ordered = nodes.sort_by { |node| depth(node, by_uid) }
    ordered.map { |node| scrub_node(node, app_name, by_uid) }
  end

  def depth(node, by_uid, seen = [])
    parent = Array(node["parentRefs"]).map { |ref| by_uid[ref["uid"]] }.compact.first
    return 0 if parent.nil? || seen.include?(parent["uid"])

    1 + depth(parent, by_uid, seen + [node["uid"]])
  end

  def scrub_node(node, app_name, by_uid)
    parent = Array(node["parentRefs"]).map { |ref| by_uid[ref["uid"]] }.compact.first
    parent_name = parent && @replacements["resource"][[app_name, parent["name"]]]
    scrubbed = scrub_group_and_kind(node.slice(*NODE_KEYS))
    name = resource_name(node["name"], scrubbed["kind"], app_name, parent_name)
    scrubbed["namespace"] = namespace(node["namespace"]) if node["namespace"]
    scrubbed["name"] = name
    scrubbed["uid"] = fake("uid", node["uid"]) { uid }
    scrubbed["resourceVersion"] = (1000 + @random.rand(9000)).to_s if node["resourceVersion"]
    scrubbed["health"] = scrub_health(node["health"], kind: scrubbed["kind"], name: name) if node["health"]
    scrubbed["images"] = ["registry.example.com/acme/#{app_name}:1.4.2"] if node["images"]
    if node["info"]
      kept = node["info"].select { |entry| POD_INFO_KEYS.include?(entry["name"]) }
      kept.empty? ? scrubbed.delete("info") : scrubbed["info"] = kept
    end
    if node["parentRefs"]
      scrubbed["parentRefs"] = node["parentRefs"].map do |ref|
        group_and_kind = scrub_group_and_kind(ref.slice("group", "kind"))
        { "group" => group_and_kind["group"], "version" => ref["version"], "kind" => group_and_kind["kind"],
          "namespace" => ref["namespace"] && namespace(ref["namespace"]),
          "name" => @replacements["resource"][[app_name, ref["name"]]] || resource_name(ref["name"], group_and_kind["kind"], app_name),
          "uid" => fake("uid", ref["uid"]) { uid } }.compact
      end
    end
    scrubbed
  end

  # A quiet cluster is all Healthy and Synced. Turn three of its apps into the cases the plugin has to show.
  def synthesise_cases(items, trees)
    make_progressing_where_the_tree_says_so(items, trees)
    healthy = items.select { |app| app.dig("status", "health", "status") == "Healthy" && app.dig("status", "sync", "status") == "Synced" }
    single, multiple = healthy.partition { |app| app.dig("spec", "sources").nil? }
    degraded = single.first || healthy.first
    out_of_sync = (multiple - [degraded]).first
    missing = (healthy - [degraded, out_of_sync]).first
    raise "the capture needs at least three Healthy and Synced apps" unless degraded && out_of_sync && missing

    make_degraded(degraded, trees)
    make_out_of_sync(out_of_sync)
    make_missing(missing, trees)
  end

  # The list and the tree are two calls; an app caught mid-rollout in the tree may be Healthy again in the list.
  def make_progressing_where_the_tree_says_so(items, trees)
    trees.each do |name, nodes|
      next unless nodes.any? { |node| node.dig("health", "status") == "Progressing" }

      app = items.find { |item| item.dig("metadata", "name") == name }
      app["status"]["health"] = { "status" => "Progressing", "message" => health_message("Progressing", nil, nil) } if app
    end
  end

  def make_degraded(app, trees)
    name = app.dig("metadata", "name")
    resource_namespace = app.dig("status", "resources").filter_map { |resource| resource["namespace"] }.first || "shop"
    app["status"]["health"] = { "status" => "Degraded", "message" => "Deployment \"#{name}\" exceeded its progress deadline" }
    app["status"]["resources"].each do |resource|
      resource["health"] = { "status" => "Degraded", "message" => "Deployment \"#{name}\" exceeded its progress deadline" } if resource["kind"] == "Deployment"
    end
    deployment_uid = uid
    replica_set = "#{name}-#{hex(10)}"
    replica_set_uid = uid
    pod = "#{replica_set}-#{alphanumeric(5)}"
    created = "2026-11-16T09:12:04Z"
    trees[name] = [
      { "group" => "apps", "version" => "v1", "kind" => "Deployment", "namespace" => resource_namespace, "name" => name,
        "uid" => deployment_uid, "health" => { "status" => "Degraded", "message" => "Deployment \"#{name}\" exceeded its progress deadline" },
        "createdAt" => created, "resourceVersion" => "4211" },
      { "group" => "apps", "version" => "v1", "kind" => "ReplicaSet", "namespace" => resource_namespace, "name" => replica_set,
        "uid" => replica_set_uid, "parentRefs" => [{ "group" => "apps", "kind" => "Deployment", "namespace" => resource_namespace, "name" => name, "uid" => deployment_uid }],
        "health" => { "status" => "Progressing", "message" => "Waiting for rollout to finish: 0 of 1 updated replicas are available..." },
        "createdAt" => created, "resourceVersion" => "4212" },
      { "version" => "v1", "kind" => "Pod", "namespace" => resource_namespace, "name" => pod, "uid" => uid,
        "parentRefs" => [{ "group" => "apps", "kind" => "ReplicaSet", "namespace" => resource_namespace, "name" => replica_set, "uid" => replica_set_uid }],
        "info" => [{ "name" => "Status Reason", "value" => "CrashLoopBackOff" }, { "name" => "Containers", "value" => "0/1" }],
        "images" => ["registry.example.com/acme/#{name}:1.4.3"],
        "health" => { "status" => "Degraded", "message" => "back-off 5m0s restarting failed container=app pod=#{pod}" },
        "createdAt" => created, "resourceVersion" => "4230" },
      { "version" => "v1", "kind" => "Service", "namespace" => resource_namespace, "name" => name, "uid" => uid,
        "health" => { "status" => "Healthy" }, "createdAt" => "2026-10-02T14:40:11Z", "resourceVersion" => "1180" }
    ]
  end

  def make_out_of_sync(app)
    app["status"]["sync"]["status"] = "OutOfSync"
    app["status"]["resources"].first["status"] = "OutOfSync" if app["status"]["resources"].any?
  end

  # Argo CD's tree holds live objects only, so a Missing app's tree is empty.
  def make_missing(app, trees)
    app["metadata"]["namespace"] = OTHER_APP_NAMESPACE
    app["status"]["health"] = { "status" => "Missing" }
    app["status"]["sync"]["status"] = "OutOfSync"
    app["status"]["resources"].each do |resource|
      resource["status"] = "OutOfSync"
      resource["health"] = { "status" => "Missing" }
    end
    trees[app.dig("metadata", "name")] = []
  end

  def check_for_survivors
    raw_strings = Dir[File.join(@raw_folder, "*.body")].flat_map { |path| strings_in(parse_or_text(File.read(path))) }
    raw_strings += @replacements.values.flat_map(&:keys).map { |key| key.is_a?(Array) ? key.last : key }
    raw_strings = raw_strings.uniq.select { |value| value.length >= 4 } - VOCABULARY
    output = Dir[File.join(@output_folder, "**", "*.json")].map { |path| File.read(path) }.join("\n")
    survivors = raw_strings.select { |value| output.include?(value) }
    ignorable = survivors.select { |value| ignorable?(value) }
    real = survivors - ignorable

    replaced = @replacements.flat_map { |category, pairs| pairs.keys.map { |value| "#{category}\t#{value}" } }
    File.write(File.join(@raw_folder, "replaced.txt"), replaced.join("\n"))
    File.write(File.join(@raw_folder, "survivors.txt"), survivors.map { |value| "#{real.include?(value) ? "REAL" : "ok"}\t#{value}" }.join("\n"))
    puts "#{replaced.size} real values replaced (#{@replacements.map { |category, pairs| "#{pairs.size} #{category}" }.join(", ")})"
    puts "#{survivors.size} raw strings appear in the fixtures: #{ignorable.size} ordinary, #{real.size} not (both listed in survivors.txt in the raw folder)"
    exit(real.empty? ? 0 : 1)
  end

  def parse_or_text(body)
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end

  def strings_in(value)
    case value
    when Hash then value.values.flat_map { |nested| strings_in(nested) }
    when Array then value.flat_map { |nested| strings_in(nested) }
    when String then [value]
    else []
    end
  end

  # Timestamps, Argo CD's own error text, Kubernetes API words and pod states name nothing of the cluster's.
  def ignorable?(value)
    value.match?(/\A\d{4}-\d{2}-\d{2}T[\d:.]+Z\z/) ||
      value.match?(/\Av\d+\.\d+\.\d+/) ||
      %w[no\ session\ information permission\ denied CrashLoopBackOff].include?(value) ||
      value.match?(/\A\d+\/\d+\z/) ||
      value.match?(/\A[a-z]+(\.[a-z0-9-]+)*\.k8s\.io\z/)
  end
end

if $PROGRAM_NAME == __FILE__
  raw_folder = ARGV.fetch(0) { abort "usage: ruby script/scrub_fixtures.rb RAW_FOLDER [OUTPUT_FOLDER]" }
  output_folder = ARGV.fetch(1, File.expand_path("../test/support/fixtures/argocd", __dir__))
  FixtureScrubber.new(raw_folder, output_folder).run
end
