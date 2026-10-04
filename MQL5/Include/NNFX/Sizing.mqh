//+------------------------------------------------------------------+
//| Sizing.mqh - lot size from risk and stop distance                |
//|                                                                  |
//| Port of tests/python/nnfx_ref/sizing.py (rulebook M2-M5; SPEC    |
//| "Money, sizing and exposure"; decisions S-3, OD-6).              |
//|                                                                  |
//| Risk is a percentage of balance, split into two equal halves,    |
//| each rounded DOWN to the broker's lot step. A half below the     |
//| minimum lot skips the trade ("too small to size"). Risk is never |
//| rounded up.                                                      |
//|                                                                  |
//| Places NO orders.                                                |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| NNFX_SizingTest 42/42, run 20261004_125319).                       |
//+------------------------------------------------------------------+
#ifndef NNFX_SIZING_MQH
#define NNFX_SIZING_MQH

#define NNFX_SIZE_EPS 1e-9

struct NNFXSize
  {
   double            half_lots;
   double            total_lots;
   double            risk_money;         // money actually at risk with the rounded lots
   double            target_risk_money;  // money the risk percentage allows
   bool              skipped;
   string            reason;
  };

// Decision OD-6: the larger of the broker's tick value and its tick value for a losing
// trade, so lots can only come out smaller. 0 if neither is > 0 (the caller refuses).
double NNFXTickValueForSizing(const double tickValue, const double tickValueLoss)
  {
   double best = MathMax(tickValue, tickValueLoss);
   return (best > 0.0) ? best : 0.0;
  }

// stopDist is in price units (e.g. 0.0030 for 30 pips on EURUSD); tickValue is the
// account-currency value of one tick for one lot; volMax <= 0 means no maximum.
// Returns false (and out.reason) if an input is not usable; true otherwise, with
// out.skipped set when a half is below the minimum lot.
bool NNFXSizeTrade(const double balance, const double riskPct, const double stopDist,
                   const double tickSize, const double tickValue, const double volMin,
                   const double volStep, const double volMax, NNFXSize &out)
  {
   out.half_lots = 0.0;
   out.total_lots = 0.0;
   out.risk_money = 0.0;
   out.target_risk_money = 0.0;
   out.skipped = false;
   out.reason = "";
   double inputs[7];
   inputs[0] = balance;  inputs[1] = riskPct;  inputs[2] = stopDist;  inputs[3] = tickSize;
   inputs[4] = tickValue; inputs[5] = volMin;  inputs[6] = volStep;
   for(int i = 0; i < 7; i++)
      if(!MathIsValidNumber(inputs[i]) || inputs[i] <= 0.0)
        {
         out.reason = "all sizing inputs must be > 0";
         return false;
        }
   double target = balance * riskPct / 100.0;
   double lossPerLot = (stopDist / tickSize) * tickValue;
   double rawHalf = (target / lossPerLot) / 2.0;
   double steps = MathFloor(rawHalf / volStep + NNFX_SIZE_EPS);
   double half = NormalizeDouble(steps * volStep, 8);
   if(volMax > 0.0 && half > volMax)
      half = NormalizeDouble(MathFloor(volMax / volStep + NNFX_SIZE_EPS) * volStep, 8);
   out.target_risk_money = target;
   if(half + NNFX_SIZE_EPS < volMin)
     {
      out.skipped = true;
      out.reason = "too small to size";
      return true;
     }
   out.half_lots = half;
   out.total_lots = NormalizeDouble(half * 2.0, 8);
   out.risk_money = out.total_lots * lossPerLot;
   return true;
  }

// Sizes a trade on `sym` from the account and the symbol's properties read NOW
// (carry-over 2: never from recorded values). tickValueUsed reports the tick value used.
bool NNFXSizeForSymbol(const string sym, const double riskPct, const double stopDist,
                       NNFXSize &out, double &tickValueUsed)
  {
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   tickValueUsed = NNFXTickValueForSizing(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE),
                                          SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS));
   if(tickValueUsed <= 0.0 || tickSize <= 0.0)
     {
      NNFXSizeTrade(0, 0, 0, 0, 0, 0, 0, 0, out);   // clears out
      out.reason = sym + ": tick value or tick size not > 0 (not logged in, or symbol not synced)";
      return false;
     }
   return NNFXSizeTrade(AccountInfoDouble(ACCOUNT_BALANCE), riskPct, stopDist, tickSize, tickValueUsed,
                        SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP),
                        SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX), out);
  }

#endif
