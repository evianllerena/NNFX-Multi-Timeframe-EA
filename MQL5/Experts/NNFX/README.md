# Expert Advisors

| File | What | Status |
| --- | --- | --- |
| `NNFX_EA.mq5` | **The EA** (Phase 6f, `docs/DESIGN_6F.md`). One instance per timeframe, attached to any chart with its preset (`MQL5/Presets/NNFX_M30.set`, `NNFX_H1.set`, `NNFX_H4.set`; magic 26030 / 26060 / 26240), trades the preset's basket of pairs in a fixed order, each pair on its own clock. Rules core per pair, guard, news, exposure, orders through `Orders.mqh` only, decision log and trade log, state with each pair's core memory, restart per DESIGN_6F section 5. Orders only in the tester or on a DEMO account. Never defines `NNFX_TEST_BUILD` | Compiled (build 6241, 0/0). Tester: 4-month H1 run, two identical runs, three presets, two restart tests; demo: pause-crash test (see `docs/VERIFICATION.md`) |
| `NNFX_OrderTest.mq5` | TEST EA for 6b-6e: opens trades on a schedule so every order path runs; restart, guard, master-switch and panel tests. The only file that defines `NNFX_TEST_BUILD` | Compiled; see `docs/VERIFICATION.md` |
| `NNFX_RepaintCheck.mq5` | Phase 5 repaint check in the tester | Compiled |
| `NNFX_TemplateProbe.mq5` | 6d probe of chart templates (no trading) | Compiled |
