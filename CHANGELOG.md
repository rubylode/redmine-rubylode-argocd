# Changelog

All notable changes to this plugin. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-11-17

First release. It shows the health and sync state of the applications in one or more Argo CD servers inside Redmine, read only.

### Added

- A table of applications per Argo CD instance: name linked to the Argo CD UI, project, health, sync, last sync and revision, with the apps that need attention first and a summary line.
- The failing resources under an app that is not Healthy, with kind, name, health and Argo CD's message.
- Several instances, each with its own address, token variable, cache and failure state. One that cannot be reached says "Status unavailable" and the others still show.
- The block as a wiki macro (`{{argocd_status}}`), a page (`/status/argocd`), a My page block, a partial, placements on the welcome page, the default My page, project Overview pages and pages matching a path list, a top menu link, and a widget on the Rubylode Status page when that plugin is installed.
- A settings page that checks each line and shows whether each token variable is set.
- Tokens are read from `ARGOCD_...` environment variables only, sent only to their own instance, over https unless the host is loopback or "Allow plain http" is checked, and never followed through a redirect.
