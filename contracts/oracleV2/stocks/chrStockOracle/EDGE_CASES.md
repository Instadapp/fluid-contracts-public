# Chronicle × Reality Stock Oracle — Edge Cases

Walkthroughs of non-happy-path behaviour. Companion to [SPEC.md](./SPEC.md). Times are ET; examples use SPY with
cap 15%, break ±30%. "Value" is price × multiplier, "anchor" the effective anchor (SPEC §7), "reads"
guarded reads; `*Raw` getters keep answering throughout. Each row names the first failing check.

## 1. Normal weekday

| Time | What happens |
| --- | --- |
| Mon 9:30 AM–4:00 PM | Chronicle posts exchange prices. Cap and break are measured from Friday's close. Write getters and the keeper record each in-session print as the hint |
| Mon 3:50 PM | Keeper calls `updateRegularHoursAnchor()`: the current print becomes a fallback hint |
| Mon 4:01:30 PM | Keeper calls again; the close, typically stamped just after the bell, becomes the hint |
| Mon 4:03 PM | Keeper calls a third time: it records the last regular-session print still visible and seals it. Views treat a sealable hint as the anchor even without this call |
| Mon night, Tue pre-market | Chronicle posts Hyperliquid prices; cap and break are measured from Monday's close |

## 2. Weekend

Chronicle keeps posting Hyperliquid prices; the anchor is Friday's close. Operate works while the value stays within
±15%; between 15% and the break, operate reverts, liquidations floor collateral on the way down and cap debt on the
way up (the other direction prices live); beyond the break every read reverts. Friday's close stays the anchor until Monday's hint is sealed.

## 3. 2:1 split, multiplier first

| Step | First failing check |
| --- | --- |
| Reality sets `tradePaused` | `TradePaused`; the keeper latches, so from then on `Paused` |
| Reality moves `uiMultiplier` 1e18 → 2e18 | `Paused` |
| Chronicle reprices −50% | `Paused`; value continuous again (price × 2) |
| Reality clears `tradePaused` | `Paused` (underneath: `MultiplierChanged`) |
| Operator checks Chronicle repriced, HIGH `setAnchor(2e18)` | `Paused`; anchor = live value, multiplier accepted |
| MID `unpause()` | Pricing resumes |

If HIGH calls `setAnchor` before Chronicle has repriced, the doubled value becomes the anchor: the oracle does not
check continuity, so the operator must.

## 4. 2:1 split, price first

| Step | First failing check |
| --- | --- |
| Chronicle reprices −50%, multiplier unchanged | `PriceBreak`; no hint recorded |
| Reality moves the multiplier | `MultiplierChanged`; the keeper latches (cause `4`), then `Paused` |
| HIGH `setAnchor(2e18)`, then MID `unpause()` | Pricing resumes |

Without `tradePaused`, only the break stops pricing, nothing is latched and no hint is recorded. Monitoring should
page on `PriceBreak`: the break holds only until the anchor ages out, 5 days 12 hours after its print (§15).

## 5. Smaller splits

A 3:2 desync is −33.3% (price first) or +50% (multiplier first): beyond the break unless a concurrent move hides it
(SPEC §10). A 5:4 desync sits inside the break: operate reverts outside the cap, liquidations floor collateral at −15% until
the close, and after the seal the full −20% is priced until the multiplier moves (then frozen and latched). Where the rtoken
is debt, operate prices it 20% low from the next session: users can borrow it cheap and sell or redeem it at full
value, and when HIGH re-anchors on the new multiplier the debt jumps +25% (+33% for 4:3), which can leave bad debt. Small splits are not expected on the
listed index ETFs; Reality's `tradePaused` (latched) covers them when they happen.

## 6. Crash beyond the cap

The value is −20% vs yesterday's close during the session. Operate reverts `OutsideCap`; liquidations price
collateral at −15%. The −20% close is inside the break, so it seals and the next session is measured from it. At −35%
every read reverts `PriceBreak` and no hint is recorded. If the session recorded a print inside the break on the way
down (say −29%), that print seals 2 minutes after the bell and −35% is −8% from it, so pricing resumes with no admin
call; one close absorbs up to two breaks (−51%). Otherwise an operator checks the market and HIGH calls `setAnchor`
to accept it.

## 7. Chronicle stops posting

Reads revert `StalePrice` once the print is older than `maxOperateAge` (operate) or `maxLiquidateAge` (liquidate).
Nothing latches; pricing resumes on the next print. Chronicle's own pauses look the same on-chain.

## 8. No call near the close

Nobody records a hint after 2:00 PM: the 2:00 PM print seals as Monday's anchor instead of the last print before the
bell. If no hint is recorded all session, cap and break stay measured from Friday's close. Monitoring should alert on
"no seal for a session".

## 9. Market-hours schedule stops updating

`getCurrentSession()` returns a stale window: no new hints (an existing hint still takes effect 2 minutes after its session).
If it reverts, the write getters and `updateRegularHoursAnchor` revert too (as in CLX); the USD oracle falls back to
the view getters, which never call MH, so reads keep working against the last anchor. Once it is older than 5 days 12 hours, cap and break are skipped and reads price live (fail-open, as in CLX).
When the schedule is back, the next in-session print is recorded without the break check and seals 2 minutes after the bell,
which re-arms both.

## 10. Rtoken paused for an upgrade

Token `paused()` set: reads revert `RtokenPaused`; the keeper latches. While the token is still paused, `unpause()`
reverts `LatchCauseActive`. After the issuer unpauses it, MID `unpause()`.

## 11. Delisting

The rtoken's `isDelisted()` is not read. Reality announces a delisting and off-chain monitoring watches the flag; an
operator pauses the oracle by hand. If the stock stops trading, Chronicle stops posting and reads revert
`StalePrice` regardless.

## 12. Fresh deployment

Until Chronicle tolls the address, every getter that reads Chronicle reverts with Chronicle's error. After the toll,
guarded reads price live with cap and break off, so the USD-oracle key can be registered at once. The keeper (or any
write read) records the first in-session prints, and the first regular-session close seals as the anchor, which arms
cap and break. No admin call is needed.

## 13. Multiplier changes and changes back

Reality moves `uiMultiplier` and restores it an hour later, without setting `tradePaused`. While it differs, reads revert
`MultiplierChanged` and the keeper latches (cause `4`). After it changes back, reads still revert `Paused`. An operator
reviews what happened, then MID `unpause()`. No `setAnchor` is needed, since the accepted multiplier is current again.

## 14. L2 sequencer outage

While the uptime feed reports down, guarded reads, `getExchangeRate()` and `updateRegularHoursAnchor()` revert
`SequencerL2__SequencerDown`; after it comes back they revert `SequencerL2__GracePeriod` for the outage length, at most 45
minutes. Nothing is queued: the first call after the gate opens records the current print if it is still in-session.
`latchPause()` keeps working throughout.

## 15. Accepted residuals

- `setAnchor` does not check continuity: accepting a multiplier before Chronicle repriced puts the split factor into
  the price. The operator checks both legs first.
- A price-first desync inside the break with no Reality flag reaches liquidations at the clamp, and at the full desync after the
  next seal, until the multiplier lands. As debt, the rtoken is underpriced by the desync on operate and jumps back
  when the multiplier is accepted (§5).
- After 5 days 12 hours without a seal the cap and break are off until the next seal (fail-open, as in CLX). This includes a
  price-first split held only by the break: before the anchor ages out (5 days 12 hours after its print, so about 1 day
  18 hours after a 3-day weekend) an operator pauses (multiplier not landed) or calls
  `setAnchor` and unpauses (landed).
- A move beyond the break halts pricing, liquidations included, until HIGH `setAnchor`, unless the session first
  recorded a print inside the break; that print seals at the close and up to two breaks are absorbed (§6).
- The anchor is the last observed in-session print, not the official close.
- Chronicle can revoke the toll at any time; every getter that reads Chronicle then reverts with Chronicle's error.
- A Reality flag stuck on (`tradePaused`, token `paused()`) blocks liquidations until it clears.
- A delisting is not detected on-chain; it relies on Reality's notice and off-chain monitoring (§11).
- A multiplier change and change-back between two keeper calls leaves no mark (reads reverted meanwhile).
- A dependency that starts reverting (rtoken beacon or `RWATokenTrade` upgrade) fails reads closed until fixed;
  `latchPause()` skips a reverting read and `unpause()` reverts. A dependency that returns malformed data (e.g. an
  upgrade to an implementation without the function) also reverts `latchPause()`; reads are already failing then.
- `*Raw` getters ignore every check, and `getExchangeRate()` every check but the sequencer: their consumers (the USD
  oracle's `getPriceRawForMode` for limit handlers and auth contracts, resolvers) see the live value during a desync
  or pause.
