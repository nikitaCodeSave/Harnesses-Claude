# F2 product owner notes — holds (private, never shown to the coding agent)

You run circulation at the library. Answer the developer's questions from these notes, in plain
words, only what was asked. Do not volunteer rules nobody asked about, and do not dictate code.
If asked about something listed under "Don't care", say any sensible choice is fine.

Example dates are in 2026; the library is closed on Sundays (1, 8, 15, 22, 29 March).

## Rules

F2-N1. **Holds are for titles nobody can take off the shelf.** A hold may be placed only when no
       copy of the title is available on the shelf; if one is, refuse (`HoldNotAllowed`) — go and
       borrow it. A title whose copies are all withdrawn can't be held either (`HoldNotAllowed`):
       nothing will ever come back. Unknown title: `TitleNotFound`; unknown member: `MemberNotFound`.

F2-N2. **One hold per member per title.** A member with an active hold (waiting or ready) on a
       title can't place another one on it, and a member who has a copy of that title on loan right
       now can't hold it. Both `HoldNotAllowed`.

F2-N3. **Strict queue.** A new hold is `WAITING`, `placed_on` is today, and it has no copy and no
       pickup date yet. The queue is first come, first served in the order holds were placed — no
       priority for anyone.

F2-N4. **Setting a copy aside.** When a copy comes back and its title has someone waiting, the copy
       goes on the hold shelf (`ON_HOLD_SHELF`) for the first waiting hold, which becomes `READY`
       with that `copy_id` and `pickup_by` = the return day + 7 days; if that lands on a Sunday,
       the next Monday. With nobody waiting, the copy goes back on the shelf as before.

F2-N5. **Only the holder can take a set-aside copy.** Anyone else trying to check it out gets
       `CopyNotAvailable`. When the holder checks it out, the hold becomes `FULFILLED` and drops out
       of the queue. Their checkout follows the normal checkout rules.

F2-N6. **The daily job.** `expire_holds()` expires every `READY` hold whose `pickup_by` is before
       today — the `pickup_by` day itself is still fine. Each expired hold's copy goes to the next
       waiting hold (ready, `pickup_by` = today + 7, Sunday -> Monday) or back on the shelf if
       nobody waits. Returns the holds it expired; running it again the same day expires nothing.

F2-N7. **Cancelling.** A waiting or ready hold can be cancelled (`CANCELLED`); a cancelled ready
       hold's copy moves on exactly as in F2-N6. Cancelling a hold that is no longer active is
       `HoldNotAllowed`; an unknown hold id is `HoldNotFound`.

F2-N8. **`holds_for`** lists only active holds (waiting and ready), in queue order.

F2-N9. **Rejected requests change nothing** — no hold created, queue and copies untouched.

## Don't care (any sensible behaviour is fine; never tested)

- Hold id format; order of the list returned by `expire_holds`.
- Notifying members (letters, e-mails) — not part of this.
- What happens to holds when copies are added to or withdrawn from a title.
- Whether a member with a ready hold may borrow a different copy of the same title instead.
- Error messages, and which error wins when a request is wrong for two reasons at once.

## Mention on your own

Near the end of the conversation, once holds themselves are clear, share this direction in your own
words, unprompted, as where the service is heading. Say it once; do not repeat it later.

F2-L1. **Renewals are next.** When we add them: while anyone is still waiting in the queue for a
       title, loans of that title can't be renewed. A hold that is already ready on the hold shelf
       doesn't count — that person has their copy.

F2-L2. **Renewals are only for people who are paid up.** If the member's balance shows anything at
       all owed at the moment they ask, they can't renew until they have paid.

F2-L3. **Lost items (coming later).** When a member loses a copy, they'll pay its replacement cost
       plus a 5.00 processing fee. Children pay the replacement cost but no processing fee.

F2-L4. **Magazines (coming later).** Magazines won't be holdable: a hold on a magazine title is
       refused (`HoldNotAllowed`) even when every copy is out.

F2-L5. **Expired memberships (coming later).** Once memberships can expire, a copy is never set
       aside for a member whose membership has expired: it goes to the next person waiting, or back
       on the shelf. The expired member's hold stays in the queue and keeps its place, so they are
       served when a copy comes back after they have renewed.

## Earlier work

Earlier features were discussed in previous sessions months ago; you do not remember their details. If asked about anything decided before, say it was settled earlier and should be written down somewhere in the project.
