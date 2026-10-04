//+------------------------------------------------------------------+
//| NNFX_OrderMathTest.mq5                                           |
//| Phase 6b check: OrderMath.mqh gives the same order prices as the |
//| Python answer key (orders.py) on identical, hand-worked cases:   |
//| OP (SL/TP1/TP2/BE), OE (rejected inputs), TR (one trail step),   |
//| SD (minimum stop distance) lines of                              |
//|   MQL5\Files\NNFX\orders\order_cases.txt                         |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_OrderMathTest.txt       |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| 22/22, run 20261004_162607).                                     |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\OrderMath.mqh>

input string InpCases = "NNFX\\orders\\order_cases.txt"; // Order cases (MQL5\Files)

int g_report = INVALID_HANDLE;
int g_pass = 0, g_fail = 0;

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

void Result(const bool ok, const string what)
  {
   if(ok)
      g_pass++;
   else
      g_fail++;
   Out((ok ? "PASS " : "FAIL ") + what);
  }

string Trim(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
  }

bool Near(const double a, const double b)
  {
   return MathAbs(a - b) <= 1e-9;
  }

double Cap(const string text)
  {
   return (text == "-") ? NNFX_CAP_OFF : StringToDouble(text);
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_OrderMathTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_OrderMathTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   int h = FileOpen(InpCases, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      Result(false, "open " + InpCases + " (error " + IntegerToString(GetLastError()) + ")");
   else
     {
      int count = 0;
      while(!FileIsEnding(h))
        {
         string line = Trim(FileReadString(h));
         if(line == "" || StringGetCharacter(line, 0) == '#')
            continue;
         string p[];
         int n = StringSplit(line, '|', p);
         string kind = (n > 0) ? p[0] : "";
         if(kind == "SF")
            continue;   // safety cases: NNFX_SafetyTest
         count++;
         if(kind == "OP" && n == 13)
           {
            int d = (int)StringToInteger(p[2]);
            double fill = StringToDouble(p[3]);
            double sl, tp1, tp2;
            bool ok = NNFXPlanPrices(d, fill, StringToDouble(p[4]), StringToDouble(p[5]), StringToDouble(p[6]),
                                     StringToDouble(p[7]), Cap(p[8]), sl, tp1, tp2);
            double wantTp2 = (p[11] == "-") ? 0.0 : StringToDouble(p[11]);
            bool good = ok && Near(sl, StringToDouble(p[9])) && Near(tp1, StringToDouble(p[10])) && Near(tp2, wantTp2) &&
                        Near(NNFXBreakevenPrice(fill), StringToDouble(p[12])) &&
                        MathAbs(fill - sl) <= StringToDouble(p[6]) * StringToDouble(p[4]) + 1e-12;
            Result(good, StringFormat("prices %s: expected SL %s TP1 %s TP2 %s BE %s; got %.10g %.10g %.10g %.10g", p[1],
                                      p[9], p[10], p[11], p[12], sl, tp1, tp2, NNFXBreakevenPrice(fill)));
           }
         else if(kind == "OE" && n == 9)
           {
            double sl, tp1, tp2;
            bool ok = NNFXPlanPrices((int)StringToInteger(p[2]), StringToDouble(p[3]), StringToDouble(p[4]),
                                     StringToDouble(p[5]), StringToDouble(p[6]), StringToDouble(p[7]), Cap(p[8]),
                                     sl, tp1, tp2);
            Result(!ok, StringFormat("prices %s: inputs must be rejected; got %s", p[1], ok ? "ACCEPTED" : "rejected"));
           }
         else if(kind == "TR" && n == 14)
           {
            bool active = (p[6] == "1");
            double newSl;
            NNFXTrailStep((int)StringToInteger(p[2]), StringToDouble(p[3]), StringToDouble(p[4]), StringToDouble(p[5]),
                          active, StringToDouble(p[7]), StringToDouble(p[8]), StringToDouble(p[9]),
                          StringToDouble(p[10]), StringToDouble(p[11]), newSl);
            bool good = Near(newSl, StringToDouble(p[12])) && active == (p[13] == "1");
            Result(good, StringFormat("trail %s: expected SL %s active %s; got %.10g %s", p[1], p[12], p[13], newSl,
                                      active ? "1" : "0"));
           }
         else if(kind == "SD" && n == 7)
           {
            bool got = NNFXStopDistanceOk(StringToDouble(p[2]), StringToDouble(p[3]), StringToInteger(p[4]),
                                          StringToDouble(p[5]));
            Result(got == (p[6] == "1"), StringFormat("stop distance %s: expected %s got %s", p[1], p[6], got ? "1" : "0"));
           }
         else
            Result(false, "order case: unreadable line " + line);
        }
      FileClose(h);
      Out(StringFormat("(%d order cases read, SF lines left to NNFX_SafetyTest)", count));
     }
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", g_pass, g_fail, g_pass + g_fail));
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
