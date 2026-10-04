//+------------------------------------------------------------------+
//| Connection.mqh - wait until the terminal is logged in            |
//|                                                                  |
//| A script started from a /config file can begin before MT5 has    |
//| logged in to the account. Until then account and symbol          |
//| properties read as defaults (balance 0, netting, tick value 0),  |
//| so a script that reads server data must call NNFXWaitConnected   |
//| first and refuse to report if it returns false.                  |
//|                                                                  |
//| Ready means all three are true (G1_phase5_1 review, F1):         |
//|  - TerminalInfoInteger(TERMINAL_CONNECTED) is true               |
//|  - AccountInfoInteger(ACCOUNT_LOGIN) is not 0                    |
//|  - SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE) > 0 for every  |
//|    listed pair                                                   |
//|                                                                  |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_CONNECTION_MQH
#define NNFX_CONNECTION_MQH

// The exact line a script writes when the wait runs out; the runner counts it as FAIL.
#define NNFX_RESULT_NOT_CONNECTED "RESULT: INVALID (not connected)"

// Waits up to timeoutSec seconds. Empty entries in syms[] are ignored; every other entry is
// added to Market Watch (needed to read its properties). On return, `detail` says what was
// seen: how long the wait took, or which condition was still false when it ran out.
bool NNFXWaitConnected(const string &syms[], const int timeoutSec, string &detail)
  {
   uint start = GetTickCount();
   string missing = "";
   while(!IsStopped())
     {
      missing = "";
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
         missing += " terminal_not_connected";
      if(AccountInfoInteger(ACCOUNT_LOGIN) == 0)
         missing += " no_account_login";
      for(int i = 0; i < ArraySize(syms); i++)
        {
         if(syms[i] == "")
            continue;
         if(!SymbolSelect(syms[i], true))
            missing += " " + syms[i] + "_not_found";
         else if(!(SymbolInfoDouble(syms[i], SYMBOL_TRADE_TICK_VALUE) > 0.0))
            missing += " " + syms[i] + "_tick_value_0";
        }
      double waited = (GetTickCount() - start) / 1000.0;
      if(missing == "")
        {
         detail = StringFormat("connected and logged in, tick value > 0 on every pair (waited %.1f s)", waited);
         return true;
        }
      if(waited >= timeoutSec)
         break;
      Sleep(250);
     }
   detail = StringFormat("still missing after %.1f s:%s", (GetTickCount() - start) / 1000.0,
                         missing == "" ? " script stopped" : missing);
   return false;
  }

#endif
