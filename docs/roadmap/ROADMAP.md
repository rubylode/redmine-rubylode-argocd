# Roadmap

## Goal

Show the state of the applications Argo CD manages inside Redmine: healthy or not, in sync with git or not, and which
resources are failing, without a second login and without leaking a token.

## Next

1. ~~Write the implementation plan~~ done 2026-11-16: `docs/plans/argocd-status/`.
2. ~~Capture sample answers from the development Argo CD and build the scrubbed fixtures and the fake server~~
   done 2026-11-17, 963232c, f79f3bc: `test/support/fixtures/argocd/`, `test/support/fake_argocd_server.rb`,
   `script/scrub_fixtures.rb`.
3. Build the plugin from the Rubylode Beszel layout, test first, one slice per session: `01-tracer.md` through
   `06-settings-page.md` in `docs/plans/argocd-status/`.
4. Screenshots, README, CHANGELOG, then release 1.0.0 the way Rubylode Beszel does, after creating the remote.

### Session brief

Next slice: `docs/plans/argocd-status/01-tracer.md`, in a fresh session. The development Argo CD is not needed for
slices 1 to 6: the fixtures cover every case. Read the spec's Data section first: `fields` is an allowlist,
multi-source apps show "N sources", on Argo CD 3.x resource health comes only from the resource tree, and the HTTP
client sets `max_retries = 0`. The fake server's apps: `billing-api` Degraded with a failing pod, `web` OutOfSync,
`job-runner` Missing in namespace `team-apps`, `notifications` Progressing, ten multi-source.

## Log

- 2026-11-17: fixtures and fake server done; spec corrected against Argo CD 3.6.1.

## Ideas

- Extract the helpers every Rubylode plugin copies (`path_matcher`, `settings_validator`, `status_widget`, transport
  rules) into one shared gem.
- A sibling plugin for the cluster itself: nodes, pods, CPU and memory through the Kubernetes API and metrics-server.
