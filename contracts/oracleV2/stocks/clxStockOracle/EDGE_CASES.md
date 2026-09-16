# CLX Stock Oracle — Edge Cases

Concrete walkthroughs of the oracle's behavior in non-happy-path situations: quiet sessions, feed outages, weekends, and MH failures. Companion to [SPEC.md](./SPEC.md); implementation in [`helpers.sol`](./helpers.sol) (`_findLatestRegularHoursRound`, `_isPreWindowAnchorTrusted`, `_revertIfStalePrice`).

All times are ET. MH session model per weekday: pre-market `EXTENDED` 4:00–9:30 AM, `REGULAR` 9:30 AM–4:00 PM, after-hours/overnight `EXTENDED` 4:00 PM → next session; weekend `HOLIDAY` Fri 8:00 PM → Mon pre-market.

## 1. Concepts

**Anchor (clamp reference).** Outside REGULAR, prices are clamped ±`MAX_EXTENDED_HOURS_CAP_PERCENT` around the latest RTH print. The anchor window is `[regularStart, regularEnd + 15m]` while the window can still print; once `block.timestamp > regularEnd + 15m` the lower bound widens to `windowEnd − MIN_CHAINLINK_HEARTBEAT` (24h20m). Rationale: Chainlink 24/5 feeds print on **deviation or heartbeat**, so a session with zero prints certifies the last pre-session print as the session price (within the ~0.5% deviation threshold). In-window prints always win (the walk takes the latest round ≤ window end) and are exempt from the liveness rules below — they are real RTH prints.

**Deadline (liveness proof).** The certification assumes the feed was *alive* through the quiet session. The feed owes a print at least every heartbeat while its 24/5 market trades: after a print at time T, the next print is due by the **deadline** `T + MIN_CHAINLINK_HEARTBEAT`. A pre-window anchor is trusted unless the feed **provably** missed a deadline:

1. Deadline not passed yet (`now < print + heartbeat`) → trusted.
2. The next print landed before its deadline → feed provably live across the session → trusted.
3. The deadline fell in `HOLIDAY` (feed expectedly silent) or `UNKNOWN` (MH cannot classify) → nothing provable → trusted.
4. Otherwise — deadline passed during trading hours (`REGULAR`/`EXTENDED`) with no print → **rejected**: fallback pricing (no clamp), `updateRegularHoursAnchor` reverts `RegularHoursReferenceNotFound` (bot alert).

**Live-leg staleness (orthogonal to the anchor).** Freshness of the *latest* print is enforced separately and is **wall-clock, not calendar-aware** (`_revertIfStalePrice`):

| Path | Max live-price age |
| --- | --- |
| operate, REGULAR / EXTENDED (incl. fallback with trusted MH window) | `MIN_CHAINLINK_HEARTBEAT` (24h20m) |
| operate, HOLIDAY / UNKNOWN | 5d |
| operate, untrusted/malformed MH window (MH failure → fail-open) | 5d |
| liquidate, always | 5d |

A dead feed can never be mispriced by the clamp: with no prints after the anchor, live == anchor and the clamp is mathematically inert.

## 2. Quiet Friday → anchor allowed (incl. Monday pre-market)

| Time (ET) | Session | What happens |
| --- | --- | --- |
| Thu 8:00 PM | EXTENDED (Thu overnight) | Feed prints — anchor candidate for Friday |
| Fri 4:00–9:30 AM | EXTENDED (pre-market) | No print |
| Fri 9:30 AM–4:00 PM | REGULAR | Zero prints — quiet session |
| Fri 4:00–8:00 PM | EXTENDED (after-hours) | Still no print |
| **Fri 8:20 PM** (deadline = Thu 8:00 PM + 24h20m) | **HOLIDAY** (weekend began 8:00 PM) | Feed is supposed to be silent → missing print proves nothing → anchor stays trusted |
| Sat, Sun | HOLIDAY | Anchor trusted, clamp active (inert while live == anchor) |
| Mon 4:00–9:30 AM | EXTENDED (pre-market) | Deadline-fell-in-HOLIDAY keeps the anchor trusted → **clamp active** |
| Mon 9:30 AM | REGULAR | Live pricing, clamp not used |

**Boundary:** deadline landing exactly at weekend start (Fri 8:00 PM) is accepted; one second earlier (Fri 7:59:59 PM, after-hours EXTENDED) is a provable miss → rejected — the feed owed a print while its market was still trading.

## 3. Quiet Tuesday, feed goes silent → anchor rejected

| Time (ET) | Session | What happens |
| --- | --- | --- |
| Mon 8:01 PM | EXTENDED (Mon overnight) | Feed prints — anchor candidate for Tuesday |
| Tue 9:30 AM–4:00 PM | REGULAR | Zero prints |
| **Tue 8:21 PM** (deadline = Mon 8:01 PM + 24h20m) | **EXTENDED** (Tue overnight, 24/5 market trading) | Feed was obligated to have printed by now — nothing came → provable violation |
| Wed 1:00 AM | EXTENDED | Anchor rejected → no clamp, `updateRegularHoursAnchor` reverts (bot alert). Operate reverts `StalePrice` on the live leg; liquidate serves on the 5d rule (clamp-inert) |

Variants:

- **Feed recovers after the violation** (prints Wed morning): rule 2 fails (gap > heartbeat) → anchor stays rejected → live price served **unclamped** rather than clamped against an uncertified anchor. Operate works again (live leg fresh).
- **Next heartbeat print on time** (prints Tue 8:01 PM, gap = 24h): rule 2 passes → anchor trusted, clamp stays anchored to the Monday-certified price all Tuesday night — even though the anchor is now older than a heartbeat vs `now`.
- **Anchor stored while trusted, feed silent afterwards**: the cache-hit path re-runs the liveness check on every read, so a stored pre-window anchor is invalidated the moment the miss becomes provable.

## 4. Missing Monday resumption print → operate blocked during pre-market

The feed's first weekly print is empirically the 24/5 reopen at Sun ~8:00 PM ET (observed weekly on SPY). Assume it never lands:

| Time (ET) | Session | What happens |
| --- | --- | --- |
| Fri 2:00 PM | REGULAR | Feed's last print — normal Friday, in-window anchor (liveness-exempt) |
| Fri 8:00 PM | HOLIDAY begins | Feed offline for the weekend — expected |
| Sat 2:20 PM (last print + 24h20m) | HOLIDAY | Live print now older than heartbeat — irrelevant: operate uses the 5d rule on HOLIDAY → serves all weekend |
| Sun 8:00 PM | HOLIDAY | Resumption print due here empirically — assume missing |
| Mon 4:00 AM | EXTENDED (pre-market) | **Operate reverts `StalePrice`**: live-leg check is wall-clock (`now > lastPrint + 24h20m`, ~62h) and EXTENDED demands heartbeat freshness. The anchor is fine — the block is purely the live leg. Liquidate serves (5d, clamp-inert) |
| Mon, first print lands | EXTENDED / REGULAR | Operate self-heals immediately |

Note: because any Friday print is > heartbeat old by Saturday afternoon, operate at Monday pre-market *always* depends on a post-weekend print having landed — normally covered with ~8h margin by the Sunday reopen print. Deliberately kept strict (no calendar-awareness on the live leg): serving a ~60h-old price when the feed provably failed to resume is worse than blocking operate; liquidate is unaffected.

For **quiet** Fridays this is stricter than the pre-liveness-rule code, which served operate here via the since-closed 5d fallback loophole; for normal Fridays behavior is unchanged.

## 5. MH (market hours) failures — fail-open

| Failure | Behavior |
| --- | --- |
| Schedule expired / missing → sessionType `UNKNOWN` | No clamp; operate & liquidate on the 5d rule |
| Window malformed (`start == 0`, `end < start`) or stale (≥ 5d) | Untrusted window → no clamp; operate gets the 5d fail-open rule (MH is not a hard dependency) |
| Window trusted but no anchor found | Feed anomaly, not an MH failure → operate stays heartbeat-fresh |
| Wrong/hacked MH labels (e.g. weekend as EXTENDED) | Can DoS operate (fail-closed); liquidate unaffected. Cannot move the RTH anchor retroactively — MH pins elapsed sessions against a plain schedule writer (see its SPEC §6) |

## 6. Accepted residuals

- The deadline check trusts MH's session labels (see §5 last row) — DoS-only exposure, auth/governance-gated writes.
- MH governance / auth class `2` can still rewrite elapsed sessions, so the anchor a clamp resolves to remains trusted at that level.
- A pre-window anchor is precise to the feed's deviation threshold (~0.5%) — negligible vs the ±15% cap.
- A stuck MH writer with a live feed keeps clamping against the last window's anchor for up to 5d (window trust) — degrades toward over-clamping, the conservative direction per leg.
