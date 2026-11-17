# 4. Attention, ordering, Apps to show, visibility

Blocked by slice 1; the summary across instances needs slice 3.

## Done means

The block opens with "All 12 apps healthy and synced" or "2 of 12 need attention", rows needing attention come first,
Apps to show narrows and relabels the list, and the block is shown only to the people the setting allows.

## Tests, in order

1. Seam 2: needs attention when health is Degraded, Missing or Unknown, or sync is OutOfSync; Progressing and
   Suspended do not count (one table-driven test over the health by sync pairs, expected values written out).
2. Seam 2: ordering is attention first, then by name.
3. Seam 2: the summary wording for all fine, some needing attention, and an unavailable instance (its apps are not
   counted; say so).
4. Seam 1: Apps to show with two lines limits the page to those apps, shows their labels, and ignores an app name the
   instance does not have (an administrator sees a note).
5. Seam 1: "Administrators only" hides the page from a signed-in user (403 or not found, as Beszel does); anonymous never
   sees it.
6. Seam 1: Block title appears as the heading.
