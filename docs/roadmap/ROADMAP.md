# Roadmap

## Goal

Show the state of the applications Argo CD manages inside Redmine: healthy or not, in sync with git or not, and which
resources are failing, without a second login and without leaking a token.

## Next

1. ~~Write the implementation plan~~ done 2026-11-16: `docs/plans/argocd-status/`.
2. ~~Capture sample answers from the development Argo CD and build the scrubbed fixtures and the fake server~~
   done 2026-11-17, 963232c, f79f3bc: `test/support/fixtures/argocd/`, `test/support/fake_argocd_server.rb`,
   `script/scrub_fixtures.rb`.
3. ~~Build the plugin from the Rubylode Beszel layout, test first: `01-tracer.md` through `06-settings-page.md` in
   `docs/plans/argocd-status/`~~ done 2026-11-17, 7e0510e through a24e5f2; review fixes 8ba3fbf.
4. ~~README, CHANGELOG, then release 1.0.0 on GitHub the way Rubylode Beszel does~~ done 2026-11-17, c13df02, tag
   v1.0.0. Screenshots still to take.
5. Install the released 1.0.0 on the first production Redmine, from the GitHub release, and check the page there
   against its Argo CD.
6. After 1.0: cache the extracted rows instead of the raw answer (Memcached's 1 MB item limit); optionally pin each
   token to a host set in the environment; mirror the repository from the household Gitea like the other plugins.
### Session brief

Current state: 1.0.0, `bin/test` 128 runs, 802 assertions, green on the Redmine 7.0 image; CI runs the 5.1 to 7.0
matrix on GitHub. Every slice of the plan is built. Next: install from the GitHub release on the first production
Redmine (item 5), then the after-1.0 items.

## Log

- 2026-11-17: fixtures and fake server done; spec corrected against Argo CD 3.6.1.
- 2026-11-17: slice 1 (tracer) done: skeleton copied from Beszel, one instance's apps on `/status/argocd`.
- 2026-11-17: slices 2 to 6, a security review and its fixes, README and CHANGELOG; released 1.0.0.

## Ideas

- Extract the helpers every Rubylode plugin copies (`path_matcher`, `settings_validator`, `status_widget`, transport
  rules) into one shared gem.
- A sibling plugin for the cluster itself: nodes, pods, CPU and memory through the Kubernetes API and metrics-server.
