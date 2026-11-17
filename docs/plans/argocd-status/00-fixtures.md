# 0. Fixtures and the fake server

Roadmap item 2. Blocked by nothing. Needs `ARGOCD_DEVELOPMENT_URL` and `ARGOCD_DEVELOPMENT_TOKEN` in the environment
(the launcher loads them from `.env`); never print either.

## Done means

`test/support/fixtures/` holds scrubbed Argo CD answers, and `test/support/fake_argocd_server.rb` serves them, with
not one real name from the development cluster in the repository.

## Steps

1. Capture raw answers to the session scratch folder, never into the repository, with a small Ruby script that reads the
   two variables:
   - `GET /api/v1/version` (record the Argo CD version).
   - `GET /api/v1/applications`, once in full and once with the `fields` parameter the spec lists. Confirm the
     parameter is honoured and the trimmed answer still holds `status.resources`, `status.sync.revision(s)` and
     `status.operationState.finishedAt`.
   - `GET /api/v1/applications/<name>/resource-tree` for a Degraded app, or for any app if none is Degraded.
   - What a bad token returns (status and body), and what a missing app returns.
2. Confirm the UI path for an app (`/applications/<namespace>/<name>` or `/applications/<name>`) on this version and
   write the answer into the spec's Display section.
3. Build the fixtures from the raw answers by a committed scrub script (`script/scrub_fixtures.rb`) that maps every app,
   namespace, project, host, repository URL, image, pod name and revision to made-up values. It takes the raw folder
   as an argument, so the raw data never needs to live in the repository.
4. Hand-edit (or have the script synthesise) the cases the cluster lacks: at least one Degraded app with a resource tree
   holding a failing pod and its message, one OutOfSync app, one multi-source app (`revisions`), one Progressing app,
   one app outside the default namespace.
5. Grep the fixtures for every real name from the raw capture (the script prints the list it replaced; check that none
   survive). Delete nothing from the scratch folder until this passes.
6. Write `test/support/fake_argocd_server.rb` modelled on `fake_beszel_hub.rb`: serves the fixtures, checks the bearer
   token, can be told to fail (500, timeout, 401), to redirect to another host, and records each request (path, host,
   `Authorization` header) so tests can assert where a token went.

## Not in this slice

The plugin itself. The fake server is exercised by slice 1's first test.
