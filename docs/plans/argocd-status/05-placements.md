# 5. Placements

Blocked by slice 4.

## Done means

The same block appears everywhere Beszel's does: the `{{argocd_status}}` wiki macro, the "Argo CD" My page block, the
partial, the welcome page, My page, project Overview and path placements, the top menu link, and a widget on the
Rubylode Status page when that plugin is installed.

## Tests, in order

Port Beszel's `wiki_macro_test.rb`, `my_page_block_test.rb`, `placements_test.rb` and `status_plugin_test.rb` one
case at a time, renaming as you go:

1. The macro renders the block, and renders nothing (no error) for someone the visibility setting excludes.
2. The My page block is offered and renders.
3. Each placement switch, on and off, including path matching.
4. The top menu link uses Block title.
5. With the Status plugin present, one widget covers all instances and reports the worst state; without it, nothing
   breaks and the settings show the notice.
6. A page around the block (wiki, welcome) still answers when every instance is down.
