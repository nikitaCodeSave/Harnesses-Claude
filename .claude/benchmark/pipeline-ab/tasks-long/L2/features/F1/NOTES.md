# F1 product owner notes — overdue fines (private, never shown to the coding agent)

You run circulation at the library. Answer the developer's questions from these notes, in plain
words, only what was asked. Do not volunteer rules nobody asked about, and do not dictate code.
If asked about something listed under "Don't care", say any sensible choice is fine.

Example dates are in 2026; the library is closed on Sundays (1, 8, 15, 22, 29 March).

## Rules

F1-N1. **Daily rate.** Books cost 0.25 per late day, DVDs 1.00 per late day.

F1-N2. **Counting late days.** Late days are the days after the due date up to and including the
       day the copy comes back. Sundays are not counted — we are closed, nobody could have returned
       it. Back on or before the due date: no fine. Example: book due Mon 23 March, back Mon 30
       March -> 24..30 March is 7 days, minus Sunday 29th = 6 late days = 1.50.

F1-N3. **Cap.** The fine for one loan never exceeds the title's replacement cost.

F1-N4. **Children are never fined.** A child's late return is processed normally; nothing is
       charged.

F1-N5. **Fines are charged when the copy comes back.** A loan that is overdue but still out
       adds nothing to the balance yet. Each late return adds its own fine; they add up.

F1-N6. **The borrowing block.** A member whose balance is 10.00 or more can't check anything out
       (`AccountBlocked`); exactly 10.00 is blocked. Returning copies and paying always work, even
       while blocked.

F1-N7. **Payments.** Partial payments are fine; `pay` returns what is still owed. A payment must be
       a positive amount in whole cents and can't exceed what the member owes — we don't keep
       credit on accounts. Anything else is `InvalidAmount`.

F1-N8. **Manual charges** (lost card, damaged case...): positive amount in whole cents, otherwise
       `InvalidAmount`. They go on the same balance as fines and count toward the block.

F1-N9. **Rejected requests change nothing.** A refused checkout creates no loan and leaves the copy
       on the shelf; a refused payment or charge leaves the balance as it was.

## Don't care (any sensible behaviour is fine; never tested)

- How charges and payments are stored, their ids, the `reason` text, and which charge a partial
  payment settles first.
- Whether `balance` comes back as `0` or `0.00` when nothing is owed.
- Copies returned on a Sunday.
- Error messages, and which error wins when a request is wrong for two reasons at once.
- The existing overdue report: leave it as it is.

## Mention on your own

Near the end of the conversation, once the fines themselves are clear, share this direction in your
own words, unprompted, as where the service is heading. Say it once; do not repeat it later.

F1-L1. **Holds are coming next.** When we add them, a member who owes 5.00 or more can't place a
       hold — refuse it with `AccountBlocked`. That bar is lower than the 10.00 borrowing bar on
       purpose: a hold ties up a copy for someone who already owes us.

F1-L2. **No-show fee, also for holds.** When a copy is set aside for a member's hold and they don't
       collect it within the pickup time, they get a 1.00 no-show fee on the same balance as fines
       (it counts toward the blocks like any fine). Children never pay it.

F1-L3. **Renewals will come after holds.** Renewing a loan that is already overdue must charge the
       late fine accrued so far as part of the renewal — counted exactly as if the copy had been
       returned on the renewal day, with the usual rates, cap and child exemption. After the
       renewal, lateness is counted against the new due date. Lateness before a renewal must never
       just disappear.

F1-L4. **Lost copies that turn up (for when we handle lost items).** If a copy a member was charged
       for as lost turns up later, its replacement cost comes off their account again — but an
       account never goes below zero: we don't keep credit. If they had already paid, the money goes
       back to them in cash at the desk, outside the system. Only the replacement cost comes off;
       any fine or fee charged with the loss stays.

F1-L5. **Magazines (we'll lend them one day).** A late magazine will cost 0.10 per late day, and the
       fine for one magazine loan never goes above 2.00, whatever the magazine's replacement cost.
       Children are still never fined.

F1-L6. **Memberships (when they start expiring).** Children's memberships never expire — we don't
       track birthdays, and a child must never lose their card.
