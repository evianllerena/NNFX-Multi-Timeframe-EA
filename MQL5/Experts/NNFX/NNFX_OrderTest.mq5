//+------------------------------------------------------------------+
//| NNFX_OrderTest.mq5 - TEST EA for Phase 6b orders and 6c restart  |
//| recovery (docs/PLAN_PHASE6.md sections 3, 4 and 9). NOT the      |
//| trading EA: no entry/exit logic. It opens trades on a fixed      |
//| schedule so every order path runs, and logs every order event    |
//| for tools/check_trades.py.                                       |
//|                                                                  |
//| Schedule (one trade at a time, on the chart symbol):             |
//|  - a new trade when flat, every InpEveryBars closed candles      |
//|  - direction alternates long/short                               |
//|  - every 4th trade has the runner cap at 2 x ATR (T7)            |
//|  - every 5th trade gets a signal exit 8 candles after entry      |
//|  - the rest end at their stop, TP1 + breakeven, or the trail     |
//| Tester only (refused on demo by Orders.mqh):                     |
//|  - on the first candle a position WITHOUT a stop is opened, to   |
//|    prove EnforceStops closes it with an alarm (F3)               |
//|  - trade InpLoseReplyOn has its reply dropped once, to prove the |
//|    retry never opens a duplicate (OD-13)                         |
//|  - G1_phase6b_1 F1, one trade each: half 2 forced to fail        |
//|    (ABORT), stops level too wide (REFUSE), no free margin        |
//|    (REFUSE, OD-5), SL/TP planned off the fill (MODIFY, OD-14)    |
//| Phase 6c:                                                        |
//|  - a continuation tracker per candle (reference baseline and C1  |
//|    through BarBuilder; State.mqh NNFXContStep, as core.py)       |
//|  - a STATE row every candle (the whole memory) and the state     |
//|    file MQL5\Files\NNFX\state\OrderTest_<symbol>.txt (atomic)    |
//|  - InpRestartAt: a SIMULATED restart in the tester: all memory   |
//|    is thrown away and rebuilt (State.mqh) from the broker, the   |
//|    state file (optionally deleted first) and the candles         |
//|    (optionally ignoring comments); PRESTOP and REBUILD rows      |
//|  - a REAL restart (demo): OnDeinit writes PRESTOP; once MT5 is   |
//|    connected (+3 s, OnTimer) it rebuilds and writes REBUILD;     |
//|    nothing trades before that; the trade log is appended to      |
//|                                                                  |
//| Orders only in the tester or on a DEMO account (section 1).      |
//| Log: Common\Files\NNFX\trades\OrderTest_<symbol>_<tester|demo>.csv|
//| Status: compiled 2026-10-06 (build 6241, 0 errors, 0 warnings);  |
//| restart test (a) PASS (run restart_20261006_004837), real        |
//| restarts on the demo PASS (demo_restart_20261006_002457).        |
//+------------------------------------------------------------------+
#property strict

// The ONLY file allowed to define this (tests/python/test_order_calls.py, S2b).
#define NNFX_TEST_BUILD
#include <NNFX\State.mqh>
#include <NNFX\BarBuilder.mqh>
#include <NNFX\Guard.mqh>
#include <NNFX\Panel.mqh>

input double InpRiskPct       = 2.0;    // Risk % (M2)
input int    InpEveryBars     = 6;      // A new trade when flat, every N closed candles
input int    InpMaxTrades     = 0;      // Stop opening after N trades (0 = no limit)
input bool   InpMinLots       = false;  // Each half at the minimum lot (demo test)
input long   InpMagic         = 26999;  // Test magic (not one of the presets' 26030/26060/26240)
input bool   InpStoplessTest  = true;   // Tester only: open one stopless position on purpose
input int    InpLoseReplyOn   = 3;      // Tester only: drop the reply once on this trade number (0 = off)
input int    InpAbortOn       = 7;      // Tester only: half 2 forced to fail on this trade -> ABORT (0 = off)
input int    InpStopsRefuseOn = 9;      // Tester only: stops level 100000 points on this trade -> REFUSE (0 = off)
input int    InpMarginRefuseOn = 11;    // Tester only: free margin 0 on this trade -> REFUSE, OD-5 (0 = off)
input int    InpModifyOn      = 13;     // Tester only: SL/TP planned 20 points off on this trade -> MODIFY (0 = off)
input bool   InpStopWhenDone  = false;  // Remove the EA once InpMaxTrades trades were tried and none is open (demo run)
// "none" = no restart. Not "": the Strategy Tester treats an empty value in [TesterInputs] as not listed and reuses
// the last-used value (runs restart_20261005_225140 and 20261006_004127 restarted although "InpRestartAt=" was
// listed; kept in checks\invalid\).
input string InpRestartAt     = "none"; // Tester: simulated restart at the first candle at/after this time ("none" = no restart)
input bool   InpRestartDeleteState = false;    // Simulated or real restart: delete the state file before the rebuild
input bool   InpRestartIgnoreComments = false; // Simulated or real restart: the rebuild ignores order comments
// D-OPS-1 (owner, 2026-10-06): close this magic's leftover TEST trades and stop. DEMO only, magic 26990-26999 only;
// rebuilt from the broker like a restart, then closed through Orders.mqh (CloseRemaining), logged to
// Common\Files\NNFX\trades\OrderTest_<symbol>_cleanup.csv. Opens nothing.
input bool   InpCloseLeftovers = false;
// Phase 6d guard (Guard.mqh). Off = the 6b/6c behaviour. On: before each new entry the guard is asked; a blocked
// entry writes a SKIP row "blocked:<reasons>" and is not tried; open trades keep being managed (S-2).
input bool   InpGuard          = false;
input bool   InpInstanceOn     = true;   // this instance's switch
input int    InpServerWinterOffset = 2;  // broker clock (D6d-4, a setting, unverified): hours east of UTC in winter
input string InpServerDst      = "US";   // broker clock: daylight-saving rule "none", "EU" or "US"
input double InpWeekendHours   = 0;      // S-7: block the last N hours before the Friday boundary (0 = off)
input double InpMaxSpread      = 0;      // points; 0 = off (not set until spreads are measured)
input int    InpTesterMaster   = -1;     // TESTER ONLY: -1 = read NNFX_MASTER, 1 = on, 0 = off (refused outside it)
// TESTER ONLY: at the first candle at/after this time the drawdown pause is switched on as if equity had fallen 10%,
// so a pause can start while a trade is open ("none" = off; refused outside the tester). The limits otherwise trip
// from closed losses only, with the account flat (run 6d_drawdown_pause_20261006_114114).
input string InpTesterPauseAt  = "none";
// DEMO master-switch test (PLAN 6d), test magics 26990-26999 only (D-OPS-1): this instance (A) sets NNFX_MASTER = 1,
// opens a second chart (InpMasterTestSymbol, same period) with the template InpMasterTestTpl (instance B, written by
// tools/run_demo_master_test.ps1), switches NNFX_MASTER to 0 after InpMasterOffAfter candles and back to 1 after
// InpMasterOffFor more. Every change is a GUARD row. "" = off.
input string InpMasterTestTpl  = "";
input string InpMasterTestSymbol = "GBPUSD";
input int    InpMasterOffAfter = 5;
input int    InpMasterOffFor   = 5;
input string InpBaseline      = "ref_baseline_sma20.txt";  // Profiles (Common\Files\NNFX\profiles) for the tracker
input string InpC1            = "ref_c1_rvi10.txt";
input string InpC2            = "ref_c2_macd_main.txt";
input string InpExit          = "ref_exit_macd_cross.txt";
input string InpVolume        = "ref_volume_ticks20.txt";

CNNFXOrders     *g_orders = NULL;
CNNFXTradeLog    g_log;
CNNFXBarBuilder  g_bb;
int              g_atr = INVALID_HANDLE;
datetime         g_last_bar = 0;
int              g_bars_flat = 0;
int              g_trade_no = 0;
string           g_current = "";
int              g_cur_dir = 0;
bool             g_exit_recorded = true;
int              g_exit_after = 0;    // candles after entry for a signal exit (0 = none)
int              g_bars_in_trade = 0;
bool             g_stopless_done = false;
string           g_mode = "";
NNFXCont         g_cont;
bool             g_has_cont = false;
datetime         g_proc = 0;           // open time of the last processed candle
bool             g_restart_done = false;
bool             g_cleanup = false;     // InpCloseLeftovers run: no trading at all
NNFXBroker       g_broker;
NNFXDrawdown     g_dd;
bool             g_dl_was = false;      // daily loss blocked at the last candle (to log the change once)
bool             g_pause_forced = false;
string           g_last_blocks = "-";   // the guard's block reasons at the last candle ("-" = not evaluated yet)
int              g_master_candles = -1;  // candles since the master-switch test started (-1 = not running)
CNNFXPanel       g_panel;               // chart buttons (live charts only)
bool             g_panel_on = false;
bool             g_pending_rebuild = false;  // a real restart: no trading until the rebuild has run (OnTimer)
uint             g_ready_since = 0;     // GetTickCount() when MT5 was first seen connected and logged in
string           g_last_saved = "";

string TradeId(const int k)          { return StringFormat("T%04d", k); }
string Instance(void)                { return "OrderTest_" + _Symbol; }
string SchedulePath(void)            { return "NNFX\\state\\OrderTest_" + _Symbol + "_schedule.txt"; }

void ContArray(NNFXCont &conts[])
  {
   ArrayResize(conts, g_has_cont ? 1 : 0);
   if(g_has_cont)
      conts[0] = g_cont;
  }

string StateNow(void)
  {
   NNFXTrade trades[];
   g_orders.ExportTrades(trades);
   NNFXCont conts[];
   ContArray(conts);
   string lines[];
   NNFXSerialize(trades, conts, lines);
   return NNFXJoin(lines, " / ");
  }

void Row(const string event, const string note)
  {
   NNFXLogRow r;
   NNFXLogRowClear(r);
   r.event = event;
   r.symbol = _Symbol;
   r.magic = InpMagic;
   r.note = note;
   g_log.Write(r);
  }

void SaveState(void)
  {
   NNFXTrade trades[];
   g_orders.ExportTrades(trades);
   NNFXCont conts[];
   ContArray(conts);
   string text = NNFXStateText(Instance(), trades, conts, g_proc);
   if(text == g_last_saved)
      return;
   if(NNFXStateSave(Instance(), text))
      g_last_saved = text;
   else
      Row("ALARM", "state file could not be saved, error " + IntegerToString(GetLastError()));
  }

// Test scaffolding only (not trading state): the schedule, kept apart from the state file under test.
void SaveSchedule(void)
  {
   int h = FileOpen(SchedulePath(), FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileWriteString(h, StringFormat("%d|%d|%s|%d|%d|%d|%d|%d\r\n", g_trade_no, g_bars_flat, g_current, g_exit_after,
                                   g_bars_in_trade, g_cur_dir, g_exit_recorded ? 1 : 0, g_stopless_done ? 1 : 0));
   FileClose(h);
  }

void LoadSchedule(void)
  {
   if(!FileIsExist(SchedulePath()))
      return;
   int h = FileOpen(SchedulePath(), FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   string p[];
   if(StringSplit(FileReadString(h), '|', p) == 8)
     {
      g_trade_no = (int)StringToInteger(p[0]);
      g_bars_flat = (int)StringToInteger(p[1]);
      g_current = p[2];
      g_exit_after = (int)StringToInteger(p[3]);
      g_bars_in_trade = (int)StringToInteger(p[4]);
      g_cur_dir = (int)StringToInteger(p[5]);
      g_exit_recorded = (p[6] == "1");
      g_stopless_done = (p[7] == "1");
     }
   FileClose(h);
  }

// Test scaffolding after a rebuild: the schedule remembers its current trade by ID. After a "deal history only"
// rebuild (no comments, no state file) that trade carries the fallback ID "R<half 1 ticket>" instead
// (G1_phase6c_1 F3), so the schedule follows it; otherwise it would think it is flat and open another trade.
// The test EA has one trade open at a time. Logged as INFO (compare_runs leaves INFO rows out).
void ScheduleAdoptRebuilt(void)
  {
   if(g_current == "" || g_orders.IsOpen(g_current))
      return;
   NNFXTrade t[];
   g_orders.ExportTrades(t);
   for(int i = 0; i < ArraySize(t); i++)
      if(t[i].sym == _Symbol)
        {
         Row("INFO", "schedule: current trade " + g_current + " is " + t[i].id + " after the rebuild");
         g_current = t[i].id;
         return;
        }
  }

int SideOf(const NNFXBar &b)
  {
   if(!MathIsValidNumber(b.base) || b.base >= EMPTY_VALUE)
      return 0;
   return (b.c > b.base) ? 1 : ((b.c < b.base) ? -1 : 0);
  }

// Closed candles (the ones BarBuilder can build) from `from` to the candle at `upto`, oldest first.
void GatherCandles(const datetime from, const datetime upto, NNFXCandleRec &recs[])
  {
   ArrayResize(recs, 0);
   int first = iBarShift(_Symbol, _Period, from, false);
   int last = iBarShift(_Symbol, _Period, upto, false);
   for(int shift = first; shift >= MathMax(last, 1); shift--)
     {
      NNFXBar b;
      NNFXRaw r;
      if(!g_bb.Build(shift, b, r))
         continue;
      int n = ArraySize(recs);
      ArrayResize(recs, n + 1);
      recs[n].sym = _Symbol;
      recs[n].time = (datetime)b.t;
      recs[n].close = b.c;
      recs[n].atr = b.atr;
      recs[n].side = SideOf(b);
      recs[n].c1 = b.c1;
     }
  }

// Rebuilds the order memory and the continuation tracker from the broker, the state file and the candles.
string Rebuild(const datetime upto, const bool deleteState, const bool ignoreComments)
  {
   if(deleteState)
      FileDelete(NNFXStatePath(Instance()));
   string lines[];
   string status = "absent";
   NNFXTrade st[];
   NNFXCont sc[];
   datetime proc = 0;
   string why = "";
   if(NNFXStateReadLines(Instance(), lines))
      status = NNFXStateParse(lines, st, sc, proc, why);
   NNFXPosRec pos[];
   NNFXDealRec deals[];
   datetime from = (MQLInfoInteger(MQL_TESTER) != 0) ? 0 : TimeCurrent() - 30 * 86400;
   NNFXGatherBroker(InpMagic, from, pos, deals);
   // candles back to the latest entry and to every open position's entry (plus the decision candle)
   datetime minTime = upto, latestIn = 0;
   for(int i = 0; i < ArraySize(deals); i++)
      if(deals[i].entry == "IN" && deals[i].sym == _Symbol)
         latestIn = MathMax(latestIn, deals[i].time);
   if(latestIn > 0)
      minTime = MathMin(minTime, latestIn);
   for(int i = 0; i < ArraySize(deals); i++)
      if(deals[i].entry == "IN")
         for(int p = 0; p < ArraySize(pos); p++)
            if(pos[p].pos == deals[i].pos)
               minTime = MathMin(minTime, deals[i].time);
   NNFXCandleRec candles[];
   GatherCandles(minTime - 2 * PeriodSeconds(), upto, candles);
   NNFXTrade out[];
   NNFXCont conts[];
   string notes;
   NNFXRebuildPure(pos, deals, status, st, candles, PeriodSeconds(), InpMagic, upto, ignoreComments, out, conts, notes);
   if(why != "")
      NNFXAddNote(notes, "state file problem: " + why);
   g_orders.ImportTrades(out);
   g_has_cont = false;
   for(int i = 0; i < ArraySize(conts); i++)
      if(conts[i].sym == _Symbol)
        {
         g_cont = conts[i];
         g_has_cont = true;
        }
   g_last_saved = "";
   StringReplace(notes, "\n", " | ");
   return notes;
  }

bool NewOrders(void)
  {
   if(g_orders != NULL)
      delete g_orders;
   g_orders = new CNNFXOrders();
   return g_orders.Init(InpMagic, GetPointer(g_log), 1.5, 1.0, 2.0, 1.5);
  }

// D-OPS-1: rebuild this magic's open test trades from the broker and close each one through Orders.mqh.
void CloseLeftovers(void)
  {
   string notes = Rebuild(iTime(_Symbol, _Period, 1), false, false);
   Row("REBUILD", "leftover cleanup (D-OPS-1); state=" + StateNow() + "; notes=" + notes);
   NNFXTrade t[];
   int n = g_orders.ExportTrades(t);
   int closed = 0;
   for(int i = 0; i < n; i++)
      if(g_orders.CloseRemaining(t[i].id, "leftover TEST trade closed (D-OPS-1, owner 2026-10-06)"))
         closed++;
   int mine = 0, tests = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk))
         continue;
      long m = PositionGetInteger(POSITION_MAGIC);
      if(m == InpMagic)
         mine++;
      if(m >= 26990 && m <= 26999)
         tests++;
     }
   Row("INFO", StringFormat("cleanup magic %I64d: %d open trades found, %d closed; positions left: this magic %d, "
                            "test magics 26990-26999 %d, whole account %d", InpMagic, n, closed, mine, tests,
                            PositionsTotal()));
  }

// DEMO master-switch test (instance A only): start, switch off, switch on; one step per candle
void MasterTestStep(void)
  {
   if(InpMasterTestTpl == "")
      return;
   if(g_master_candles < 0)
     {
      GlobalVariableSet(NNFX_GV_MASTER, 1.0);
      long id = ChartOpen(InpMasterTestSymbol, _Period);
      bool ok = (id > 0) && ChartApplyTemplate(id, InpMasterTestTpl);
      Row("GUARD", StringFormat("TEST master switch: NNFX_MASTER = 1; chart %s opened (id %I64d) with template %s: %s, error %d",
                                InpMasterTestSymbol, id, InpMasterTestTpl, ok ? "applied" : "FAILED", GetLastError()));
      g_master_candles = 0;
      return;
     }
   g_master_candles++;
   if(g_master_candles == InpMasterOffAfter)
     {
      GlobalVariableSet(NNFX_GV_MASTER, 0.0);
      Row("GUARD", "TEST master switch: NNFX_MASTER = 0 (OFF)");
     }
   else if(g_master_candles == InpMasterOffAfter + InpMasterOffFor)
     {
      GlobalVariableSet(NNFX_GV_MASTER, 1.0);
      Row("GUARD", "TEST master switch: NNFX_MASTER = 1 (ON)");
     }
   else
     {
      // then the chart buttons, through the panel's own handlers (test build: custom events, auto-confirmed)
      int k = g_master_candles - (InpMasterOffAfter + InpMasterOffFor);
      int action = (k == 1 || k == 3) ? NNFX_PANEL_INSTANCE : (k == 5 ? NNFX_PANEL_DDRESET : (k == 7 ? NNFX_PANEL_CLOSEALL : 0));
      if(action != 0)
        {
         Row("GUARD", StringFormat("TEST panel: button %d sent as custom event", action));
         EventChartCustom(0, (ushort)(NNFX_PANEL_TEST_EVENT_BASE + action), InpMagic, 0.0, "test");
        }
     }
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(!g_panel_on)
      return;
   int a = g_panel.OnEvent(id, lparam, dparam, sparam);
   if(a == NNFX_PANEL_INSTANCE)
      Row("GUARD", "instance switch " + (NNFXInstanceOn(_Symbol, InpMagic, InpInstanceOn) ? "ON" : "OFF") + " by the chart button");
   else if(a == NNFX_PANEL_DDRESET)
      Row("GUARD", "drawdown reset requested by the chart button (confirmed): NNFX_DD_RESET = 1, applied at the next candle");
   else if(a == NNFX_PANEL_CLOSEALL)
     {
      NNFXTrade t[];
      int n = g_orders.ExportTrades(t);
      Row("GUARD", StringFormat("close-all by the chart button (confirmed): %d trade(s) of this instance", n));
      for(int i = 0; i < n; i++)
         g_orders.CloseRemaining(t[i].id, "close-all button (confirmed)");
     }
  }

// The guard at a candle close (6d). Server time = TimeCurrent() (the broker's clock; never TimeLocal, D6d-4).
string GuardAtCandle(const bool indicatorOk)
  {
   datetime t = TimeCurrent();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   // drawdown (R-12, OD-2): the owner's reset first (D6d-3, logged), then this candle's equity sample
   NNFXDrawdownLoad(g_dd);
   string resetText;
   if(NNFXDrawdownResetRequested(g_dd, equity, resetText))
      Row("GUARD", resetText);
   bool was = g_dd.paused;
   NNFXDrawdownSample(g_dd, equity);
   if(g_mode == "tester" && InpTesterPauseAt != "none" && !g_pause_forced && t >= StringToTime(InpTesterPauseAt))
     {
      g_pause_forced = true;
      if(!g_dd.paused)
        {
         g_dd.paused = true;
         was = true;   // logged here, not as a real pause
         Row("GUARD", StringFormat("TEST: drawdown pause forced (InpTesterPauseAt %s, tester only); %d trade(s) open",
                                   InpTesterPauseAt, g_orders.TradeCount()));
        }
     }
   NNFXDrawdownSave(g_dd);
   if(g_dd.paused && !was)
     {
      string why = StringFormat("drawdown pause (R-12): equity %.2f <= 90%% of the peak %.2f; reset by hand only (S-6)",
                                equity, g_dd.peak);
      Row("GUARD", why);
      NNFXNotify(why);
     }
   // daily loss (S-5, D6d-2): the account's closed deals since the trading day boundary
   datetime start = NNFXTradingDayStart(g_broker, t);
   datetime times[];
   double profits[];
   if(HistorySelect(start, t + 60))
     {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
            continue;
         int k = ArraySize(times);
         ArrayResize(times, k + 1);
         ArrayResize(profits, k + 1);
         times[k] = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         profits[k] = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                      HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
        }
     }
   double pl, limit;
   bool dl = NNFXDailyLoss(g_broker, t, AccountInfoDouble(ACCOUNT_BALANCE), InpRiskPct, times, profits, pl, limit);
   if(dl && !g_dl_was)
     {
      string why = StringFormat("daily loss limit (S-5, D6d-2): today's closed P/L %.2f <= %.2f since %s",
                                pl, limit, NNFXTime(start));
      Row("GUARD", why);
      NNFXNotify(why);
     }
   g_dl_was = dl;
   int master = NNFXMasterState();
   if(g_mode == "tester" && InpTesterMaster >= 0)
      master = InpTesterMaster;
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return NNFXGuardBlocks(master, NNFXInstanceOn(_Symbol, InpMagic, InpInstanceOn), g_dd.paused, dl, NNFXInRollover(g_broker, t),
                          NNFXInWeekendBlock(g_broker, t, InpWeekendHours), spread, InpMaxSpread, indicatorOk);
  }

int OnInit()
  {
   g_mode = (MQLInfoInteger(MQL_TESTER) != 0) ? "tester" : "demo";
   g_broker.name = AccountInfoString(ACCOUNT_SERVER);
   g_broker.winter_offset = InpServerWinterOffset;
   g_broker.dst = InpServerDst;
   if(InpGuard && InpServerDst != "none" && InpServerDst != "EU" && InpServerDst != "US")
     {
      Print("NNFX_OrderTest: InpServerDst must be none, EU or US");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMasterTestTpl != "" && (MQLInfoInteger(MQL_TESTER) != 0 || InpMagic < 26990 || InpMagic > 26999 ||
                                  AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO || !InpGuard))
     {
      Print("NNFX_OrderTest: the master-switch test is demo only, test magic 26990-26999, with InpGuard=true");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTesterPauseAt != "none" && MQLInfoInteger(MQL_TESTER) == 0)
     {
      Print("NNFX_OrderTest: InpTesterPauseAt is for the Strategy Tester only");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTesterMaster >= 0 && MQLInfoInteger(MQL_TESTER) == 0)
     {
      Print("NNFX_OrderTest: InpTesterMaster is for the Strategy Tester only (live: the NNFX_MASTER global variable)");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpCloseLeftovers)
     {
      if(g_mode != "demo" || InpMagic < 26990 || InpMagic > 26999 ||
         AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
        {
         Print("NNFX_OrderTest: InpCloseLeftovers refused (DEMO account and magic 26990-26999 only, D-OPS-1)");
         return INIT_FAILED;
        }
      g_mode = "cleanup";
      g_cleanup = true;
     }
   bool restart = false;
   if(g_cleanup)
      restart = false;
   else if(g_mode == "tester")
     {
      // a tester agent keeps MQL5\Files between runs: start every tester run clean
      FileDelete(NNFXStatePath(Instance()));
      FileDelete(SchedulePath());
     }
   else
      restart = FileIsExist(NNFXStatePath(Instance())) || FileIsExist(SchedulePath());
   if(!g_log.Open("OrderTest_" + _Symbol + "_" + g_mode + ".csv", restart))
      return INIT_FAILED;
   if(InpGuard && g_mode == "tester")
      // PLAN 6d: are the terminal's global variables visible in the tester? NNFX_GuardTest sets this probe
      Row("INFO", StringFormat("tester global variables: NNFX_TESTER_PROBE %s; NNFX_MASTER %s",
                               GlobalVariableCheck("NNFX_TESTER_PROBE") ? "visible" : "NOT visible",
                               GlobalVariableCheck(NNFX_GV_MASTER) ? "visible" : "missing"));
   if(!NewOrders())
      return INIT_FAILED;
   g_atr = iATR(_Symbol, _Period, 14);
   string profiles[5];
   profiles[0] = InpBaseline;
   profiles[1] = InpC1;
   profiles[2] = InpC2;
   profiles[3] = InpExit;
   profiles[4] = InpVolume;
   if(g_atr == INVALID_HANDLE || !g_bb.Init(_Symbol, _Period, profiles, true))
     {
      Print("NNFX_OrderTest: init failed: ", g_bb.Error());
      return INIT_FAILED;
     }
   // A real restart and the cleanup read the broker's positions and deals. OnInit can run before MT5 has
   // logged in and synchronized (cleanup run cleanup_20261006_091948: EA loaded 09:19:57.504, "terminal
   // synchronized" 09:19:58.017), so both wait in OnTimer until MT5 is connected, logged in and has a tick
   // value, plus 3 s. Nothing trades before that (OnTick and OnTradeTransaction return).
   if(g_cleanup || restart)
     {
      g_pending_rebuild = restart;
      EventSetTimer(1);
     }
   if(g_mode == "demo" && !g_cleanup)
     {
      g_panel.Init(0, _Symbol, InpMagic, InpInstanceOn);
      g_panel_on = true;
     }
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   if(!g_cleanup && !g_pending_rebuild)
     {
      EventKillTimer();
      return;
     }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || AccountInfoInteger(ACCOUNT_LOGIN) == 0 ||
      !(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) > 0.0))
     {
      g_ready_since = 0;
      return;
     }
   if(g_ready_since == 0)
     {
      g_ready_since = GetTickCount();
      return;
     }
   if(GetTickCount() - g_ready_since < 3000)
      return;
   EventKillTimer();
   if(g_cleanup)
     {
      CloseLeftovers();
      ExpertRemove();
      return;
     }
   RealRestartRebuild();
   g_pending_rebuild = false;
  }

// a REAL restart: rebuild before anything else (SPEC); the schedule is test scaffolding, kept apart
void RealRestartRebuild(void)
  {
      LoadSchedule();
      string lines[];
      NNFXTrade st[];
      NNFXCont sc[];
      datetime proc = 0;
      string why;
      if(NNFXStateReadLines(Instance(), lines) && NNFXStateParse(lines, st, sc, proc, why) == "present" &&
         !InpRestartDeleteState)
         g_proc = proc;
      else
         g_proc = iTime(_Symbol, _Period, 1);   // OD-7: the EA skips to the next new candle anyway
      string notes = Rebuild(g_proc, InpRestartDeleteState, InpRestartIgnoreComments);
      Row("REBUILD", "real restart; state=" + StateNow() + "; notes=" + notes);
      ScheduleAdoptRebuilt();
      SaveState();
  }

void OnDeinit(const int reason)
  {
   if(g_panel_on)
      g_panel.Remove();
   if(g_orders != NULL)
     {
      // stopped before the deferred rebuild ran: the memory is empty, which is not the state before this stop
      Row("PRESTOP", StringFormat("deinit reason %d; ", reason) +
          (g_pending_rebuild ? "stopped before the rebuild ran (no state)" : "state=" + StateNow()));
      int h = FileOpen("NNFX\\trades\\OrderTest_" + _Symbol + "_" + g_mode + "_summary.txt",
                       FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(h != INVALID_HANDLE)
        {
         FileWriteString(h, StringFormat("NNFX_OrderTest %s %s, build %d, magic %I64d, deinit reason %d\r\n", _Symbol, g_mode,
                                         (int)TerminalInfoInteger(TERMINAL_BUILD), InpMagic, reason));
         FileWriteString(h, "log: Common\\Files\\" + g_log.Path() + "\r\n");
         FileWriteString(h, StringFormat("RESULT: run complete, %d trades opened\r\n", g_trade_no));
         FileClose(h);
        }
      delete g_orders;
      g_orders = NULL;
     }
   g_log.Close();
   if(g_atr != INVALID_HANDLE)
      IndicatorRelease(g_atr);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(g_cleanup || g_pending_rebuild)
      return;
   g_orders.Poll("transaction");
  }

// The schedule for one new candle (unchanged from 6b).
void ScheduleStep(const double atr, const string blocks)
  {
   if(g_current != "" && g_orders.IsOpen(g_current))
     {
      g_bars_in_trade++;
      if(g_exit_after > 0 && g_bars_in_trade >= g_exit_after)
         g_orders.CloseRemaining(g_current, "scripted signal exit after " + IntegerToString(g_exit_after) + " candles");
      return;
     }
   g_current = "";
   g_bars_flat++;
   if(g_bars_flat < InpEveryBars)
      return;
   if(blocks != "")
     {
      // a new entry is due but the guard blocks it: not tried, the trade number is not used; tried again next candle
      Row("SKIP", "blocked:" + blocks);
      return;
     }
   if(InpMaxTrades > 0 && g_trade_no >= InpMaxTrades)
     {
      if(InpStopWhenDone)
        {
         Print("NNFX_OrderTest: ", g_trade_no, " trades tried and none open: removing the EA (InpStopWhenDone)");
         ExpertRemove();
        }
      return;
     }
   g_trade_no++;
   int k = g_trade_no;
   int dir = (k % 2 == 1) ? 1 : -1;
   double cap = (k % 4 == 0) ? 2.0 : NNFX_CAP_OFF;
   g_exit_after = (k % 5 == 0) ? 8 : 0;
   if(g_mode == "tester")
     {
      if(InpLoseReplyOn > 0 && k == InpLoseReplyOn)
         g_orders.TestLoseNextReply();
      if(InpAbortOn > 0 && k == InpAbortOn)
         g_orders.TestFailNextHalf2();
      if(InpStopsRefuseOn > 0 && k == InpStopsRefuseOn)
         g_orders.TestStopsLevelOverride(100000);
      if(InpMarginRefuseOn > 0 && k == InpMarginRefuseOn)
         g_orders.TestFreeMarginOverride(0.0);
      if(InpModifyOn > 0 && k == InpModifyOn)
         g_orders.TestFillOffset(20);
     }
   string id = TradeId(k);
   if(g_orders.OpenTrade(_Symbol, dir, atr, InpRiskPct, cap, id, InpMinLots))
     {
      g_current = id;
      g_cur_dir = dir;
      g_exit_recorded = false;
      g_bars_in_trade = 0;
      NNFXContStart(g_cont, _Symbol, dir, TimeCurrent(), PeriodSeconds());   // a new trade starts the tracker (I-12)
      g_cont.last_exit_dir = g_has_cont ? g_cont.last_exit_dir : 0;
      g_has_cont = true;
     }
   g_bars_flat = 0;
  }

// Last exit direction as soon as the current trade is fully closed (every tick, and again before each STATE row,
// so a trade closed while a candle is processed is never shown as still unrecorded).
void RecordExit(void)
  {
   if(g_current != "" && !g_exit_recorded && !g_orders.IsOpen(g_current))
     {
      g_exit_recorded = true;
      if(g_has_cont)
         g_cont.last_exit_dir = g_cur_dir;
     }
  }

void OnTick()
  {
   if(g_cleanup || g_pending_rebuild)
      return;
   g_orders.EnforceStops();
   g_orders.Poll("tick");
   RecordExit();
   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar == g_last_bar)
     {
      SaveState();
      return;
     }
   bool first = (g_last_bar == 0);
   g_last_bar = bar;
   if(first)
      return;   // decisions only from the second candle on (and OD-7 after a restart)

   // a SIMULATED restart (tester): everything in memory is thrown away and rebuilt, before this candle is processed
   if(InpRestartAt != "none" && InpRestartAt != "" && !g_restart_done && bar >= StringToTime(InpRestartAt))
     {
      g_restart_done = true;
      string before = StateNow();
      Row("PRESTOP", "simulated restart; state=" + before);
      if(!NewOrders())
         return;
      g_has_cont = false;
      string notes = Rebuild(g_proc, InpRestartDeleteState, InpRestartIgnoreComments);
      string after = StateNow();
      Row("REBUILD", "match=" + (after == before ? "yes" : "no") + "; state=" + after + "; notes=" + notes);
      ScheduleAdoptRebuilt();
     }

   NNFXBar b;
   NNFXRaw raw;
   bool ok = g_bb.Build(1, b, raw);
   if(ok && g_has_cont)
      NNFXContStep(g_cont, SideOf(b), b.c1);

   double atr[1];
   bool haveAtr = (CopyBuffer(g_atr, 0, 1, 1, atr) == 1 && atr[0] > 0);
   if(haveAtr)
     {
      double close = iClose(_Symbol, _Period, 1);
      if(InpStoplessTest && !g_stopless_done && g_mode == "tester")
        {
         g_stopless_done = true;
         if(g_orders.NNFXTestOpenWithoutStop(_Symbol, 1, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), "TS01"))
            g_orders.EnforceStops();
        }
      g_orders.OnBarClose(_Symbol, close, atr[0]);
      g_orders.Reconcile();
      MasterTestStep();
      string blocks = InpGuard ? GuardAtCandle(ok) : "";
      if(InpGuard && blocks != g_last_blocks)
        {
         // every change of the block reasons, open trade or not (a SKIP is written only when an entry is due)
         Row("GUARD", "blocks: " + (blocks == "" ? "none" : blocks) + " (was " +
             (g_last_blocks == "" ? "none" : g_last_blocks) + ")");
         g_last_blocks = blocks;
        }
      ScheduleStep(atr[0], blocks);
     }
   RecordExit();
   g_proc = iTime(_Symbol, _Period, 1);
   Row("STATE", "proc=" + NNFXTime(g_proc) + "; state=" + StateNow());
   SaveState();
   SaveSchedule();
  }
//+------------------------------------------------------------------+
