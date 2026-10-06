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
//|  - a REAL restart (demo): OnDeinit writes PRESTOP, OnInit        |
//|    rebuilds and writes REBUILD; the trade log is appended to     |
//|                                                                  |
//| Orders only in the tester or on a DEMO account (section 1).      |
//| Log: Common\Files\NNFX\trades\OrderTest_<symbol>_<tester|demo>.csv|
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
#property strict

// The ONLY file allowed to define this (tests/python/test_order_calls.py, S2b).
#define NNFX_TEST_BUILD
#include <NNFX\State.mqh>
#include <NNFX\BarBuilder.mqh>

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
input string InpRestartAt     = "";     // Tester: simulated restart at the first candle at/after this time ("" = none)
input bool   InpRestartDeleteState = false;    // Simulated or real restart: delete the state file before the rebuild
input bool   InpRestartIgnoreComments = false; // Simulated or real restart: the rebuild ignores order comments
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

int OnInit()
  {
   g_mode = (MQLInfoInteger(MQL_TESTER) != 0) ? "tester" : "demo";
   bool restart = false;
   if(g_mode == "tester")
     {
      // a tester agent keeps MQL5\Files between runs: start every tester run clean
      FileDelete(NNFXStatePath(Instance()));
      FileDelete(SchedulePath());
     }
   else
      restart = FileIsExist(NNFXStatePath(Instance())) || FileIsExist(SchedulePath());
   if(!g_log.Open("OrderTest_" + _Symbol + "_" + g_mode + ".csv", restart))
      return INIT_FAILED;
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
   if(restart)
     {
      // a REAL restart: rebuild before anything else (SPEC); the schedule is test scaffolding, kept apart
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
      SaveState();
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_orders != NULL)
     {
      Row("PRESTOP", StringFormat("deinit reason %d; state=", reason) + StateNow());
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
   g_orders.Poll("transaction");
  }

// The schedule for one new candle (unchanged from 6b).
void ScheduleStep(const double atr)
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
   if(InpRestartAt != "" && !g_restart_done && bar >= StringToTime(InpRestartAt))
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
      ScheduleStep(atr[0]);
     }
   RecordExit();
   g_proc = iTime(_Symbol, _Period, 1);
   Row("STATE", "proc=" + NNFXTime(g_proc) + "; state=" + StateNow());
   SaveState();
   SaveSchedule();
  }
//+------------------------------------------------------------------+
