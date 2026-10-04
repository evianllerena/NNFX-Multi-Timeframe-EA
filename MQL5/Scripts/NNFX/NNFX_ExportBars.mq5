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
//| Waits until MT5 is logged in first; if it is not, _summary.txt   |
//| ends "RESULT: INVALID (not connected)" and nothing is exported.  |
//|                                                                  |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| run 20261004_115428, 5 of 5 pairs complete).                     |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).

#include <NNFX\BarBuilder.mqh>
#include <NNFX\Connection.mqh>

input string          InpSymbols  = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY"; // Pairs (VP's 5 test pairs)
input ENUM_TIMEFRAMES InpTF       = PERIOD_H1;                          // Timeframe
input int             InpBars     = 3000;                               // Closed candles to export
input string          InpBaseline = "ref_baseline_sma20.txt";           // Profiles (Common\Files\NNFX\profiles)
input string          InpC1       = "ref_c1_rvi10.txt";
input string          InpC2       = "ref_c2_macd_main.txt";
input string          InpExit     = "ref_exit_macd_cross.txt";
input string          InpVolume   = "ref_volume_ticks20.txt";
input int             InpConnectWait = 120;                             // Seconds to wait for the terminal to log in

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

// Ask MT5 for enough candles and wait until the terminal has them (history is downloaded on
// request). Returns the number of candles available.
int EnsureHistory(const string symbol, const int need)
  {
   MqlRates rates[];
   int got = 0;
   for(int k = 0; k < 120; k++)          // up to about 60 seconds
     {
      got = CopyRates(symbol, InpTF, 0, need, rates);
      if(got >= need)
         break;
      Sleep(500);
     }
   return MathMax(got, Bars(symbol, InpTF));
  }

bool ExportOne(const string symbol, const string &profiles[], const int summary)
  {
   if(!SymbolSelect(symbol, true))
     {
      Print("NNFX_ExportBars: symbol not found: ", symbol);
      FileWriteString(summary, symbol + " requested=" + IntegerToString(InpBars) + " written=0 usable=0 complete=no reason=symbol_not_found\r\n");
      return false;
     }
   // Candles to export + warm-up margin + the current (forming) candle.
   int need = InpBars + 200;
   int have = EnsureHistory(symbol, need);
   CNNFXBarBuilder bb;
   if(!bb.Init(symbol, InpTF, profiles, true))
     {
      Print("NNFX_ExportBars: ", symbol, ": ", bb.Error());
      FileWriteString(summary, symbol + " requested=" + IntegerToString(InpBars) + " written=0 usable=0 complete=no reason=init_failed\r\n");
      return false;
     }
   for(int k = 0; k < 120 && !bb.AllCalculated(); k++)   // up to about 60 seconds
      Sleep(500);
   bool calculated = bb.AllCalculated();
   int available = Bars(symbol, InpTF) - 2;
   int count = MathMin(InpBars, available);
   if(count < 1)
     {
      Print("NNFX_ExportBars: ", symbol, ": no history on ", TfName(InpTF));
      FileWriteString(summary, symbol + " requested=" + IntegerToString(InpBars) + " written=0 usable=0 complete=no reason=no_history\r\n");
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
   FileWriteString(h, "time,open,high,low,close,tickvol,atr,base,c1_a,c1_b,c2_a,c2_b,ex_a,ex_b,vol,vol_ref,"
                      "c1,c2,ex,vol_pass,ok,why\r\n");
   int written = 0, usable = 0;
   string first = "", last = "";
   // Oldest first, so the file reads in time order.
   for(int shift = count; shift >= 1; shift--)
     {
      NNFXBar b;
      NNFXRaw r;
      bool ok = bb.Build(shift, b, r);
      string t = TimeToString(r.time, TIME_DATE | TIME_MINUTES);
      if(first == "")
         first = t;
      last = t;
      string row = t + "," +
                   Num(b.o) + "," + Num(b.h) + "," + Num(b.l) + "," + Num(b.c) + "," +
                   IntegerToString(iVolume(symbol, InpTF, shift)) + "," + Num(b.atr) + "," +
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
   bool complete = (written == InpBars) && calculated;
   FileWriteString(summary, StringFormat("%s requested=%d written=%d usable=%d complete=%s history=%d calculated=%s first=%s last=%s\r\n",
                                         symbol, InpBars, written, usable, complete ? "yes" : "no", have,
                                         calculated ? "yes" : "no", first, last));
   Print(StringFormat("NNFX_ExportBars: %s %s: %d of %d candles written (%d usable)%s to MQL5\\Files\\%s",
                      symbol, TfName(InpTF), written, InpBars, usable, complete ? "" : " INCOMPLETE", path));
   return complete;
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
   for(int k = 0; k < n; k++)
      syms[k] = NNFXTrim(syms[k]);
   int done = 0;
   int summary = FileOpen("NNFX\\export\\_summary.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   // History and indicator values come from the server: export nothing before login.
   string detail;
   if(!NNFXWaitConnected(syms, InpConnectWait, detail))
     {
      FileWriteString(summary, "connection: " + detail + "\r\n");
      FileWriteString(summary, NNFX_RESULT_NOT_CONNECTED + "\r\n");
      FileClose(summary);
      Print("NNFX_ExportBars: not connected, nothing exported: ", detail);
      return;
     }
   FileWriteString(summary, "connection: " + detail + "\r\n");
   for(int k = 0; k < n; k++)
     {
      string s = syms[k];
      if(s != "" && ExportOne(s, profiles, summary))
         done++;
     }
   FileWriteString(summary, StringFormat("RESULT: %d of %d pairs complete\r\n", done, n));
   FileClose(summary);
   Print(StringFormat("NNFX_ExportBars: finished, %d of %d pairs complete", done, n));
  }
//+------------------------------------------------------------------+
