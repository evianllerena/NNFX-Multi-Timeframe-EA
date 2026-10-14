//+------------------------------------------------------------------+
//| OrderMath.mqh - order prices and the order safety decision       |
//|                                                                  |
//| Port of tests/python/nnfx_ref/orders.py (docs/PLAN_PHASE6.md     |
//| sections 1 and 3). Pure functions: no trading calls, so the same |
//| numbers can be checked against the Python answer key.            |
//|                                                                  |
//|  stop   fill - dir x sl_atr x ATR, rounded TOWARDS the fill, so  |
//|         the stop is never wider than the one the lots were sized |
//|         for (F4: planned risk never above target)                |
//|  TP1    fill + dir x tp1_atr x ATR, nearest tick (T1)            |
//|  TP2    fill + dir x cap x ATR if the runner cap is on (T7)      |
//|  BE     exactly the half's entry (T2, OD-15)                     |
//|  trail  after TP1: on once a close is start x ENTRY ATR beyond   |
//|         entry; close - dir x dist x current ATR, nearest tick,   |
//|         never backwards (T4, I-11)                               |
//|  safety orders only in the tester or on a DEMO account (OD-18)   |
//|         and only on a HEDGING account, tester included (A7)      |
//|  retry  only refusals that can clear by themselves (B3, OD-13)   |
//|                                                                  |
//| Places NO orders.                                                |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| OrderMathTest 22/22, SafetyTest 6/6, run 20261004_162607).       |
//| NNFXHedgingOk / NNFXRetcodeRetryable (review fixes A7, B3,       |
//| 2026-10-14): not yet compiled.                                   |
//+------------------------------------------------------------------+
#ifndef NNFX_ORDERMATH_MQH
#define NNFX_ORDERMATH_MQH

#define NNFX_OM_EPS 1e-9
// Runner cap off (T7, decision R-11). A cap of 0 is not "off": it is rejected, as in orders.py.
#define NNFX_CAP_OFF -1.0

// Section 1 SAFETY, the pure decision: true only in the Strategy Tester or on a DEMO account.
// CONTEST and REAL are refused outside the tester (decision OD-18).
bool NNFXOrdersAllowedFor(const long tradeMode, const bool inTester)
  {
   if(inTester)
      return true;
   return tradeMode == ACCOUNT_TRADE_MODE_DEMO;
  }

// A7 (review 2026-10-14): two positions per trade on one symbol is the design (S-10). On a netting or
// exchange account the second half would merge into the first, so orders need a HEDGING account.
// Same as orders.py hedging_ok(); checked against the MM lines of order_cases.txt by NNFX_SafetyTest.
bool NNFXHedgingOk(const long marginMode)
  {
   return marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
  }

// B3 (review 2026-10-14): false for refusals a retry 1 s later cannot clear (OD-13 retries the rest).
// Same list as orders.py NOT_RETRYABLE; checked against the RC lines of order_cases.txt by NNFX_SafetyTest.
bool NNFXRetcodeRetryable(const uint retcode)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_INVALID:
      case TRADE_RETCODE_INVALID_VOLUME:
      case TRADE_RETCODE_INVALID_STOPS:
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_NO_MONEY:
      case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_SERVER_DISABLES_AT:
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
      case TRADE_RETCODE_ONLY_REAL:
      case TRADE_RETCODE_LIMIT_ORDERS:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case TRADE_RETCODE_LIMIT_POSITIONS:
      case TRADE_RETCODE_INVALID_ORDER:
      case TRADE_RETCODE_POSITION_CLOSED:
      case TRADE_RETCODE_HEDGE_PROHIBITED:
      case TRADE_RETCODE_FIFO_CLOSE:
      case TRADE_RETCODE_INVALID_EXPIRATION:
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME:
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
      case TRADE_RETCODE_LONG_ONLY:
      case TRADE_RETCODE_SHORT_ONLY:
      case TRADE_RETCODE_CLOSE_ONLY:
         return false;
     }
   return true;
  }

// A5 (review fixes set 3): what a sent order's state means for the sender. 1 = filled (a position exists, possibly a
// partial fill: OD-14 accepts any fill), -1 = it will never fill (cancelled, rejected, expired: a re-send is safe),
// 0 = not resolved yet (started, placed, being changed): never re-send while 0, or a slow fill doubles the half.
// Same as orders.py order_state_outcome(); checked against the OS lines of order_cases.txt by NNFX_OrderMathTest.
int NNFXOrderStateOutcome(const long state)
  {
   switch((int)state)
     {
      case ORDER_STATE_FILLED:
      case ORDER_STATE_PARTIAL:
         return 1;
      case ORDER_STATE_CANCELED:
      case ORDER_STATE_REJECTED:
      case ORDER_STATE_EXPIRED:
         return -1;
     }
   return 0;
  }

// OD-5 with the owner's buffer (OWN-2 (d), 2026-10-14): the margin of both halves plus 5% must be free. Half 1's
// spread cost lowers the free margin before half 2 is sent; without the buffer half 2 could be refused "No money" near
// full use (H1 run ea_explore2_M30_H1_20261014_172116, T1903151800_1). Same as orders.py margin_ok(); MB lines.
#define NNFX_MARGIN_BUFFER 0.05
bool NNFXMarginOk(const double marginBothHalves, const double freeMargin)
  {
   return marginBothHalves * (1.0 + NNFX_MARGIN_BUFFER) <= freeMargin + 1e-9;
  }

double NNFXRoundNearest(const double price, const double tick)
  {
   return NormalizeDouble(MathFloor(price / tick + 0.5 + NNFX_OM_EPS) * tick, 10);
  }

// A stop rounded towards the fill: up for a long (stop below), down for a short.
double NNFXRoundStop(const int dir, const double price, const double tick)
  {
   if(dir == 1)
      return NormalizeDouble(MathCeil(price / tick - NNFX_OM_EPS) * tick, 10);
   return NormalizeDouble(MathFloor(price / tick + NNFX_OM_EPS) * tick, 10);
  }

// SL, TP1 and TP2 (0 = none) for a trade filled at `fill`. capAtr = NNFX_CAP_OFF (< 0): runner cap off.
// False if an input is not usable (a cap of exactly 0 included).
bool NNFXPlanPrices(const int dir, const double fill, const double atr, const double tick,
                    const double slAtr, const double tp1Atr, const double capAtr,
                    double &sl, double &tp1, double &tp2)
  {
   sl = 0.0;
   tp1 = 0.0;
   tp2 = 0.0;
   if(dir != 1 && dir != -1)
      return false;
   if(!(fill > 0) || !(atr > 0) || !(tick > 0) || !(slAtr > 0) || !(tp1Atr > 0))
      return false;
   if(capAtr == 0.0)
      return false;
   sl = NNFXRoundStop(dir, fill - dir * slAtr * atr, tick);
   tp1 = NNFXRoundNearest(fill + dir * tp1Atr * atr, tick);
   if(capAtr > 0.0)
      tp2 = NNFXRoundNearest(fill + dir * capAtr * atr, tick);
   return true;
  }

// T2 / OD-15: exactly the entry price.
double NNFXBreakevenPrice(const double entry)
  {
   return entry;
  }

// A1 (review fixes set 2): after TP1, what half 2's stop at the broker needs. 0 = nothing (at breakeven or better),
// 1 = move it to breakeven, 2 = close half 2 at market: the price is already at or beyond breakeven against the trade,
// so a breakeven stop would be hit at once and the broker refuses it (label C, decision RV-A1).
// Same as orders.py be_action(); checked against the BA lines of order_cases.txt by NNFX_OrderMathTest.
int NNFXBeAction(const int dir, const double entry2, const double brokerSl, const double bid, const double ask,
                 const double tick)
  {
   double be = NNFXBreakevenPrice(entry2);
   if((be - brokerSl) * dir <= tick * 0.5)
      return 0;
   double exitPrice = (dir > 0) ? bid : ask;   // the price half 2 would close at
   if((exitPrice - be) * dir <= 0.0)
      return 2;
   return 1;
  }

// A1/A8 (review fixes set 2): when a failed breakeven move or close is tried again. Every 5 s for the first 5
// failures, then every 60 s, without end (the position stays protected by its own stop meanwhile).
// Same as orders.py pending_due(); checked against the PD lines of order_cases.txt by NNFX_OrderMathTest.
#define NNFX_PENDING_FAST_S 5
#define NNFX_PENDING_SLOW_S 60
#define NNFX_PENDING_FAST_N 5
bool NNFXPendingDue(const int fails, const long secondsSinceLast)
  {
   if(fails <= 0)
      return true;
   return secondsSinceLast >= (fails < NNFX_PENDING_FAST_N ? NNFX_PENDING_FAST_S : NNFX_PENDING_SLOW_S);
  }

// One candle close of the T4 trail on half 2 (called only after TP1). Returns true if the stop moved.
bool NNFXTrailStep(const int dir, const double entry, const double atrEntry, const double currentSl,
                   bool &active, const double close, const double atr, const double tick,
                   const double startAtr, const double distAtr, double &newSl)
  {
   newSl = currentSl;
   if(!active && (close - entry) * dir >= startAtr * atrEntry - 1e-12)
      active = true;
   if(!active)
      return false;
   double candidate = NNFXRoundNearest(close - dir * distAtr * atr, tick);
   if((candidate - currentSl) * dir > NNFX_OM_EPS * tick)
     {
      newSl = candidate;
      return true;
     }
   return false;
  }

// SPEC: a stop closer than the broker's minimum stop distance is not sent.
bool NNFXStopDistanceOk(const double price, const double sl, const long stopsLevelPoints, const double point)
  {
   return MathAbs(price - sl) + NNFX_OM_EPS * point >= stopsLevelPoints * point;
  }

// Money lost if this position's stop is hit exactly: lots x stop distance in ticks x tick value.
double NNFXPlannedRisk(const double lots, const double entry, const double sl, const double tickSize,
                       const double tickValue)
  {
   return lots * (MathAbs(entry - sl) / tickSize) * tickValue;
  }

#endif
