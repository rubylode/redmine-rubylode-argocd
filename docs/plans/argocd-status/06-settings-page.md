# 6. Settings page

Blocked by slice 3.

## Done means

The settings page accepts the spec's settings, refuses bad lines with a message naming the line, and shows next to each
instance whether its token variable is set, never its value.

## Tests, in order

1. Seam 1: saving valid instance and app lines stores them as `plugin_redmine_rubylode_argocd`.
2. Seam 1: each bad instance line is refused with its line number: missing parts, an address that is not http(s),
   `http://` while plain http is off, a variable not starting with `ARGOCD_`, a duplicate name. `#` lines are ignored.
3. Seam 1: an Apps to show line naming an unknown instance is refused.
4. Seam 1: cache, failure cache and timeout outside sane bounds are refused (Beszel's limits).
5. Seam 1: the page says "set" or "not set" for each variable, and the variable's value never appears in the HTML.
6. Seam 1: saving clears the cache, so the next page load fetches fresh data.

## Pieces

Beszel's `settings_validator.rb`, `settings_controller_patch.rb` and settings view.
