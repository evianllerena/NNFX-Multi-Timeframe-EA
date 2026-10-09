//+------------------------------------------------------------------+
//| NNFX_GvTool.mq5                                                  |
//| Test-terminal tool (D-OPS-1): lists, deletes or sets NNFX        |
//| terminal global variables. Only names starting "NNFX_" are       |
//| touched. Writes MQL5\Files\NNFX_GvTool.txt: every NNFX_ variable |
//| before, what was deleted / set, and every NNFX_ variable after.  |
//| Places NO orders.                                                |
//| Status: compiled 2026-10-06 (build 6241, 0 errors, 0 warnings);  |
//| run gv_delete_master_20261006_170258.                            |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

input string InpDelete = "";   // comma-separated names to delete ("" = list only); each must start with NNFX_
// 6f (demo crash test of the drawdown pause, G1_phase6d_1 item 2): comma-separated NAME=value pairs to set, each name
// starting NNFX_ ("" = none). Set after the deletes, then flushed to disk.
input string InpSet    = "";

int g_out = INVALID_HANDLE;

void Out(const string line)
  {
   Print(line);
   if(g_out != INVALID_HANDLE)
      FileWriteString(g_out, line + "\r\n");
  }

void ListAll(const string title)
  {
   Out(title);
   int n = GlobalVariablesTotal(), shown = 0;
   for(int i = 0; i < n; i++)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, "NNFX_") != 0)
         continue;
      Out(StringFormat("  %s = %.10g (last set %s)", name, GlobalVariableGet(name),
                       TimeToString(GlobalVariableTime(name), TIME_DATE | TIME_SECONDS)));
      shown++;
     }
   if(shown == 0)
      Out("  (none)");
  }

void OnStart()
  {
   g_out = FileOpen("NNFX_GvTool.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out(StringFormat("NNFX_GvTool, terminal build %d, account %I64d on %s, server time %s",
                    (int)TerminalInfoInteger(TERMINAL_BUILD), AccountInfoInteger(ACCOUNT_LOGIN),
                    AccountInfoString(ACCOUNT_SERVER), TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS)));
   ListAll("before:");
   string names[];
   int n = (InpDelete == "") ? 0 : StringSplit(InpDelete, ',', names);
   for(int i = 0; i < n; i++)
     {
      string name = names[i];
      StringTrimLeft(name);
      StringTrimRight(name);
      if(StringFind(name, "NNFX_") != 0)
        {
         Out("REFUSED " + name + ": only NNFX_ variables");
         continue;
        }
      if(!GlobalVariableCheck(name))
        {
         Out("not present: " + name);
         continue;
        }
      bool ok = GlobalVariableDel(name);
      Out(StringFormat("DELETED %s: %s", name, ok ? "ok" : "FAILED, error " + IntegerToString(GetLastError())));
     }
   string sets[];
   int m = (InpSet == "") ? 0 : StringSplit(InpSet, ',', sets);
   for(int i = 0; i < m; i++)
     {
      string kv[];
      string item = sets[i];
      StringTrimLeft(item);
      StringTrimRight(item);
      if(StringSplit(item, '=', kv) != 2 || StringFind(kv[0], "NNFX_") != 0)
        {
         Out("REFUSED " + item + ": need NNFX_NAME=value");
         continue;
        }
      bool ok = GlobalVariableSet(kv[0], StringToDouble(kv[1])) > 0;
      Out(StringFormat("SET %s = %s: %s", kv[0], kv[1], ok ? "ok" : "FAILED, error " + IntegerToString(GetLastError())));
     }
   if(n + m > 0)
      GlobalVariablesFlush();
   ListAll("after:");
   Out(StringFormat("RESULT: done (%d names asked to delete, %d to set)", n, m));
   if(g_out != INVALID_HANDLE)
      FileClose(g_out);
  }
//+------------------------------------------------------------------+
