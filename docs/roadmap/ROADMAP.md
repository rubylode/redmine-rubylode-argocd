# Roadmap

## Goal

Show the state of the applications Argo CD manages inside Redmine: healthy or not, in sync with git or not, and which
resources are failing, without a second login and without leaking a token.

## Next

1. ~~Write the implementation plan~~ done 2026-11-16: `docs/plans/argocd-status/`.
2. Capture sample answers from the development Argo CD (see `.env.example`) and build the scrubbed fixtures and the
   fake server: `docs/plans/argocd-status/00-fixtures.md`.
3. Build the plugin from the Rubylode Beszel layout, test first, one slice per session: `01-tracer.md` through
   `06-settings-page.md` in `docs/plans/argocd-status/`.

### Session brief

Next slice: `docs/plans/argocd-status/00-fixtures.md`. Start from a session launched with the project's `.env` so
both `ARGOCD_DEVELOPMENT_*` variables are set. Raw captures go to the session scratch folder, never the repository.
4. Screenshots, README, CHANGELOG, then release 1.0.0 the way Rubylode Beszel does, after creating the remote.

## Ideas

- Extract the helpers every Rubylode plugin copies (`path_matcher`, `settings_validator`, `status_widget`, transport
  rules) into one shared gem.
- A sibling plugin for the cluster itself: nodes, pods, CPU and memory through the Kubernetes API and metrics-server.
