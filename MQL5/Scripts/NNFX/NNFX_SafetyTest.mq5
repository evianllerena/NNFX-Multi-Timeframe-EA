//+------------------------------------------------------------------+
//| NNFX_SafetyTest.mq5                                              |
//| Phase 6b check S1 (docs/PLAN_PHASE6.md section 1): the order     |
//| safety decision NNFXOrdersAllowedFor gives the same answer as    |
//| the Python answer key on all 6 cases (DEMO, CONTEST, REAL) x     |
//| (tester, not tester): the SF lines of                            |
//|   MQL5\Files\NNFX\orders\order_cases.txt                         |
//| Review fixes 2026-10-14: also the MM lines (A7, NNFXHedgingOk)   |
//| and the RC lines (B3, NNFXRetcodeRetryable). Not yet compiled.   |
//| Also reports (information only) what NNFXOrdersAllowed says for  |
//| the account this script runs on.                                 |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_SafetyTest.txt          |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| 6/6, run 20261004_162607).                                       |
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

bool MarginMode(const string name, long &mode)
  {
   if(name == "HEDGING")  { mode = ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; return true; }
   if(name == "NETTING")  { mode = ACCOUNT_MARGIN_MODE_RETAIL_NETTING; return true; }
   if(name == "EXCHANGE") { mode = ACCOUNT_MARGIN_MODE_EXCHANGE;       return true; }
   return false;
  }

// The RC lines name MT5's TRADE_RETCODE_* constants without the prefix, so no retcode number is typed by hand.
bool Retcode(const string name, uint &code)
  {
   if(name == "REQUOTE")            { code = TRADE_RETCODE_REQUOTE;            return true; }
   if(name == "REJECT")             { code = TRADE_RETCODE_REJECT;             return true; }
   if(name == "ERROR")              { code = TRADE_RETCODE_ERROR;              return true; }
   if(name == "TIMEOUT")            { code = TRADE_RETCODE_TIMEOUT;            return true; }
   if(name == "INVALID_PRICE")      { code = TRADE_RETCODE_INVALID_PRICE;      return true; }
   if(name == "PRICE_CHANGED")      { code = TRADE_RETCODE_PRICE_CHANGED;      return true; }
   if(name == "PRICE_OFF")          { code = TRADE_RETCODE_PRICE_OFF;          return true; }
   if(name == "TOO_MANY_REQUESTS")  { code = TRADE_RETCODE_TOO_MANY_REQUESTS;  return true; }
   if(name == "LOCKED")             { code = TRADE_RETCODE_LOCKED;             return true; }
   if(name == "FROZEN")             { code = TRADE_RETCODE_FROZEN;             return true; }
   if(name == "CONNECTION")         { code = TRADE_RETCODE_CONNECTION;         return true; }
   if(name == "INVALID")            { code = TRADE_RETCODE_INVALID;            return true; }
   if(name == "INVALID_VOLUME")     { code = TRADE_RETCODE_INVALID_VOLUME;     return true; }
   if(name == "INVALID_STOPS")      { code = TRADE_RETCODE_INVALID_STOPS;      return true; }
   if(name == "TRADE_DISABLED")     { code = TRADE_RETCODE_TRADE_DISABLED;     return true; }
   if(name == "MARKET_CLOSED")      { code = TRADE_RETCODE_MARKET_CLOSED;      return true; }
   if(name == "NO_MONEY")           { code = TRADE_RETCODE_NO_MONEY;           return true; }
   if(name == "INVALID_FILL")       { code = TRADE_RETCODE_INVALID_FILL;       return true; }
   if(name == "SERVER_DISABLES_AT") { code = TRADE_RETCODE_SERVER_DISABLES_AT; return true; }
   if(name == "CLIENT_DISABLES_AT") { code = TRADE_RETCODE_CLIENT_DISABLES_AT; return true; }
   if(name == "ONLY_REAL")          { code = TRADE_RETCODE_ONLY_REAL;          return true; }
   if(name == "LIMIT_ORDERS")       { code = TRADE_RETCODE_LIMIT_ORDERS;       return true; }
   if(name == "LIMIT_VOLUME")       { code = TRADE_RETCODE_LIMIT_VOLUME;       return true; }
   if(name == "LIMIT_POSITIONS")    { code = TRADE_RETCODE_LIMIT_POSITIONS;    return true; }
   if(name == "INVALID_ORDER")      { code = TRADE_RETCODE_INVALID_ORDER;      return true; }
   if(name == "POSITION_CLOSED")    { code = TRADE_RETCODE_POSITION_CLOSED;    return true; }
   if(name == "HEDGE_PROHIBITED")   { code = TRADE_RETCODE_HEDGE_PROHIBITED;   return true; }
   if(name == "FIFO_CLOSE")         { code = TRADE_RETCODE_FIFO_CLOSE;         return true; }
   if(name == "INVALID_EXPIRATION") { code = TRADE_RETCODE_INVALID_EXPIRATION; return true; }
   if(name == "INVALID_CLOSE_VOLUME") { code = TRADE_RETCODE_INVALID_CLOSE_VOLUME; return true; }
   if(name == "CLOSE_ORDER_EXIST")  { code = TRADE_RETCODE_CLOSE_ORDER_EXIST;  return true; }
   if(name == "LONG_ONLY")          { code = TRADE_RETCODE_LONG_ONLY;          return true; }
   if(name == "SHORT_ONLY")         { code = TRADE_RETCODE_SHORT_ONLY;         return true; }
   if(name == "CLOSE_ONLY")         { code = TRADE_RETCODE_CLOSE_ONLY;         return true; }
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
         if(StringFind(line, "MM|") == 0 || StringFind(line, "RC|") == 0)
           {
            string q[];
            long mm = 0;
            uint rc = 0;
            bool isMm = (StringFind(line, "MM|") == 0);
            if(StringSplit(line, '|', q) != 4 || (isMm ? !MarginMode(q[2], mm) : !Retcode(q[2], rc)))
              {
               Result(false, (isMm ? "margin-mode" : "retcode") + " case: unreadable line " + line);
               continue;
              }
            bool res = isMm ? NNFXHedgingOk(mm) : NNFXRetcodeRetryable(rc);
            Result(res == (q[3] == "1"), StringFormat("%s %s (%s): expected %s got %s", isMm ? "margin mode" : "retry", q[1],
                                                      q[2], q[3], res ? "1" : "0"));
            continue;
           }
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
       ", margin mode " + IntegerToString(AccountInfoInteger(ACCOUNT_MARGIN_MODE)) +
       " -> " + (here ? "allowed" : "refused") + ": " + why);
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
