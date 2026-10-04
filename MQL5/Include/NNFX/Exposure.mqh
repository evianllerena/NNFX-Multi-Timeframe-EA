//+------------------------------------------------------------------+
//| Exposure.mqh - same-currency exposure across all positions       |
//|                                                                  |
//| Port of tests/python/nnfx_ref/exposure.py (rulebook M6, M7;      |
//| decisions S-4, OD-4, OD-20, OD-21).                              |
//|                                                                  |
//| Each position is split into its two currencies with direction:   |
//| long EURUSD = long EUR + short USD. Only same-direction exposure  |
//| counts. Modes for new signals: "first" (fixed order, a second    |
//| same-direction trade on a currency is skipped) and "split" (two  |
//| signals sharing a leg only with each other get half risk; three  |
//| or more on a leg are all skipped; a conflict with an open        |
//| position is skipped). Open positions on non-FX symbols (not two  |
//| of the 8 majors, rulebook P1) are ignored with a log line.       |
//|                                                                  |
//| Places NO orders.                                                |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_EXPOSURE_MQH
#define NNFX_EXPOSURE_MQH

// The 8 majors whose 28 pairs VP trades (rulebook P1).
#define NNFX_MAJORS "USD,EUR,GBP,JPY,CHF,CAD,AUD,NZD"

struct NNFXPos
  {
   string            sym;
   int               dir;     // +1 long, -1 short
  };

// Base and quote currency from a symbol such as "EURUSD" or "eurusd.m": letters only,
// upper case, the first six. False if fewer than six letters.
bool NNFXCurrencies(const string sym, string &base, string &quote)
  {
   string letters = "";
   for(int i = 0; i < StringLen(sym); i++)
     {
      ushort c = StringGetCharacter(sym, i);
      if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
         letters += ShortToString(c);
     }
   StringToUpper(letters);
   if(StringLen(letters) < 6)
     {
      base = "";
      quote = "";
      return false;
     }
   base = StringSubstr(letters, 0, 3);
   quote = StringSubstr(letters, 3, 3);
   return true;
  }

bool NNFXIsMajor(const string cur)
  {
   string majors[];
   int n = StringSplit(NNFX_MAJORS, ',', majors);
   for(int i = 0; i < n; i++)
      if(majors[i] == cur)
         return true;
   return false;
  }

// True if the symbol is a pair of two different major currencies (OD-21).
bool NNFXIsFx(const string sym)
  {
   string base, quote;
   if(!NNFXCurrencies(sym, base, quote))
      return false;
   return NNFXIsMajor(base) && NNFXIsMajor(quote) && base != quote;
  }

// The two legs of a position as keys "EUR:1" / "USD:-1". False if not FX or dir not +-1.
bool NNFXLegs(const string sym, const int dir, string &leg1, string &leg2)
  {
   string base, quote;
   if((dir != 1 && dir != -1) || !NNFXIsFx(sym) || !NNFXCurrencies(sym, base, quote))
      return false;
   leg1 = base + ":" + IntegerToString(dir);
   leg2 = quote + ":" + IntegerToString(-dir);
   return true;
  }

int NNFXFindKey(const string &keys[], const string key)
  {
   for(int i = 0; i < ArraySize(keys); i++)
      if(keys[i] == key)
         return i;
   return -1;
  }

void NNFXAddKey(string &keys[], const string key)
  {
   if(NNFXFindKey(keys, key) < 0)
     {
      int n = ArraySize(keys);
      ArrayResize(keys, n + 1);
      keys[n] = key;
     }
  }

// Risk percentage for each new signal (0 = skipped), in signal order, in out[].
// openPos: every open position on the account (all EAs, manual trades), whatever its stop.
// log: one line per ignored non-FX open position. Returns false (and log) on bad input:
// unknown mode, or a signal on a non-FX symbol.
bool NNFXAllocate(const NNFXPos &openPos[], const NNFXPos &signals[], const double riskPct,
                  const string mode, double &out[], string &log)
  {
   log = "";
   int ns = ArraySize(signals);
   ArrayResize(out, ns);
   ArrayInitialize(out, 0.0);
   if(mode != "first" && mode != "split")
     {
      log = "exposure: mode must be first or split";
      return false;
     }
   string l1, l2;
   for(int i = 0; i < ns; i++)
      if(!NNFXLegs(signals[i].sym, signals[i].dir, l1, l2))
        {
         log = "exposure: signal on a non-FX symbol or bad direction: " + signals[i].sym;
         return false;
        }
   string held[];
   ArrayResize(held, 0);
   for(int i = 0; i < ArraySize(openPos); i++)
     {
      if(!NNFXLegs(openPos[i].sym, openPos[i].dir, l1, l2))
        {
         log += (log == "" ? "" : "\n") + "exposure: ignored non-FX position " + openPos[i].sym;
         continue;
        }
      NNFXAddKey(held, l1);
      NNFXAddKey(held, l2);
     }

   if(mode == "first")
     {
      string taken[];
      ArrayCopy(taken, held);
      for(int i = 0; i < ns; i++)
        {
         NNFXLegs(signals[i].sym, signals[i].dir, l1, l2);
         if(NNFXFindKey(taken, l1) >= 0 || NNFXFindKey(taken, l2) >= 0)
            out[i] = 0.0;
         else
           {
            out[i] = riskPct;
            NNFXAddKey(taken, l1);
            NNFXAddKey(taken, l2);
           }
        }
      return true;
     }

   // split: count each leg over the signals that don't conflict with an open position
   bool eligible[];
   ArrayResize(eligible, ns);
   string keys[];
   int counts[];
   ArrayResize(keys, 0);
   ArrayResize(counts, 0);
   for(int i = 0; i < ns; i++)
     {
      NNFXLegs(signals[i].sym, signals[i].dir, l1, l2);
      eligible[i] = (NNFXFindKey(held, l1) < 0 && NNFXFindKey(held, l2) < 0);
      if(!eligible[i])
         continue;
      string mine[2];
      mine[0] = l1;
      mine[1] = l2;
      for(int k = 0; k < 2; k++)
        {
         int at = NNFXFindKey(keys, mine[k]);
         if(at < 0)
           {
            at = ArraySize(keys);
            ArrayResize(keys, at + 1);
            ArrayResize(counts, at + 1);
            keys[at] = mine[k];
            counts[at] = 0;
           }
         counts[at]++;
        }
     }
   for(int i = 0; i < ns; i++)
     {
      if(!eligible[i])
         continue;
      NNFXLegs(signals[i].sym, signals[i].dir, l1, l2);
      int shared = MathMax(counts[NNFXFindKey(keys, l1)], counts[NNFXFindKey(keys, l2)]);
      if(shared == 1)
         out[i] = riskPct;
      else if(shared == 2)
         out[i] = riskPct / 2.0;
      else
         out[i] = 0.0;   // three or more on one leg: not covered by VP's rule; skip (OD-4)
     }
   return true;
  }

// Every open position on the account, of every EA and manual trades (M6: "all three
// EAs, all pairs, and any manual trades"). Returns the count.
int NNFXOpenPositions(NNFXPos &out[])
  {
   int n = PositionsTotal();
   ArrayResize(out, 0);
   for(int i = 0; i < n; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k].sym = PositionGetString(POSITION_SYMBOL);
      out[k].dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
     }
   return ArraySize(out);
  }

#endif
