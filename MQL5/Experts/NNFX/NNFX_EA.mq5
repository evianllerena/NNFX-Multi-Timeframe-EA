//+------------------------------------------------------------------+
//| NNFX_EA.mq5 - the NNFX EA (Phase 6f; docs/PLAN_PHASE6.md 6f,     |
//| docs/DESIGN_6F.md). One instance per timeframe (presets          |
//| NNFX_M30 / NNFX_H1 / NNFX_H4, magic 26030 / 26060 / 26240) trades|
//| a basket of pairs from one chart (S-1).                          |
//|                                                                  |
//| Per pair: a BarBuilder (5 indicator slots + ATR), the rules core |
//| (RulesCore.mqh, the port of core.py, unaltered) and its own      |
//| clock. On every tick and a 1 s timer the pairs are visited in    |
//| the preset's fixed order; a pair is processed once when its own  |
//| new closed candle exists (R-3), never mid-candle.                |
//|                                                                  |
//| At one candle close, per pair (DESIGN_6F section 3):             |
//|  block = Guard (6d) + News N1/N2 (6e) + "diverge" (below), then  |
//|          a trial run of the core finds the ENTERs; Exposure (6a) |
//|          allocates them across the basket in the fixed order and |
//|          a signal allocated 0 gets "exposure" (section 4)        |
//|  news  = the X5 first-close flag (6e)                            |
//|  the core runs; ENTER -> Orders.OpenTrade now (the core fills at |
//|  this open); EXIT -> Orders.CloseRemaining. TP1, breakeven and   |
//|  the trail stay with Orders.mqh (broker-held, 6b).               |
//|  D6f-1: core flat + broker open -> the broker trade is closed;   |
//|  core open + broker flat -> no action, the core cannot enter     |
//|  until its own simulation closes. Both logged as DIVERGE.        |
//|  One decision-log row (DecisionLog.mqh).                         |
//| State (broker map + every pair's core memory, PCORE lines) is    |
//| saved at every candle and after every trade event (6c note 1).   |
//|                                                                  |
//| Start and restart (DESIGN_6F section 5): wait for MT5 connected, |
//| logged in, tick values, +3 s; the broker side is rebuilt (6c);   |
//| each pair's core memory is restored from its PCORE line and the  |
//| candles it missed are fed with block "missed" (OD-7 (b): never   |
//| acted on). A replay with no blocks is a cross-check only. A      |
//| start-up disagreement is a DIVERGE row + alarm, never a close;   |
//| D6f-1 applies from the first live candle. A pair with no saved   |
//| memory starts flat (warm-up candles with block "start"); if the  |
//| broker holds a trade the core does not know [C, open question]: |
//| it is left to its broker-held stops and the pair takes no new    |
//| entry while it is open (block "diverge").                        |
//|                                                                  |
//| Orders only in the Strategy Tester or on a DEMO account          |
//| (Orders.mqh, section 1). Never defines NNFX_TEST_BUILD (F3).     |
//| Never uses TimeLocal (D6d-4).                                    |
//| Logs (Common\Files\NNFX): trades\EA_<tf>_<magic>_<mode>.csv,     |
//| decisions\EA_<tf>_<magic>_<mode>.csv. State: MQL5\Files\NNFX\    |
//| state\EA_<magic>.txt.                                            |
//| Status: compiles (build 6241, 0 errors, 0 warnings); not yet run.|
//+------------------------------------------------------------------+
#property strict

#include <NNFX\State.mqh>
#include <NNFX\BarBuilder.mqh>
#include <NNFX\Guard.mqh>
#include <NNFX\Panel.mqh>
#include <NNFX\News.mqh>
#include <NNFX\Exposure.mqh>
#include <NNFX\DecisionLog.mqh>

input long   InpMagic         = 26060;   // Magic number (OD-16: 30M 26030, 1H 26060, 4H 26240)
input string InpPairs         = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY";   // Pairs, in the fixed processing order
input double InpRiskPct       = 2.0;     // Risk % per trade (M2)
input string InpExposureMode  = "first"; // Same-currency exposure (M6/M7): first or split
// Rule settings (SPEC Settings; the defaults are the approved ones). Stop 1.5, TP1 1.0 and the 1 x ATR distance from
// the baseline are fixed (A-level) and not inputs.
input bool   InpTrailOn       = true;    // T4 trailing stop
input double InpTrailStart    = 2.0;     // T4 switch-on: a close this many entry ATRs beyond entry
input double InpTrailDist     = 1.5;     // T4 distance behind the close, in ATRs
input double InpRunnerCap     = 0.0;     // T7 runner cap in ATRs (0 = off)
input bool   InpExitOnExitInd = true;    // X2
input bool   InpExitOnC1      = true;    // X3
input bool   InpExitOnBaseline = true;   // X4
input bool   InpNewsExit      = true;    // X5
input bool   InpPullback      = true;    // E3
input bool   InpOneCandle     = true;    // E4
input bool   InpBridgeTooFar  = true;    // E5
input int    InpBridgeBars    = 7;       // E5 candles
input string InpContinuation  = "a";     // E6: off, a or b
input string InpBaseline      = "ref_baseline_sma20.txt";  // Profiles (Common\Files\NNFX\profiles)
input string InpC1            = "ref_c1_rvi10.txt";
input string InpC2            = "ref_c2_macd_main.txt";
input string InpExit          = "ref_exit_macd_cross.txt";
input string InpVolume        = "ref_volume_ticks20.txt";
// Guard (6d)
input bool   InpInstanceOn    = true;    // this instance's switch (the chart button overrides it)
input int    InpServerWinterOffset = 2;  // broker clock (D6d-4, a setting, unverified): hours east of UTC in winter
input string InpServerDst     = "US";    // broker clock: daylight-saving rule none, EU or US
input double InpWeekendHours  = 0;       // S-7: block the last N hours before the Friday boundary (0 = off)
input double InpMaxSpread     = 0;       // points; 0 = off
// News (6e). The event file is written by NNFX_CalendarExport (times in UTC); "none" = no blackouts.
input bool   InpNewsBlock     = true;    // N1 on/off (SPEC Settings)
input string InpNewsFile      = "NNFX\\calendar\\events_2019.01_2026.09.txt";   // Common\Files
input string InpBlackouts     = "none";  // N2 (OD-19): CUR:YYYY.MM.DD-YYYY.MM.DD;... or none
input double InpNewsMaxAgeHours = 24;    // live: alarm when the file is older (OD-12)
input int    InpWarmupBars    = 300;     // candles fed at start (warm-up, cross-check, longest restore gap)
// TESTER ONLY ("none" = off; refused outside the tester). Not "": the tester reuses the last value for an empty input.
input int    InpTesterMaster  = -1;      // -1 = read NNFX_MASTER (live), 1 = on, 0 = off (the tester cannot see terminal GVs)
input string InpTesterMasterOff = "none"; // "YYYY.MM.DD HH:MI;YYYY.MM.DD HH:MI": master OFF in this window
input string InpRestartAt     = "none";  // a simulated restart at the first candle at/after this time
input bool   InpRestartDeleteState = false;  // the simulated restart deletes the state file first

#define EA_MISSED "missed"   // block reason for candles the EA did not see live (OD-7 (b))
#define EA_START  "start"    // block reason for warm-up candles (not logged)

CNNFXOrders      *g_orders = NULL;
CNNFXTradeLog     g_log;
CNNFXDecisionLog  g_dlog;
NNFXSettings      g_set;
string            g_pairs[];
CNNFXBarBuilder  *g_bb[];
CNNFXPairCore    *g_core[];
datetime          g_proc[];        // open time of the last candle each pair processed
datetime          g_prevClose[];   // that candle's close (X5's previous actual close)
bool              g_orphan[];      // the broker holds a trade the core does not know (start without memory)
bool              g_waitAlarm[];   // "core open, broker flat" alarmed for this episode
string            g_mode = "";
bool              g_ready = false;
uint              g_ready_since = 0;
bool              g_restart_done = false;
NNFXBroker        g_broker;
NNFXDrawdown      g_dd;
bool              g_dl_was = false;
string            g_global_was = "-";
NNFXNewsEvent     g_news[];
NNFXBlackout      g_blackouts[];
datetime          g_news_loaded = 0;
bool              g_news_ok = false;
CNNFXPanel        g_panel;
bool              g_panel_on = false;
string            g_last_saved = "";
datetime          g_masterOffFrom = 0, g_masterOffTo = 0;

string Tf(void)         { string s = EnumToString((ENUM_TIMEFRAMES)_Period); StringReplace(s, "PERIOD_", ""); return s; }
string Instance(void)   { return StringFormat("EA_%I64d", InpMagic); }
string LogName(void)    { return StringFormat("EA_%s_%I64d_%s.csv", Tf(), InpMagic, g_mode); }
int    Period_(void)    { return PeriodSeconds((ENUM_TIMEFRAMES)_Period); }

// Deterministic trade ID: candle time + the pair's place in the fixed order (one entry per pair per candle).
// Nothing keys on it after a restart (a "deal history only" rebuild gives R<ticket>; 6c carry-over).
string TradeId(const datetime t, const int k)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return StringFormat("T%02d%02d%02d%02d%02d_%d", s.year % 100, s.mon, s.day, s.hour, s.min, k);
  }

void Row(const string event, const string sym, const string note)
  {
   NNFXLogRow r;
   NNFXLogRowClear(r);
   r.event = event;
   r.symbol = sym;
   r.magic = InpMagic;
   r.note = note;
   g_log.Write(r);
  }

//--- state -----------------------------------------------------------
void SaveState(void)
  {
   if(g_orders == NULL || !g_ready)
      return;
   NNFXTrade trades[];
   g_orders.ExportTrades(trades);
   NNFXCont conts[];
   NNFXCoreRec cores[];
   int n = ArraySize(g_pairs);
   ArrayResize(cores, n);
   datetime proc = 0;
   for(int k = 0; k < n; k++)
     {
      cores[k].sym = g_pairs[k];
      cores[k].proc = g_proc[k];
      cores[k].snap = g_core[k].Snapshot();
      proc = (k == 0) ? g_proc[k] : MathMin(proc, g_proc[k]);
     }
   string text = NNFXStateText(Instance(), trades, conts, cores, proc);
   if(text == g_last_saved)
      return;
   if(NNFXStateSave(Instance(), text))
      g_last_saved = text;
   else
      Row("INFO", "", "STATE FILE NOT SAVED, error " + IntegerToString(GetLastError()));
  }

//--- broker side ------------------------------------------------------
// The open broker trade on this pair (first found), or "" (dir 0)
string BrokerTrade(const string sym, int &dir)
  {
   dir = 0;
   NNFXTrade t[];
   int n = g_orders.ExportTrades(t);
   for(int i = 0; i < n; i++)
      if(t[i].sym == sym)
        {
         dir = t[i].dir;
         return t[i].id;
        }
   return "";
  }

// The core's view after a candle: +1/-1 holding (or entering at the next open), 0 flat (or exiting at it)
int CoreDir(CNNFXPairCore &core)
  {
   if(core.PendingKind() == 2)
      return 0;
   if(core.PendingKind() == 1)
      return core.PendingDir();
   return core.PositionDir();
  }

//--- candle inputs ----------------------------------------------------
// Builds the core's input for the closed candle with open time t of pair k (block and news filled later).
bool BuildAt(const int k, const datetime t, NNFXBar &b, NNFXRaw &raw)
  {
   int shift = iBarShift(g_pairs[k], (ENUM_TIMEFRAMES)_Period, t, true);
   if(shift < 1)
     {
      raw.ok = false;
      raw.why = "no candle";
      b.t = (long)t;
      return false;
     }
   return g_bb[k].Build(shift, b, raw);
  }

// N1/N2 for pair k at the close tc; why = the reasons ("" = none)
string NewsBlock(const int k, const datetime tc)
  {
   if(!InpNewsBlock)
      return "";
   if(!g_news_ok)
      return "newsfile";
   string why;
   if(NNFXNewsBlocked(g_pairs[k], tc, g_news, g_broker, g_blackouts, why))
      return why;
   return "";
  }

void AddReason(string &block, const string why)
  {
   if(why == "")
      return;
   string w = why;
   StringReplace(w, ",", ";");
   block += (block == "" ? "" : ";") + w;
  }

// Feeds candle t to a core with a fixed block reason (warm-up, missed, replay). Returns false if not built.
bool FeedFixed(const int k, CNNFXPairCore &core, const datetime t, const string block, datetime &prevClose, NNFXBar &b,
               NNFXRaw &raw)
  {
   if(!BuildAt(k, t, b, raw))
      return false;
   datetime tc = t + Period_();
   b.block = block;
   string nb = NewsBlock(k, tc);
   if(block == "")
      b.block = nb;   // the replay: news only (it cannot know the other block inputs)
   b.news = g_news_ok && NNFXNewsFirstClose(g_pairs[k], tc, prevClose, g_news, g_broker);
   prevClose = tc;
   core.OnBar(b);
   return true;
  }

//--- guard --------------------------------------------------------------
// Account-wide parts of the guard, once per visit with a due pair: drawdown (with the owner's reset, D6d-3), daily
// loss (D6d-2/D6d-5), master switch. Returns the reasons ("," as NNFXGuardBlocks).
string GuardGlobal(void)
  {
   datetime t = TimeCurrent();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   NNFXDrawdownLoad(g_dd);
   string resetText;
   if(NNFXDrawdownResetRequested(g_dd, equity, resetText))
      Row("GUARD", "", resetText);
   bool was = g_dd.paused;
   NNFXDrawdownSample(g_dd, equity);
   NNFXDrawdownSave(g_dd);
   if(g_dd.paused && !was)
     {
      string why = StringFormat("drawdown pause (R-12): equity %.2f <= 90%% of the peak %.2f; reset by hand only (S-6)",
                                equity, g_dd.peak);
      Row("GUARD", "", why);
      NNFXNotify(why);
     }
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
      string why = StringFormat("daily loss limit (S-5, D6d-2): today's closed P/L %.2f <= %.2f since %s", pl, limit,
                                NNFXTime(start));
      Row("GUARD", "", why);
      NNFXNotify(why);
     }
   g_dl_was = dl;
   int master = NNFXMasterState();
   if(g_mode == "tester" && InpTesterMaster >= 0)
     {
      master = InpTesterMaster;
      if(g_masterOffFrom > 0 && t >= g_masterOffFrom && t < g_masterOffTo)
         master = 0;
     }
   string s = NNFXGuardBlocks(master, NNFXInstanceOn(_Symbol, InpMagic, InpInstanceOn), g_dd.paused, dl, false, false,
                              0, 0, true);
   if(s != g_global_was)
     {
      Row("GUARD", "", "blocks: " + (s == "" ? "none" : s) + " (was " + (g_global_was == "" ? "none" : g_global_was) + ")");
      g_global_was = s;
     }
   return s;
  }

// The per-pair parts at this moment: rollover, weekend, spread, indicator
string GuardPair(const int k, const bool indicatorOk)
  {
   datetime t = TimeCurrent();
   double spread = (double)SymbolInfoInteger(g_pairs[k], SYMBOL_SPREAD);
   return NNFXGuardBlocks(1, true, false, false, NNFXInRollover(g_broker, t), NNFXInWeekendBlock(g_broker, t, InpWeekendHours),
                          spread, InpMaxSpread, indicatorOk);
  }

// Which batch of candle time t this is: 1 for the first visit that processes t, 2 for pairs whose candle arrived
// later (each pair keeps its own clock, so a late pair never holds the others back), ... The decision log notes
// "batch N" for N > 1, so the fixed order can be checked within each batch.
datetime g_batch_t[4];
int      g_batch_n[4];

int BatchOf(const datetime t)
  {
   for(int i = 0; i < 4; i++)
      if(g_batch_t[i] == t)
         return ++g_batch_n[i];
   int old = 0;
   for(int i = 1; i < 4; i++)
      if(g_batch_t[i] < g_batch_t[old])
         old = i;
   g_batch_t[old] = t;
   g_batch_n[old] = 1;
   return 1;
  }

//--- one candle time, every due pair (DESIGN_6F sections 3 and 4) ------
void ProcessGroup(const datetime t, const int &ks[])
  {
   int n = ArraySize(ks);
   int batch = BatchOf(t);
   string batchNote = (batch > 1) ? StringFormat("batch %d; ", batch) : "";
   string global = GuardGlobal();
   NNFXBar bars[];
   NNFXRaw raws[];
   bool built[];
   string blocks[];
   ArrayResize(bars, n);
   ArrayResize(raws, n);
   ArrayResize(built, n);
   ArrayResize(blocks, n);
   NNFXPos signals[];
   int sigOf[];       // signal index per pair (-1 none)
   ArrayResize(sigOf, n);
   datetime tc = t + Period_();
   for(int j = 0; j < n; j++)
     {
      int k = ks[j];
      sigOf[j] = -1;
      built[j] = BuildAt(k, t, bars[j], raws[j]);
      if(!built[j])
         continue;
      // T4 trail of this pair's broker trades at this close (Orders.mqh, as 6b)
      g_orders.OnBarClose(g_pairs[k], bars[j].c, bars[j].atr);
      string block = "";
      AddReason(block, global);
      AddReason(block, GuardPair(k, true));
      AddReason(block, NewsBlock(k, tc));
      int bdir;
      if(BrokerTrade(g_pairs[k], bdir) != "" && CoreDir(g_core[k]) == 0)
         AddReason(block, "diverge");   // never a second trade on a pair the broker still holds (D6f-1, orphan)
      bars[j].block = block;
      bars[j].news = g_news_ok && NNFXNewsFirstClose(g_pairs[k], tc, g_prevClose[k], g_news, g_broker);
      // trial run: does the core enter here?
      if(block == "")
        {
         CNNFXPairCore trial;
         trial.Init(g_pairs[k], g_set);
         trial.Restore(g_core[k].Snapshot());
         trial.OnBar(bars[j]);
         NNFXEvent e;
         for(int i = 0; i < trial.EventCount(); i++)
            if(trial.GetEvent(i, e) && e.ev == "ENTER")
              {
               int m = ArraySize(signals);
               ArrayResize(signals, m + 1);
               signals[m].sym = g_pairs[k];
               signals[m].dir = e.dir;
               sigOf[j] = m;
              }
        }
     }
   // exposure across the basket (6a), every open position on the account (M6)
   double alloc[];
   ArrayResize(alloc, ArraySize(signals));
   if(ArraySize(signals) > 0)
     {
      NNFXPos open[];
      NNFXOpenPositions(open);
      string elog;
      if(!NNFXAllocate(open, signals, InpRiskPct, InpExposureMode, alloc, elog))
        {
         Row("INFO", "", "exposure refused every signal: " + elog);
         ArrayInitialize(alloc, 0.0);
        }
      else if(elog != "")
        {
         StringReplace(elog, "\n", " | ");
         Row("INFO", "", elog);
        }
     }
   // the real run, in the fixed order
   for(int j = 0; j < n; j++)
     {
      int k = ks[j];
      string sym = g_pairs[k];
      string action = "", note = "";
      if(!built[j])
        {
         // the core is never fed a candle with missing values; logged with ind_ok 0
         bars[j].block = "indicator";
         g_dlog.Write(sym, Tf(), bars[j], false, "", "-", batchNote + "not fed to the core: " + raws[j].why);
         g_proc[k] = t;
         g_prevClose[k] = tc;
         continue;
        }
      if(sigOf[j] >= 0 && alloc[sigOf[j]] <= 0.0)
         AddReason(bars[j].block, "exposure");
      g_core[k].ClearEvents();
      g_core[k].OnBar(bars[j]);
      NNFXEvent e;
      for(int i = 0; i < g_core[k].EventCount(); i++)
        {
         if(!g_core[k].GetEvent(i, e))
            continue;
         if(e.ev == "ENTER")
           {
            double risk = (sigOf[j] >= 0) ? alloc[sigOf[j]] : InpRiskPct;
            string id = TradeId(t, k);
            double cap = (g_set.runner_cap_atr > 0) ? g_set.runner_cap_atr : NNFX_CAP_OFF;
            if(g_orders.OpenTrade(sym, e.dir, bars[j].atr, risk, cap, id, false))
               action += (action == "" ? "" : "; ") + "OPEN " + id;
            else
               action += (action == "" ? "" : "; ") + "REFUSE " + id;
            if(risk < InpRiskPct)
               note += StringFormat("risk %.2f%% (exposure %s) ", risk, InpExposureMode);
           }
         else if(e.ev == "EXIT")
           {
            int bdir;
            string id = BrokerTrade(sym, bdir);
            if(id != "")
              {
               g_orders.CloseRemaining(id, e.rule + " exit (the rules core)");
               action += (action == "" ? "" : "; ") + "CLOSE " + id;
              }
            else
               note += "exit " + e.rule + ": no broker trade ";
           }
        }
      // D6f-1 after the actions
      g_orders.Poll("candle");
      int bdir;
      string bid = BrokerTrade(sym, bdir);
      int cdir = CoreDir(g_core[k]);
      if(bid == "")
         g_orphan[k] = false;
      if(cdir == 0 && bid != "" && !g_orphan[k])
        {
         string why = StringFormat("DIVERGE (D6f-1): the rules core is flat, the broker holds %s; closed", bid);
         g_orders.CloseRemaining(bid, "D6f-1: the rules core is flat");
         action += (action == "" ? "" : "; ") + "DIVERGE close " + bid;
         Row("DIVERGE", sym, why);
         NNFXNotify(sym + " " + why);
        }
      else if(cdir != 0 && bid == "")
        {
         action += (action == "" ? "" : "; ") + "DIVERGE wait";
         if(!g_waitAlarm[k])
           {
            string why = "DIVERGE (D6f-1): the rules core holds a trade, the broker none; no new entry until the core closes";
            Row("DIVERGE", sym, why);
            NNFXNotify(sym + " " + why);
            g_waitAlarm[k] = true;
           }
        }
      else
         g_waitAlarm[k] = false;
      if(g_orphan[k])
         note += "broker trade " + bid + " not known to the core: left to its stops [C] ";
      g_dlog.Write(sym, Tf(), bars[j], true, NNFXEventsText(g_core[k], 0), action == "" ? "-" : action, batchNote + note);
      g_proc[k] = t;
      g_prevClose[k] = tc;
     }
   g_orders.Reconcile();
   SaveState();
  }

//--- start and restart (DESIGN_6F section 5) -------------------------------
// Closed candles of pair k (open times), oldest first, from (after) `after` up to the last closed candle, at most max
int ClosedSince(const int k, const datetime after, const int max, datetime &times[])
  {
   ArrayResize(times, 0);
   datetime last = iTime(g_pairs[k], (ENUM_TIMEFRAMES)_Period, 1);
   if(last == 0)
      return 0;
   int first = (after > 0) ? iBarShift(g_pairs[k], (ENUM_TIMEFRAMES)_Period, after, false) - 1 : max;
   first = MathMin(first, max);
   for(int shift = first; shift >= 1; shift--)
     {
      datetime t = iTime(g_pairs[k], (ENUM_TIMEFRAMES)_Period, shift);
      if(t <= after || t == 0)
         continue;
      int n = ArraySize(times);
      ArrayResize(times, n + 1);
      times[n] = t;
     }
   return ArraySize(times);
  }

void GatherCandles(const int k, const datetime from, const datetime upto, NNFXCandleRec &recs[])
  {
   string sym = g_pairs[k];
   int first = iBarShift(sym, (ENUM_TIMEFRAMES)_Period, from, false);
   int last = iBarShift(sym, (ENUM_TIMEFRAMES)_Period, upto, false);
   for(int shift = first; shift >= MathMax(last, 1); shift--)
     {
      NNFXBar b;
      NNFXRaw r;
      if(!g_bb[k].Build(shift, b, r))
         continue;
      int n = ArraySize(recs);
      ArrayResize(recs, n + 1);
      recs[n].sym = sym;
      recs[n].time = (datetime)b.t;
      recs[n].close = b.c;
      recs[n].atr = b.atr;
      recs[n].side = (b.c > b.base) ? 1 : ((b.c < b.base) ? -1 : 0);
      recs[n].c1 = b.c1;
     }
  }

string DirText(const int d) { return d == 0 ? "flat" : (d == 1 ? "long" : "short"); }

// The broker map (6c) and each pair's core (saved memory, else a flat warm-up), then the cross-check.
void Start(const string why)
  {
   // state file
   string lines[];
   string status = "absent";
   NNFXTrade st[];
   NNFXCont sc[];
   NNFXCoreRec cores[];
   datetime proc = 0;
   string bad = "";
   if(NNFXStateReadLines(Instance(), lines))
      status = NNFXStateParse(lines, st, sc, cores, proc, bad);
   // broker side (6c, unchanged): positions, deals, candles back to the entries
   NNFXPosRec pos[];
   NNFXDealRec deals[];
   datetime from = (g_mode == "tester") ? 0 : TimeCurrent() - 30 * 86400;
   NNFXGatherBroker(InpMagic, from, pos, deals);
   datetime upto = (proc > 0) ? proc : iTime(_Symbol, (ENUM_TIMEFRAMES)_Period, 1);
   datetime minTime = upto;
   for(int i = 0; i < ArraySize(deals); i++)
      if(deals[i].entry == "IN")
         minTime = MathMin(minTime, deals[i].time);
   NNFXCandleRec candles[];
   for(int k = 0; k < ArraySize(g_pairs); k++)
      GatherCandles(k, minTime - 2 * Period_(), upto, candles);
   NNFXTrade out[];
   NNFXCont conts[];
   string notes;
   NNFXRebuildPure(pos, deals, status, st, candles, Period_(), InpMagic, upto, false, out, conts, notes);
   if(bad != "")
      NNFXAddNote(notes, "state file problem: " + bad);
   g_orders.ImportTrades(out);
   StringReplace(notes, "\n", " | ");
   Row("REBUILD", "", why + "; broker: " + IntegerToString(ArraySize(out)) + " open trade(s); notes=" + notes);

   // each pair's core
   for(int k = 0; k < ArraySize(g_pairs); k++)
     {
      string sym = g_pairs[k];
      g_core[k].Init(sym, g_set);
      g_orphan[k] = false;
      g_waitAlarm[k] = false;
      bool restored = false;
      datetime saved = 0;
      for(int c = 0; c < ArraySize(cores); c++)
         if(cores[c].sym == sym && status == "present")
           {
            saved = cores[c].proc;
            restored = saved > 0 && g_core[k].Restore(cores[c].snap);
            if(!restored)
               g_core[k].Init(sym, g_set);
           }
      datetime times[];
      string how = "";
      NNFXBar b;
      NNFXRaw raw;
      if(restored)
        {
         ClosedSince(k, saved, InpWarmupBars + 1, times);
         if(ArraySize(times) > InpWarmupBars)
           {
            restored = false;
            g_core[k].Init(sym, g_set);
            how = "saved memory too old (more than InpWarmupBars candles missed)";
           }
        }
      if(restored)
        {
         // the candles missed while stopped, including the one waiting now: fed, logged, never acted on (OD-7 (b))
         g_prevClose[k] = saved + Period_();
         for(int i = 0; i < ArraySize(times); i++)
           {
            g_core[k].ClearEvents();
            bool ok = FeedFixed(k, g_core[k], times[i], EA_MISSED, g_prevClose[k], b, raw);
            if(!ok)
               b.block = "indicator";
            g_dlog.Write(sym, Tf(), b, ok, ok ? NNFXEventsText(g_core[k], 0) : "", "-",
                         ok ? "missed while stopped (OD-7 (b))" : "missed while stopped; not fed: " + raw.why);
            g_prevClose[k] = times[i] + Period_();
           }
         g_proc[k] = (ArraySize(times) > 0) ? times[ArraySize(times) - 1] : saved;
         how = StringFormat("restored from the state file (saved at %s), %d missed candle(s) fed", NNFXTime(saved),
                            ArraySize(times));
        }
      else
        {
         // no saved memory: a flat warm-up (no entry can be simulated), not logged
         ClosedSince(k, 0, InpWarmupBars, times);
         datetime pc = 0;
         for(int i = 0; i < ArraySize(times); i++)
           {
            g_core[k].ClearEvents();
            FeedFixed(k, g_core[k], times[i], EA_START, pc, b, raw);
           }
         g_proc[k] = (ArraySize(times) > 0) ? times[ArraySize(times) - 1] : iTime(sym, (ENUM_TIMEFRAMES)_Period, 1);
         g_prevClose[k] = g_proc[k] + Period_();
         if(how == "")
            how = "no saved memory (state file " + status + "): flat warm-up of " + IntegerToString(ArraySize(times)) + " candles";
        }
      g_core[k].ClearEvents();

      // cross-check: a replay with no blocks but news, in a separate copy; information only
      CNNFXPairCore replay;
      replay.Init(sym, g_set);
      ClosedSince(k, 0, InpWarmupBars, times);
      datetime pc = 0;
      for(int i = 0; i < ArraySize(times); i++)
        {
         replay.ClearEvents();
         if(times[i] <= g_proc[k])
            FeedFixed(k, replay, times[i], "", pc, b, raw);
        }
      int rdir = CoreDir(replay);
      int cdir = CoreDir(g_core[k]);
      int bdir;
      string bid = BrokerTrade(sym, bdir);
      string text = StringFormat("start (%s): %s; core %s, broker %s%s, replay with no blocks %s", why, how, DirText(cdir),
                                 DirText(bdir), bid == "" ? "" : " (" + bid + ")", DirText(rdir));
      if(cdir == 0 && bid != "" && !restored)
        {
         g_orphan[k] = true;
         text += "; the broker trade is left to its stops and the pair takes no new entry while it is open [C]";
        }
      if((cdir == 0) != (bid == "") || (cdir != 0 && bid != "" && cdir != bdir))
        {
         // a start-up disagreement: an alarm, never a close (D6f-1 applies from the first live candle)
         Row("DIVERGE", sym, text + "; START-UP: alarm only, nothing closed (DESIGN_6F section 5)");
         NNFXNotify(sym + " start-up DIVERGE: core " + DirText(cdir) + ", broker " + DirText(bdir) + "; nothing closed");
        }
      else
         Row("INFO", sym, text + (rdir != cdir ? "; the replay differs: information only" : "; the replay agrees"));
     }
   g_last_saved = "";
   g_ready = true;
   SaveState();
  }

// Live clock and Algo Trading checks after login (6c carry-overs; D6d-4: never TimeLocal)
void LiveChecks(void)
  {
   int live = (int)MathRound((double)(TimeTradeServer() - TimeGMT()) / 3600.0);
   int rule = NNFXServerOffset(g_broker, TimeGMT()) / 3600;
   string t = StringFormat("server clock: live offset %+d h, the setting's rule gives %+d h (winter %+d, DST %s)", live, rule,
                           InpServerWinterOffset, InpServerDst);
   Row("INFO", "", t + (live == rule ? "" : " MISMATCH: the trading day boundary and news times would be wrong"));
   if(live != rule)
      NNFXNotify(t + " MISMATCH");
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      Row("INFO", "", "ALGO TRADING IS OFF (terminal or EA): orders will be refused by MT5");
      NNFXNotify("Algo Trading is off: no orders can be sent");
     }
   NewsCheckAge();
  }

void NewsLoad(void)
  {
   datetime gen;
   int n = NNFXNewsLoad(InpNewsFile, true, g_broker, g_news, gen);
   g_news_ok = (n >= 0);
   g_news_loaded = TimeCurrent();
   Row("INFO", "", g_news_ok ? StringFormat("news file %s: %d events, generated %s GMT", InpNewsFile, n, NNFXTime(gen))
                             : "NEWS FILE NOT READ: " + InpNewsFile + " (entries blocked with \"newsfile\")");
  }

// Live only: the file's age (OD-12) and whether it reaches the next 24 hours (recency, G1_phase6e_1 F2)
void NewsCheckAge(void)
  {
   if(g_mode == "tester" || !InpNewsBlock)
      return;
   datetime gen = 0;
   NNFXNewsEvent ev[];
   NNFXNewsLoad(InpNewsFile, true, g_broker, ev, gen);
   double age = NNFXNewsAgeHours(gen);
   datetime lastEv = (ArraySize(ev) > 0) ? ev[ArraySize(ev) - 1].time : 0;
   if(age < 0 || age > InpNewsMaxAgeHours)
      NNFXNotify(StringFormat("news file %s is %.1f h old (more than %.0f h, OD-12)", InpNewsFile, age, InpNewsMaxAgeHours));
   if(lastEv < TimeCurrent() + 24 * 3600)
      NNFXNotify("news file " + InpNewsFile + " has no event after " + NNFXTime(lastEv) + ": it may not cover the next 24 h");
  }

//--- the visit: every tick and every second --------------------------------
void Visit(void)
  {
   if(!g_ready)
      return;
   g_orders.EnforceStops();
   g_orders.Poll("tick");
   // due pairs, grouped by candle time, in the fixed order
   int n = ArraySize(g_pairs);
   datetime due[];
   ArrayResize(due, n);
   datetime first = 0;
   for(int k = 0; k < n; k++)
     {
      due[k] = 0;
      datetime last = iTime(g_pairs[k], (ENUM_TIMEFRAMES)_Period, 1);
      if(last == 0 || last <= g_proc[k])
         continue;
      datetime times[];
      ClosedSince(k, g_proc[k], InpWarmupBars, times);
      int nt = ArraySize(times);
      if(nt == 0)
         continue;
      // behind by more than one candle (only after a stall): the older ones are fed and logged, never acted on,
      // as at a restart (OD-7 (b)); only the newest closed candle is processed live
      for(int i = 0; i < nt - 1; i++)
        {
         NNFXBar b;
         NNFXRaw raw;
         g_core[k].ClearEvents();
         bool ok = FeedFixed(k, g_core[k], times[i], EA_MISSED, g_prevClose[k], b, raw);
         if(!ok)
            b.block = "indicator";
         g_dlog.Write(g_pairs[k], Tf(), b, ok, ok ? NNFXEventsText(g_core[k], 0) : "", "-",
                      ok ? "missed (stall; OD-7 (b))" : "missed (stall); not fed: " + raw.why);
         g_proc[k] = times[i];
         g_prevClose[k] = times[i] + Period_();
        }
      due[k] = times[nt - 1];
      first = (first == 0) ? due[k] : MathMin(first, due[k]);
     }
   if(first == 0)
      return;   // trade events save the state in OnTradeTransaction
   // a simulated restart (tester): everything in memory is thrown away and rebuilt before this candle
   if(InpRestartAt != "none" && !g_restart_done && first >= StringToTime(InpRestartAt))
     {
      g_restart_done = true;
      SimulatedRestart();
      return;
     }
   int ks[];
   for(int k = 0; k < n; k++)
      if(due[k] == first)
        {
         int m = ArraySize(ks);
         ArrayResize(ks, m + 1);
         ks[m] = k;
        }
   ProcessGroup(first, ks);
   if(g_mode != "tester" && TimeCurrent() - g_news_loaded >= 3600)
     {
      NewsLoad();
      NewsCheckAge();
     }
  }

void SimulatedRestart(void)
  {
   SaveState();
   Row("PRESTOP", "", "simulated restart (tester, InpRestartAt " + InpRestartAt + ")");
   if(InpRestartDeleteState)
      FileDelete(NNFXStatePath(Instance()));
   delete g_orders;
   g_orders = new CNNFXOrders();
   g_orders.Init(InpMagic, GetPointer(g_log), g_set.sl_atr, g_set.tp1_atr, g_set.trail_start_atr, g_set.trail_dist_atr);
   for(int k = 0; k < ArraySize(g_pairs); k++)
     {
      delete g_core[k];
      g_core[k] = new CNNFXPairCore();
      g_proc[k] = 0;
     }
   g_ready = false;
   Start("simulated restart");
  }

//--- events ----------------------------------------------------------------
int OnInit()
  {
   g_mode = (MQLInfoInteger(MQL_TESTER) != 0) ? "tester" : "demo";
   g_broker.name = AccountInfoString(ACCOUNT_SERVER);
   g_broker.winter_offset = InpServerWinterOffset;
   g_broker.dst = InpServerDst;
   if(InpServerDst != "none" && InpServerDst != "EU" && InpServerDst != "US")
     {
      Print("NNFX_EA: InpServerDst must be none, EU or US");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_mode != "tester" && InpTesterMaster != -1)
     {
      Print("NNFX_EA: InpTesterMaster is for the Strategy Tester only (live: the NNFX_MASTER global variable)");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_mode != "tester" && (InpTesterMasterOff != "none" || InpRestartAt != "none"))
     {
      Print("NNFX_EA: InpTesterMasterOff and InpRestartAt are for the Strategy Tester only");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTesterMasterOff != "none")
     {
      string w[];
      if(StringSplit(InpTesterMasterOff, ';', w) != 2)
        {
         Print("NNFX_EA: InpTesterMasterOff must be \"from;to\"");
         return INIT_PARAMETERS_INCORRECT;
        }
      g_masterOffFrom = StringToTime(w[0]);
      g_masterOffTo = StringToTime(w[1]);
     }
   g_set.Defaults();
   g_set.risk_pct = InpRiskPct;
   g_set.trail_on = InpTrailOn;
   g_set.trail_start_atr = InpTrailStart;
   g_set.trail_dist_atr = InpTrailDist;
   g_set.runner_cap_atr = InpRunnerCap;
   g_set.exit_on_exit_ind = InpExitOnExitInd;
   g_set.exit_on_c1 = InpExitOnC1;
   g_set.exit_on_baseline = InpExitOnBaseline;
   g_set.news_exit = InpNewsExit;
   g_set.pullback_on = InpPullback;
   g_set.one_candle = InpOneCandle;
   g_set.btf_on = InpBridgeTooFar;
   g_set.btf_bars = InpBridgeBars;
   g_set.continuation = InpContinuation;
   string err;
   if(!g_set.Validate(err) || (InpExposureMode != "first" && InpExposureMode != "split"))
     {
      Print("NNFX_EA: settings: ", err == "" ? "InpExposureMode must be first or split" : err);
      return INIT_PARAMETERS_INCORRECT;
     }
   string bo = (InpBlackouts == "none") ? "" : InpBlackouts;
   if(NNFXParseBlackouts(bo, g_blackouts) < 0)
     {
      Print("NNFX_EA: InpBlackouts is malformed");
      return INIT_PARAMETERS_INCORRECT;
     }
   // pairs, fixed order
   string p[];
   int n = StringSplit(InpPairs, ',', p);
   for(int i = 0; i < n; i++)
     {
      string s = p[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "")
         continue;
      if(!NNFXIsFx(s) || !SymbolSelect(s, true))
        {
         Print("NNFX_EA: pair ", s, " is not one of the 28 or not available");
         return INIT_PARAMETERS_INCORRECT;
        }
      int m = ArraySize(g_pairs);
      ArrayResize(g_pairs, m + 1);
      g_pairs[m] = s;
     }
   n = ArraySize(g_pairs);
   if(n == 0)
     {
      Print("NNFX_EA: no pairs");
      return INIT_PARAMETERS_INCORRECT;
     }
   // logs: a new file each tester run; live, the same file continued across restarts
   bool append = (g_mode != "tester");
   if(g_mode == "tester")
      FileDelete(NNFXStatePath(Instance()));
   if(!g_log.Open(LogName(), append) || !g_dlog.Open(LogName(), append))
      return INIT_FAILED;
   g_orders = new CNNFXOrders();
   if(!g_orders.Init(InpMagic, GetPointer(g_log), g_set.sl_atr, g_set.tp1_atr, g_set.trail_start_atr, g_set.trail_dist_atr))
      return INIT_FAILED;   // section 1: not the tester and not a DEMO account
   Row("INFO", "", StringFormat("NNFX_EA %s, magic %I64d, pairs %s, risk %.2f%%, exposure %s, terminal build %d, account %I64d on %s",
                                Tf(), InpMagic, InpPairs, InpRiskPct, InpExposureMode,
                                (int)TerminalInfoInteger(TERMINAL_BUILD), AccountInfoInteger(ACCOUNT_LOGIN),
                                AccountInfoString(ACCOUNT_SERVER)));
   ArrayResize(g_bb, n);
   ArrayResize(g_core, n);
   ArrayResize(g_proc, n);
   ArrayResize(g_prevClose, n);
   ArrayResize(g_orphan, n);
   ArrayResize(g_waitAlarm, n);
   string profiles[5];
   profiles[0] = InpBaseline;
   profiles[1] = InpC1;
   profiles[2] = InpC2;
   profiles[3] = InpExit;
   profiles[4] = InpVolume;
   for(int k = 0; k < n; k++)
     {
      g_bb[k] = new CNNFXBarBuilder();
      g_core[k] = new CNNFXPairCore();
      g_proc[k] = 0;
      g_prevClose[k] = 0;
      g_orphan[k] = false;
      g_waitAlarm[k] = false;
      if(!g_bb[k].Init(g_pairs[k], (ENUM_TIMEFRAMES)_Period, profiles, true))
        {
         Print("NNFX_EA: ", g_pairs[k], ": ", g_bb[k].Error());
         return INIT_FAILED;
        }
     }
   NewsLoad();
   if(InpNewsBlock && !g_news_ok && g_mode == "tester")
      return INIT_FAILED;   // a tester run without its event file would test a different rule set
   if(g_mode != "tester")
     {
      g_panel.Init(0, _Symbol, InpMagic, InpInstanceOn);
      g_panel_on = true;
     }
   // Nothing trades before the start-up: connected, logged in, every pair has a tick value, indicators calculated,
   // +3 s (6c carry-over; OnInit can run before MT5 has synchronized its positions). Live, a 1 s timer also visits
   // the pairs between the chart symbol's ticks; the tester visits on the chart symbol's ticks only (1 minute OHLC
   // gives one at least every minute; a 1 s timer would add millions of empty events to a 3-month run).
   if(g_mode != "tester")
      EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

string g_not_ready = "";

bool ReadyToStart(void)
  {
   g_not_ready = "";
   if(g_mode != "tester")
     {
      if(!TerminalInfoInteger(TERMINAL_CONNECTED) || AccountInfoInteger(ACCOUNT_LOGIN) == 0)
        {
         g_not_ready = "not connected / logged in";
         return false;
        }
      for(int k = 0; k < ArraySize(g_pairs); k++)
         if(!(SymbolInfoDouble(g_pairs[k], SYMBOL_TRADE_TICK_VALUE) > 0.0))
           {
            g_not_ready = g_pairs[k] + ": no tick value";
            return false;
           }
     }
   for(int k = 0; k < ArraySize(g_pairs); k++)
     {
      if(iTime(g_pairs[k], (ENUM_TIMEFRAMES)_Period, 1) == 0)
        {
         g_not_ready = g_pairs[k] + ": no closed candle";
         return false;
        }
      // every indicator value present on the last closed candle (AllCalculated, used by the scripts, never becomes
      // true in the Strategy Tester: run ea_dbg_start_20261006, "EURUSD: indicators not calculated" for 2 days)
      NNFXBar b;
      NNFXRaw raw;
      if(!g_bb[k].Build(1, b, raw))
        {
         g_not_ready = g_pairs[k] + ": last closed candle not built (" + raw.why + ")";
         return false;
        }
     }
   return true;
  }

void TryStart(void)
  {
   if(g_ready)
      return;
   if(!ReadyToStart())
     {
      static datetime said = 0;
      if(TimeCurrent() - said >= 60)
        {
         Print("NNFX_EA: waiting to start: ", g_not_ready);
         said = TimeCurrent();
        }
      g_ready_since = 0;
      return;
     }
   if(g_ready_since == 0)
     {
      g_ready_since = GetTickCount();
      if(g_mode != "tester")
         return;
     }
   if(g_mode != "tester" && GetTickCount() - g_ready_since < 3000)
      return;
   if(g_mode != "tester")
      LiveChecks();
   Start(g_mode == "tester" ? "tester start" : "start");
  }

void OnTimer()
  {
   TryStart();
   Visit();
  }

void OnTick()
  {
   TryStart();
   Visit();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(!g_ready)
      return;
   g_orders.Poll("transaction");
   SaveState();   // after every trade event (G1_phase6c_2 note 1)
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(!g_panel_on || !g_ready)
      return;
   int a = g_panel.OnEvent(id, lparam, dparam, sparam);
   if(a == NNFX_PANEL_INSTANCE)
      Row("GUARD", "", "instance switch " + (NNFXInstanceOn(_Symbol, InpMagic, InpInstanceOn) ? "ON" : "OFF") + " by the chart button");
   else if(a == NNFX_PANEL_DDRESET)
      Row("GUARD", "", "drawdown reset requested by the chart button (confirmed): NNFX_DD_RESET = 1, applied at the next candle");
   else if(a == NNFX_PANEL_CLOSEALL)
     {
      NNFXTrade t[];
      int n = g_orders.ExportTrades(t);
      Row("GUARD", "", StringFormat("close-all by the chart button (confirmed): %d trade(s) of this instance", n));
      for(int i = 0; i < n; i++)
         g_orders.CloseRemaining(t[i].id, "close-all button (confirmed)");
      SaveState();
     }
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_panel_on)
      g_panel.Remove();
   if(g_orders != NULL)
     {
      SaveState();
      Row("PRESTOP", "", StringFormat("deinit reason %d; %s", reason, g_ready ? "state saved" : "stopped before the start-up ran (" + g_not_ready + ")"));
      delete g_orders;
      g_orders = NULL;
     }
   for(int k = 0; k < ArraySize(g_bb); k++)
     {
      if(CheckPointer(g_bb[k]) == POINTER_DYNAMIC)
         delete g_bb[k];
      if(CheckPointer(g_core[k]) == POINTER_DYNAMIC)
         delete g_core[k];
     }
   g_dlog.Close();
   g_log.Close();
  }
//+------------------------------------------------------------------+
