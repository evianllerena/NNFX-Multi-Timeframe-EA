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
//|                                                                  |
//| Places NO orders.                                                |
//| Status: not yet compiled.                                        |
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
