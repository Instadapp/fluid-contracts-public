# US Equity Market Hours — Off-chain schedule writer

Authorized bot that posts weekly schedules to `FluidUsEquityMarketHours` via `updateWeekSessions`.

Contract: [`SPEC.md`](./SPEC.md). Reference builder (optional): [`UsEquityMarketHoursCalendarLib.sol`](../../../../test/foundry/oracleV2/UsEquityMarketHoursCalendarLib.sol).

---

## Mental model (read this first)

Each on-chain row is one **session**:

| Piece | Meaning |
| --- | --- |
| `sessionStart` | When this entry begins |
| `durationMinutes` | Length of the **session itself** (cash REGULAR hours, or a HOLIDAY closed block) |
| `extendedDurationMinutes` | Time **after** the session — classified as `EXTENDED`. For a cash day this covers **post-market + overnight + next pre-market** until the next entry starts. |

**Weekend:** one `HOLIDAY` entry for the closed span; its `extendedDurationMinutes` is the **pre-market** of the next trading day (usually Monday pre, or Tuesday pre if Monday is a holiday).

`EXTENDED` is never written as its own row — it is only the tail of a `REGULAR` or `HOLIDAY` entry.

---

## 1. Role

| | |
| --- | --- |
| Who | Auth class `1` (the bot) — class `2` or Liquidity governance may additionally rewrite pinned sessions |
| Call | `updateWeekSessions(Session[] sessions_)` |
| Failure mode | Oracles **fail open** on `UNKNOWN` — still never post an invalid schedule; alert on failure / drift |

The bot writes the **future**: entries starting before `now + 5 hours` are pinned and must be re-posted byte-identical to what is already stored, or the tx reverts. A normal weekly rewrite satisfies this for free (the elapsed Friday + live weekend entries are unchanged). Correcting the live entry needs class `2` / governance — see §4.

MH is complementary security for CLX, not a hard dependency for pricing.

---

## 2. Cadence & Slack

1. **Friday evening** — build the planned schedule for the coming week, run local sanity checks, and **Slack the full planned payload** (devs have ~one day to react).
2. **Saturday** — if nothing blocked it, **auto-submit** `updateWeekSessions` with that plan.
3. **Every successful on-chain write** — Slack again with tx hash + summary, tagging **bergben**, **Thrilok**, and **Georges**.
4. **Failed write / source dissent / drift** — Slack alert with reason (same tags); one short retry only for transient RPC/source flakes. Do not auto mid-week rewrite by default — alert and wait for humans.

---

## 3. What on-chain expects

### `Session` calldata

| Field | Type | Notes |
| --- | --- | --- |
| `sessionStart` | `uint32` | Unix seconds (ET wall → unix with DST / `America/New_York`) |
| `durationMinutes` | `uint16` | Main window; ≤ `8191`; REGULAR sessions additionally ≤ `1440` (24h) |
| `extendedDurationMinutes` | `uint16` | Post-session tail → `EXTENDED`; ≤ `8191` |
| `sessionType` | `uint8` | Write **only** `1` (`REGULAR`) or `3` (`HOLIDAY`) |

Classification for one entry:

- `[sessionStart, sessionStart + durationMinutes)` → stored type
- Next `extendedDurationMinutes` → `EXTENDED`
- Outside every entry → `UNKNOWN`

Contiguity:  
`next.sessionStart == prev.sessionStart + (durationMinutes + extendedDurationMinutes) * 60`.

### Sanity checks (tx reverts otherwise)

1. `1 ≤ length ≤ 8`
2. Non-zero start + duration; types ∈ {REGULAR, HOLIDAY}; durations ≤ 8191
3. Contiguous
4. Total minutes ≥ `10080` (7 days)
5. Some entry’s full window contains `block.timestamp`
6. Some `REGULAR` has `sessionStart ≤ block.timestamp`
7. Every entry starting before `now + 5 hours` matches a stored entry exactly (skipped on the first write, and for class `2` / governance)

A revert on 7 means the schedule you rebuilt disagrees with history — a changed early-close flag, a retroactive holiday, or a source bug. **Do not retry**; Slack humans with both payloads.

How the bot assembles the array is up to the backend, as long as these rules pass.

---

## 4. Typical shapes & edge cases

Use exchange **cash + late session** (ET), not broker-only products.

| Kind | Main | Extended | Type |
| --- | --- | --- | --- |
| Full cash day | `390` (09:30–16:00) | Post + overnight + next pre (until next entry) | `REGULAR` |
| Early close | `210` (09:30–13:00) | Post (e.g. to 17:00) then bridge as needed | `REGULAR` |
| Weekend | Closed Fri post → next open’s pre | Pre of next trading day (`~330` if 04:00–09:30) | `HOLIDAY` |
| Full holiday (e.g. Monday closed) | Closed block covering the holiday | Pre of the **next trading** day (often Tuesday) | `HOLIDAY` |

Edge cases (handle accordingly — still one contiguous ≤8-row week):

- **Monday holiday:** weekend/`HOLIDAY` bridge must end at **Tuesday** (or first trading day) pre — not Monday 09:30. Start the forward week at the first cash open.
- **Friday holiday / early week start:** last completed cash day + `HOLIDAY` bridge that still contains Saturday `now`.
- **Never** run overnight `EXTENDED` into a holiday Core morning; after post ends, use `HOLIDAY` until the next trading day’s pre.
- **Unplanned mid-week closure:** the live entry is pinned, so replace the **next** entry instead — a `HOLIDAY` row starting exactly where the live one ends. The closed day’s pre-market stays `EXTENDED` rather than `HOLIDAY`; that is the conservative label (still clamped) and costs nothing. Only reach for class `2` / governance when the live entry itself is wrong.

---

## 5. Calendar sources (examples)

- Tradier `GET /v1/markets/calendar`
- Alpaca `GET /v2/calendar`
- Polygon `GET /v1/marketstatus/upcoming`
- Finnhub / FMP holiday endpoints
- Offline: pinned `exchange_calendars` / `pandas_market_calendars` (XNYS)

Require **at least 2 of 3** (or similar) healthy sources before posting; on dissent → do not write, Slack humans.

---

## 6. Related

[`main.sol`](./main.sol) · [`SPEC.md`](./SPEC.md) · [`iFluidUsEquityMarketHours.sol`](../interfaces/iFluidUsEquityMarketHours.sol) · [`UsEquityMarketHoursCalendarLib.sol`](../../../../test/foundry/oracleV2/UsEquityMarketHoursCalendarLib.sol)
