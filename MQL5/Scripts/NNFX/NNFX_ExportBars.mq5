//+------------------------------------------------------------------+
//| NNFX_ExportBars.mq5                                              |
//| Phase 5 check: exports, for each closed candle, the prices, ATR, |
//| raw indicator values and the directions the slot layer computed. |
//|                                                                  |
//| Used for:                                                        |
//|  - the Data Window spot check (compare a few rows with MT5);     |
//|  - tools/check_export.py, which recomputes every direction and   |
//|    volume pass in Python from the raw values and must agree;     |
//|  - later (Phase 7), the bar-by-bar cross-check.                  |
//|                                                                  |
//| Places NO orders. Writes                                         |
//|   MQL5\Files\NNFX\export\<symbol>_<timeframe>.csv                |
//| Status: NOT YET COMPILED.                                        |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <NNFX\BarBuilder.mqh>

input string          InpSymbols  = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY"; // Pairs (VP's 5 test pairs)
input ENUM_TIMEFRAMES InpTF       = PERIOD_H1;                          // Timeframe
input int             InpBars     = 3000;                               // Closed candles to export
input string          InpBaseline = "ref_baseline_sma20.txt";           // Profiles (Common\Files\NNFX\profiles)
input string          InpC1       = "ref_c1_rvi10.txt";
input string          InpC2       = "ref_c2_macd_main.txt";
input string          InpExit     = "ref_exit_macd_cross.txt";
input string          InpVolume   = "ref_volume_ticks20.txt";

// Full-precision text for a value; bad values as tokens the Python checker understands.
string Num(const double v)
  {
   if(!MathIsValidNumber(v))
      return "nan";
   if(v >= EMPTY_VALUE || v <= -EMPTY_VALUE)
      return "empty";
   return StringFormat("%.17g", v);
  }

string TfName(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);      // e.g. "PERIOD_H1"
   StringReplace(s, "PERIOD_", "");
   return s;
  }

bool ExportOne(const string symbol, const string &profiles[])
  {
   if(!SymbolSelect(symbol, true))
     {
      Print("NNFX_ExportBars: symbol not found: ", symbol);
      return false;
     }
   CNNFXBarBuilder bb;
   if(!bb.Init(symbol, InpTF, profiles, true))
     {
      Print("NNFX_ExportBars: ", symbol, ": ", bb.Error());
      return false;
     }
   // Wait (briefly) for history and indicator calculation.
   for(int k = 0; k < 50 && Bars(symbol, InpTF) < InpBars + 100; k++)
      Sleep(200);
   for(int k = 0; k < 50; k++)
     {
      NNFXBar b;
      NNFXRaw r;
      if(bb.Build(1, b, r))
         break;
      Sleep(200);
     }
   int available = Bars(symbol, InpTF) - 2;
   int count = MathMin(InpBars, available);
   if(count < 1)
     {
      Print("NNFX_ExportBars: ", symbol, ": no history on ", TfName(InpTF));
      return false;
     }
   string path = "NNFX\\export\\" + symbol + "_" + TfName(InpTF) + ".csv";
   int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Print("NNFX_ExportBars: cannot write ", path, " error ", GetLastError());
      return false;
     }
   FileWriteString(h, StringFormat("# symbol=%s timeframe=%s profiles=%s,%s,%s,%s,%s atr=14 build=%d\r\n",
                                   symbol, TfName(InpTF), profiles[0], profiles[1], profiles[2],
                                   profiles[3], profiles[4], (int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileWriteString(h, "time,open,high,low,close,atr,base,c1_a,c1_b,c2_a,c2_b,ex_a,ex_b,vol,vol_ref,"
                      "c1,c2,ex,vol_pass,ok,why\r\n");
   int written = 0, usable = 0;
   // Oldest first, so the file reads in time order.
   for(int shift = count; shift >= 1; shift--)
     {
      NNFXBar b;
      NNFXRaw r;
      bool ok = bb.Build(shift, b, r);
      string row = TimeToString(r.time, TIME_DATE | TIME_MINUTES) + "," +
                   Num(b.o) + "," + Num(b.h) + "," + Num(b.l) + "," + Num(b.c) + "," + Num(b.atr) + "," +
                   Num(r.v[NNFX_SLOT_BASE][0]) + "," +
                   Num(r.v[NNFX_SLOT_C1][0]) + "," + Num(r.v[NNFX_SLOT_C1][1]) + "," +
                   Num(r.v[NNFX_SLOT_C2][0]) + "," + Num(r.v[NNFX_SLOT_C2][1]) + "," +
                   Num(r.v[NNFX_SLOT_EX][0]) + "," + Num(r.v[NNFX_SLOT_EX][1]) + "," +
                   Num(r.v[NNFX_SLOT_VOL][0]) + "," + Num(r.vol_ref) + "," +
                   IntegerToString(b.c1) + "," + IntegerToString(b.c2) + "," + IntegerToString(b.ex) + "," +
                   (b.vol ? "1" : "0") + "," + (ok ? "1" : "0") + "," + r.why;
      FileWriteString(h, row + "\r\n");
      written++;
      if(ok)
         usable++;
     }
   FileClose(h);
   Print(StringFormat("NNFX_ExportBars: %s %s: %d candles written (%d usable) to MQL5\\Files\\%s",
                      symbol, TfName(InpTF), written, usable, path));
   return true;
  }

void OnStart()
  {
   string profiles[5];
   profiles[0] = InpBaseline;
   profiles[1] = InpC1;
   profiles[2] = InpC2;
   profiles[3] = InpExit;
   profiles[4] = InpVolume;
   string syms[];
   int n = StringSplit(InpSymbols, ',', syms);
   int done = 0;
   for(int k = 0; k < n; k++)
     {
      string s = NNFXTrim(syms[k]);
      if(s != "" && ExportOne(s, profiles))
         done++;
     }
   Print(StringFormat("NNFX_ExportBars: finished, %d of %d pairs exported", done, n));
  }
//+------------------------------------------------------------------+
