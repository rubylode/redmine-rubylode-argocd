# 3. Several instances, each failing on its own

Blocked by slice 1. Touches credentials: gets a fresh read-only reviewer at the end (diff plus this file).

## Done means

Every instance line renders its own section. One instance down, slow or refusing the token shows "Status unavailable"
for that section only (administrators see why, without the token); each token reaches only its own host.

## Tests, in order

1. Seam 1: two instances, two sections, in settings order.
2. Seam 1: the second instance returns 500; the first renders, the second says unavailable; an administrator sees the
   reason, other users do not.
3. Seam 1: a timeout past Timeout seconds behaves the same, and the page still answers.
4. Seam 1: after a failure, a request within Failure cache seconds does not call that instance again.
5. Seam 1: the fake server records that instance A's token was sent only to A's host and B's only to B's.
6. Seam 1: a redirect to another host is not followed with the token (the section is unavailable).
7. Seam 1: an `http://` address is refused while Allow plain http is off, and works when it is on.
8. Seam 1: neither token appears in the page, the log, or the administrator's reason (assert on the captured log).
9. Seam 1: a line whose variable is unset or does not start with `ARGOCD_` makes that instance unavailable with a clear
   reason; it never reads another variable.

## Pieces

Beszel's `secure_transport.rb` and its credential-secrecy test are the model; adapt rather than invent.
