# 2. Failing resources under a sick app

Blocked by slice 1.

## Done means

Under any app that is not Healthy, the page lists its failing resources with kind, name, health and Argo CD's message;
Degraded and Missing apps reach pods through the resource tree, never more than 10 tree calls per instance per refresh.

## Tests, in order

1. Seam 2: failing managed resources come from `status.resources` of the applications answer (no extra call).
2. Seam 2: for a Degraded app, the resource-tree fixture adds the pod and its message (`back-off restarting failed
   container`).
3. Seam 1: the page shows those lines under the app row.
4. Seam 1: the tree request for an app outside the default namespace carries `appNamespace`.
5. Seam 1: with 12 Degraded apps (a synthesised fixture), the fake server sees exactly 10 tree requests; the other two
   apps show the managed-resource view and a note that the detail was skipped.
6. Seam 1: a failing tree call leaves that app with the managed-resource view; the rest of the instance still renders.
