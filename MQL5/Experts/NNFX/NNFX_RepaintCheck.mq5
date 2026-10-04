//+------------------------------------------------------------------+
//| NNFX_RepaintCheck.mq5  (Strategy Tester only; never trades)      |
//|                                                                  |
//| Spec check V2: does an indicator rewrite its past values?        |
//|                                                                  |
//| While the tester replays history, at every new candle this EA    |
//| records each profile's values for the candle that just closed    |
//| (what the EA would have seen live). When the test ends it reads  |
//| the same candles again from the finished indicator and compares. |
//| Any difference = the indicator repaints and is rejected.         |
//|                                                                  |
//| Run it in the Strategy Tester (model "1 minute OHLC" or "Every   |
//| tick"). Profiles are read from Common\Files\NNFX\profiles\.      |
//| Report: Common\Files\NNFX\reports\Repaint_<symbol>_<tf>.txt      |
//|                                                                  |
//| This EA contains NO trading code: it places no orders.           |
//| Status: compiled 2026-10-04, MT5 build 6238, 0 errors 0 warnings.|
//+------------------------------------------------------------------+
#property description "NNFX repaint check (V2). Strategy Tester only; places no orders."

#include <NNFX\Slot.mqh>

input string InpProfiles = "ref_baseline_sma20.txt,ref_c1_rvi10.txt,ref_c2_macd_main.txt,ref_exit_macd_cross.txt,ref_volume_ticks20.txt"; // Profiles to check

CNNFXSlot g_slots[];
string    g_files[];
datetime  g_last_bar = 0;
// recorded "as seen at the close" values
int       r_slot[];
int       r_buf[];
datetime  r_time[];
double    r_val[];
int       g_records = 0;

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER))
     {
      Print("NNFX_RepaintCheck runs in the Strategy Tester only.");
      return INIT_FAILED;
     }
   string parts[];
   int n = StringSplit(InpProfiles, ',', parts);
   ArrayResize(g_slots, n);
   ArrayResize(g_files, n);
   for(int k = 0; k < n; k++)
     {
      g_files[k] = NNFXTrim(parts[k]);
      if(!g_slots[k].Init(_Symbol, _Period, NNFX_PROFILE_DIR + g_files[k], true))
        {
         Print("NNFX_RepaintCheck: ", g_slots[k].Error());
         return INIT_FAILED;
        }
     }
   return INIT_SUCCEEDED;
  }

void Record(const int slot, const int buf, const datetime t, const double v)
  {
   if(g_records >= ArraySize(r_val))
     {
      int size = g_records + 4096;
      ArrayResize(r_slot, size);
      ArrayResize(r_buf, size);
      ArrayResize(r_time, size);
      ArrayResize(r_val, size);
     }
   r_slot[g_records] = slot;
   r_buf[g_records] = buf;
   r_time[g_records] = t;
   r_val[g_records] = v;
   g_records++;
  }

void OnTick()
  {
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == g_last_bar)
      return;
   g_last_bar = t0;
   datetime t1 = iTime(_Symbol, _Period, 1);   // the candle that just closed
   for(int k = 0; k < ArraySize(g_slots); k++)
     {
      if(!g_slots[k].Ready(1))
         continue;
      for(int j = 0; j < g_slots[k].BufferCount(); j++)
        {
         int buf = g_slots[k].BufferAt(j);
         Record(k, buf, t1, g_slots[k].Value(buf, 1));
        }
     }
  }

bool Same(const double a, const double b)
  {
   bool ba = NNFXIsBad(a), bb = NNFXIsBad(b);
   if(ba || bb)
      return ba && bb;
   return MathAbs(a - b) <= 1e-10 * MathMax(1.0, MathMax(MathAbs(a), MathAbs(b)));
  }

double OnTester()
  {
   int n = ArraySize(g_slots);
   int checked[], diffs[], missing[];
   ArrayResize(checked, n);
   ArrayResize(diffs, n);
   ArrayResize(missing, n);
   ArrayInitialize(checked, 0);
   ArrayInitialize(diffs, 0);
   ArrayInitialize(missing, 0);
   string examples[];
   for(int i = 0; i < g_records; i++)
     {
      int k = r_slot[i];
      int shift = iBarShift(_Symbol, _Period, r_time[i], true);
      if(shift < 1)
        {
         missing[k]++;
         continue;
        }
      double now = g_slots[k].Value(r_buf[i], shift);
      checked[k]++;
      if(!Same(r_val[i], now))
        {
         diffs[k]++;
         if(ArraySize(examples) < 30)
           {
            int e = ArraySize(examples);
            ArrayResize(examples, e + 1);
            examples[e] = StringFormat("  %s %s buffer %d: at close %.10g, later %.10g",
                                       g_slots[k].Name(), TimeToString(r_time[i]), r_buf[i], r_val[i], now);
           }
        }
     }

   string tf = EnumToString(_Period);
   StringReplace(tf, "PERIOD_", "");
   string path = "NNFX\\reports\\Repaint_" + _Symbol + "_" + tf + ".txt";
   int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   int total_diffs = 0;
   string lines[];
   int L = 0;
   ArrayResize(lines, n + 4 + ArraySize(examples));
   lines[L++] = StringFormat("NNFX_RepaintCheck %s %s, terminal build %d", _Symbol, tf,
                             (int)TerminalInfoInteger(TERMINAL_BUILD));
   for(int k = 0; k < n; k++)
     {
      total_diffs += diffs[k];
      lines[L++] = StringFormat("%s %s: %d values checked, %d changed later, %d candles not found",
                                diffs[k] == 0 && checked[k] > 0 ? "PASS" : "FAIL", g_files[k],
                                checked[k], diffs[k], missing[k]);
     }
   for(int e = 0; e < ArraySize(examples); e++)
      lines[L++] = examples[e];
   lines[L++] = StringFormat("RESULT: %s (%d changed values)", total_diffs == 0 ? "NO REPAINTING FOUND" : "REPAINTING FOUND",
                             total_diffs);
   for(int i = 0; i < L; i++)
     {
      Print(lines[i]);
      if(h != INVALID_HANDLE)
         FileWriteString(h, lines[i] + "\r\n");
     }
   if(h != INVALID_HANDLE)
     {
      FileClose(h);
      Print("NNFX_RepaintCheck: report written to Common\\Files\\", path);
     }
   return 0.0;
  }
//+------------------------------------------------------------------+
