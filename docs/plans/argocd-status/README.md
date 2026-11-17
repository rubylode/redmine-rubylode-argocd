# Argo CD status: implementation plan

Spec: `docs/specs/2026-11-16-argocd-status-design.md`. Date: 2026-11-16.

## Seams (agreed)

1. **Redmine requests against the fake Argo CD server.** The main seam. Integration tests hit the page, the macro, the
   My page block and the settings page while `test/support/fake_argocd_server.rb` serves the scrubbed fixtures over
   real HTTP, exactly as Rubylode Beszel does with `fake_beszel_hub.rb`.
2. **The status model.** Argo CD JSON in, rows out: health and sync per app, whether it needs attention, the failing
   resources, the summary. Used for the combinations (every health by sync pair, multi-source revisions, the
   resource-tree cap) that would be slow and noisy through HTML.

No test reaches into a private method or asserts on a class other than through these two doors. Transport rules
(token bound to its host, redirects, plain http) are checked at seam 1, with the fake server playing the wrong host.

## Order

| # | File | What becomes true | Blocked by |
|---|---|---|---|
| 0 | `00-fixtures.md` | Scrubbed fixtures and a fake server exist | nothing |
| 1 | `01-tracer.md` | One instance's apps show on `/status/argocd` | 0 |
| 2 | `02-failing-resources.md` | A sick app lists its failing resources | 1 |
| 3 | `03-several-instances.md` | Several instances, each failing on its own | 1 |
| 4 | `04-attention.md` | Summary line, ordering, Apps to show, visibility | 1 (3 for the summary across instances) |
| 5 | `05-placements.md` | Macro, My page block, partial, hooks, top menu, Status widget | 4 |
| 6 | `06-settings-page.md` | Settings validate and say which variables are set | 3 |

Slices 2 and 3 can go in either order. Each slice starts in a fresh session from its file, works test first (one
failing test, the least code that passes it), runs single test files while working and the full suite once at the end
(`bin/test`), and ends with one or more conventional commits.

After slice 6: demo, screenshots, README, CHANGELOG and release (roadmap item 4).

## Sources to copy from

- Rubylode Beszel (`../redmine-rubylode-beszel`): the whole layout. `init.rb`, `lib/rubylode_beszel/*`,
  `app/models/rubylode_beszel/{secure_transport,path_matcher,settings_validator,status_widget}.rb`, the views, the
  stylesheet, `bin/test`, `docker-compose.yml`, `docker/test.Dockerfile`, `.github/workflows/*`, `test/test_helper.rb`.
  Rename `beszel` to `argocd` and `RubylodeBeszel` to `RubylodeArgocd`.
- Rubylode Windmill (`../redmine-rubylode-windmill`): `windmill_client.rb` (JSON API client with a bearer token)
  and `attention_rule.rb`.
- Leave out Beszel's settings-rename migration; this plugin has no old settings to move.
