# Light PRD Review — Lore & Story Mobile

**Verdict:** Ship-ready after four small fixes. Decision-readiness is high; scope
is coherent; requirements are testable (the counter-metrics C1–C3 and NFR1/NFR7
give the MVP a real acceptance bar). Findings below, most-severe first.

## Findings

### F1 (High) — §5 preamble is stale after the Group I change
"Groups A–E are MVP; F–H are phased" no longer holds: Group I exists, and MVP now
includes FR24–FR25 while FR26 is phased. A reader trusting the preamble
mis-scopes the MVP. → Restate the MVP/phased split accurately.

### F2 (Medium) — Ambiguous "§n" cross-references
The PRD cites `§3.4` (S1) and `§3.3` (FR21) without a document prefix, while other
cites are qualified (`ARCHITECTURE.md §6`). The PRD has no §3.3/§3.4 of its own,
so a reader can't tell these point at MOBILE.md / ARCHITECTURE.md. → Qualify every
external section reference with its source document.

### F3 (Low) — FR18 reads as a run-on
The linter's example list is long and the mid-clause line wrap makes
"dialogue lines missing the `Name:` shape" awkward. → Light rewrap; no content
change.

### F4 (Low, enhancement) — §1 undersells error-surfacing
FR9a (flag invalid markup live) is a stated differentiator the author explicitly
values, but §1's value paragraph omits it. → Add a clause naming it (a generic
editor can't tell a scene's `[[label->passage]]` is wrong).

## Non-findings (checked, fine)
- Counter-metrics present and mapped (NFR1→C1/C3, FR14→C2).
- Out-of-scope list is explicit and the ADR-5 reversal is called out.
- Open questions correctly limited to O1 (code blocker) + O3/O4 (deferred).
- Addendum holds the implementation depth; PRD stays capability-level.
