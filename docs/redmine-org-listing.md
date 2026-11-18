# Listing on www.redmine.org

The text to paste at www.redmine.org, Plugins, New plugin. Redmine's "Check for updates" asks that directory about every installed plugin, so the listing must carry the same name, author and version as the plugin.

| Field | Value |
|---|---|
| Name | Rubylode Argo CD |
| Short description | The health and sync state of the apps in one or more Argo CD instances: a page, a wiki macro, a My page block and a partial |
| Homepage | https://github.com/rubylode/redmine-rubylode-argocd |
| Compatible with | Redmine 5.1.x, 6.0.x, 6.1.x, 7.0.x |
| License | GNU General Public License, version 2 or (at your option) any later version |
| Author | Rubylode |

## Notes for this version

Version 1.1.0. The health and sync state of the apps in one or more Argo CD instances, with the failing resources of an app in trouble: a page, a wiki macro, a My page block and a partial, and a block on the Rubylode Status page. Needs Redmine 5.1 or newer. No migration. Install and settings are described in the README at https://github.com/rubylode/redmine-rubylode-argocd.

## File to upload

`redmine_rubylode_argocd-1.1.0.zip`, the file the GitHub release workflow publishes when the `v1.1.0` tag is pushed. Upload the same file that is attached to the GitHub release.

## Checking the result

The name, author and version in the listing must match what the plugin registers (`Rubylode Argo CD`, `Rubylode`, `1.1.0`). When they do, Administration, Plugins, Check for updates shows:

- a green tick: the installed version is the latest one listed on redmine.org;
- an amber warning: redmine.org lists a newer version than the installed one;
- a grey question mark: the plugin is not found, so the name or the listing needs a look.

The answer comes only from the redmine.org directory. Nothing in the plugin can change it, and it stays grey until the listing exists.
