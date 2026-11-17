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
   `06-settings-page.md` in `docs/plans/argocd-status/`. Slice 1 done 2026-11-17, 7e0510e, c1f7283.
4. Screenshots, README, CHANGELOG, then release 1.0.0 the way Rubylode Beszel does, after creating the remote.

### Session brief

Current state: c1f7283, `bin/test` 7 runs, 40 assertions, green on the Redmine 7.0 image (the 5.1 to 7.0 CI matrix
has not run yet: no remote). `/status/argocd` shows one instance's apps for administrators. Not yet handled: an
unreachable instance raises on the page, no failure cache, a Cache seconds of 0, transport rules, visibility.

Next slice: `02-failing-resources.md` or `03-several-instances.md` (either order; 3 first fixes the error path), in a
fresh session. The fixtures cover every case. Read the spec's Data section first: on Argo CD 3.x resource health
comes only from the resource tree, and `job-runner` (namespace `team-apps`) needs `appNamespace`. The fake server's
apps: `billing-api` Degraded with a failing pod, `web` OutOfSync, `job-runner` Missing, `notifications` Progressing,
ten multi-source.

## Log

- 2026-11-17: fixtures and fake server done; spec corrected against Argo CD 3.6.1.
- 2026-11-17: slice 1 (tracer) done: skeleton copied from Beszel, one instance's apps on `/status/argocd`.

## Ideas

- Extract the helpers every Rubylode plugin copies (`path_matcher`, `settings_validator`, `status_widget`, transport
  rules) into one shared gem.
- A sibling plugin for the cluster itself: nodes, pods, CPU and memory through the Kubernetes API and metrics-server.
