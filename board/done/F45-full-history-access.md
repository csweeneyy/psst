# F45 - The assistant can reach any date

**Why**
It only ever saw 14 days, so anything older got a refusal.

**Acceptance**
- Every request carries 14 days daily, 12 weeks, and 12 months per habit, plus
  the habit's "tracked since" date
- `fetch_history` returns exact days for any range: the Worker ends its turn
  with a `dataRequest`, the device resolves it locally, and asks once more
- Exactly one retry, so a model that keeps asking cannot loop
- The intermediate pass is not recorded as a conversation turn

**Status**
Done. Eval case "reaches past two weeks for exact days" passes: it answered
day by day for the first week of August rather than refusing.
