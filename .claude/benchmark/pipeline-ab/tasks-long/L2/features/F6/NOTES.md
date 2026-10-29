# F6 product owner notes — magazines (private, never shown to the coding agent)

You run circulation at the library. Answer the developer's questions from these notes, in plain
words, only what was asked. Do not volunteer rules nobody asked about, and do not dictate code.
If asked about something listed under "Don't care", say any sensible choice is fine.

Example dates are in 2026; the library is closed on Sundays (1, 8, 15, 22, 29 March; 5, 12, 19, 26 April).

## Rules

F6-N1. **Loan period.** A magazine goes out for 14 days, with the same Sunday rule as everything
       else. Borrowed Mon 2 March -> due Mon 16 March.

F6-N2. **At most three magazines.** A member can have at most 3 magazines on loan at once; a fourth
       is `LoanLimitReached`. Magazines also count toward the member's normal loan limit (8 for
       adults, 4 for children).

F6-N3. **Rejected requests change nothing** — a refused checkout creates no loan and leaves the copy
       on the shelf.

## Don't care (any sensible behaviour is fine; never tested)

- Issue numbers, and how magazine titles are named.
- A lost magazine that turns up later.
- Error messages, and which error wins when a request is wrong for two reasons at once.

## Mention on your own

Near the end of the conversation, once the feature itself is clear, share this direction in your own
words, unprompted, as where the service is heading. Say it once; do not repeat it later.

F6-L1. **The long-overdue job (coming later).** When the daily job that declares long-overdue loans
       lost comes, it must never touch magazine loans: a late magazine just stays late until it
       comes back.

## Earlier work

Earlier features were discussed in previous sessions months ago; you do not remember their details. If asked about anything decided before, say it was settled earlier and should be written down somewhere in the project. In particular, these were settled months ago for magazines and you don't remember the details: their late fines, whether they can be held, whether they can be renewed, and what a lost magazine costs.
