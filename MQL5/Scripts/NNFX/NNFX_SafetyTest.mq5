//+------------------------------------------------------------------+
//| NNFX_SafetyTest.mq5                                              |
//| Phase 6b check S1 (docs/PLAN_PHASE6.md section 1): the order     |
//| safety decision NNFXOrdersAllowedFor gives the same answer as    |
//| the Python answer key on all 6 cases (DEMO, CONTEST, REAL) x     |
//| (tester, not tester): the SF lines of                            |
//|   MQL5\Files\NNFX\orders\order_cases.txt                         |
//| Also reports (information only) what NNFXOrdersAllowed says for  |
//| the account this script runs on.                                 |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_SafetyTest.txt          |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\Orders.mqh>

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

bool Mode(const string name, long &mode)
  {
   if(name == "DEMO")    { mode = ACCOUNT_TRADE_MODE_DEMO;    return true; }
   if(name == "CONTEST") { mode = ACCOUNT_TRADE_MODE_CONTEST; return true; }
   if(name == "REAL")    { mode = ACCOUNT_TRADE_MODE_REAL;    return true; }
   return false;
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_SafetyTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_SafetyTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   int h = FileOpen(InpCases, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      Result(false, "open " + InpCases + " (error " + IntegerToString(GetLastError()) + ")");
   else
     {
      while(!FileIsEnding(h))
        {
         string line = FileReadString(h);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringFind(line, "SF|") != 0)
            continue;
         string p[];
         long mode;
         if(StringSplit(line, '|', p) != 5 || !Mode(p[2], mode))
           {
            Result(false, "safety case: unreadable line " + line);
            continue;
           }
         bool got = NNFXOrdersAllowedFor(mode, p[3] == "1");
         Result(got == (p[4] == "1"), StringFormat("safety %s (%s, tester=%s): expected %s got %s", p[1], p[2], p[3],
                                                   p[4], got ? "1" : "0"));
        }
      FileClose(h);
     }
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", g_pass, g_fail, g_pass + g_fail));
   string why;
   bool here = NNFXOrdersAllowed(why);
   Out("THIS ACCOUNT (information only, not counted): trade mode " + IntegerToString(AccountInfoInteger(ACCOUNT_TRADE_MODE)) +
       " -> " + (here ? "allowed" : "refused") + ": " + why);
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
