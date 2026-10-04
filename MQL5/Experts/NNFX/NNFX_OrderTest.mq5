//+------------------------------------------------------------------+
//| NNFX_OrderTest.mq5 - TEST EA for Phase 6b orders                 |
//| (docs/PLAN_PHASE6.md section 3). NOT the trading EA: it has no   |
//| indicator logic. It opens trades on a fixed schedule so every    |
//| order path runs, and logs every order event for                  |
//| tools/check_trades.py.                                           |
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
//|                                                                  |
//| Orders only in the tester or on a DEMO account (section 1).      |
//| Log: Common\Files\NNFX\trades\OrderTest_<symbol>_<tester|demo>.csv|
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| tester run 20261004_162607, 154 trades; demo pending).           |
//+------------------------------------------------------------------+
#property strict

// The ONLY file allowed to define this (tests/python/test_order_calls.py, S2b).
#define NNFX_TEST_BUILD
#include <NNFX\Orders.mqh>

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

CNNFXOrders   g_orders;
CNNFXTradeLog g_log;
int           g_atr = INVALID_HANDLE;
datetime      g_last_bar = 0;
int           g_bars_flat = 0;
int           g_trade_no = 0;
string        g_current = "";
int           g_exit_after = 0;    // candles after entry for a signal exit (0 = none)
int           g_bars_in_trade = 0;
bool          g_stopless_done = false;
string        g_mode = "";

string TradeId(const int k)
  {
   return StringFormat("T%04d", k);
  }

int OnInit()
  {
   g_mode = (MQLInfoInteger(MQL_TESTER) != 0) ? "tester" : "demo";
   g_log.Open("OrderTest_" + _Symbol + "_" + g_mode + ".csv");
   if(!g_orders.Init(InpMagic, GetPointer(g_log), 1.5, 1.0, 2.0, 1.5))
      return INIT_FAILED;
   g_atr = iATR(_Symbol, _Period, 14);
   if(g_atr == INVALID_HANDLE)
      return INIT_FAILED;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   int h = FileOpen("NNFX\\trades\\OrderTest_" + _Symbol + "_" + g_mode + "_summary.txt",
                    FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h != INVALID_HANDLE)
     {
      FileWriteString(h, StringFormat("NNFX_OrderTest %s %s, build %d, magic %I64d, deinit reason %d\r\n", _Symbol, g_mode,
                                      (int)TerminalInfoInteger(TERMINAL_BUILD), InpMagic, reason));
      FileWriteString(h, "log: Common\\Files\\" + g_log.Path() + "\r\n");
      FileWriteString(h, StringFormat("RESULT: run complete, %d trades opened\r\n", g_orders.TradeCount()));
      FileClose(h);
     }
   g_log.Close();
   if(g_atr != INVALID_HANDLE)
      IndicatorRelease(g_atr);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   g_orders.Poll("transaction");
  }

void OnTick()
  {
   g_orders.EnforceStops();
   g_orders.Poll("tick");
   datetime bar = iTime(_Symbol, _Period, 0);
   if(bar == g_last_bar)
      return;
   bool first = (g_last_bar == 0);
   g_last_bar = bar;
   if(first)
      return;   // decisions only from the second candle on, with a full closed candle behind

   double atr[1];
   if(CopyBuffer(g_atr, 0, 1, 1, atr) != 1 || !(atr[0] > 0))
      return;
   double close = iClose(_Symbol, _Period, 1);

   if(InpStoplessTest && !g_stopless_done && g_mode == "tester")
     {
      g_stopless_done = true;
      if(g_orders.NNFXTestOpenWithoutStop(_Symbol, 1, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), "TS01"))
         g_orders.EnforceStops();
     }

   g_orders.OnBarClose(_Symbol, close, atr[0]);

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
   if(g_orders.OpenTrade(_Symbol, dir, atr[0], InpRiskPct, cap, id, InpMinLots))
     {
      g_current = id;
      g_bars_in_trade = 0;
     }
   g_bars_flat = 0;
  }
//+------------------------------------------------------------------+
