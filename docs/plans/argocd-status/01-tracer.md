# 1. Tracer: one instance on the status page

Blocked by slice 0.

## Done means

With one instance line in the settings, an administrator opening `/status/argocd` sees a table of that instance's apps
(name linked to the Argo CD UI, project, health, sync, last sync, short revision), served from the fake server, and
the test suite runs on the Redmine 5.1 to 7.0 matrix in CI.

## Prefactoring (first commit, no behaviour)

Copy the Beszel skeleton (see the plan README): `init.rb` registering `redmine_rubylode_argocd`, the routes, the
controller and an empty page, locales, stylesheet, `bin/test`, the Docker test setup, the workflows, the test helper.
The suite runs green with one smoke test that the plugin is registered.

## Tests, in order (red, then green, one at a time)

1. Seam 2: the status model turns the applications fixture into rows with name, namespace, project, health, sync,
   finished-at time and a seven-character revision; a multi-source app shows its first revision.
2. Seam 1: an administrator gets the page with one row per app in the fixture; names link to the UI path confirmed
   in slice 0.
3. Seam 1: the request to the fake server carries `Authorization: Bearer <token>` read from the variable named in the
   instance line, and asks for the trimmed `fields`.
4. Seam 1: a second request within Cache seconds does not reach the fake server.

## Pieces

Settings reader for the instance line (just enough for one line), an Argo CD client adapted from Windmill's, the
status model, a cache keyed per instance, the page view. Keep the instance line parser ready for many lines but test
only one here.
