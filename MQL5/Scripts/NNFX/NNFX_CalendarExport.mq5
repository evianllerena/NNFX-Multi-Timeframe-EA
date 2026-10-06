//+------------------------------------------------------------------+
//| NNFX_CalendarExport.mq5                                          |
//| Phase 6e: MT5's economic calendar to files the EA can read in    |
//| the tester and live alike (SPEC, News filter). Live chart only:  |
//| the calendar functions are not allowed in the tester (4014).     |
//| Waits for login (Connection.mqh). Places NO orders.              |
//|                                                                  |
//| InpMode = "list": the event catalogue. For each of the 8         |
//|   currencies, every calendar event (id, name, importance, type,  |
//|   sector, frequency) -> MQL5\Files\NNFX\calendar\events_list.csv |
//|   Used once, to map VP's event list to the calendar's own names  |
//|   (OD-11: profiles/news_events.txt, approved by the owner).      |
//| InpMode = "export": (built after the mapping is approved)        |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\Connection.mqh>

input string InpMode       = "list";                               // "list" (catalogue)
input string InpCurrencies = "USD,EUR,GBP,CAD,AUD,NZD,JPY,CHF";    // VP's 8 currencies (rulebook)

int g_report = INVALID_HANDLE;

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

string Csv(string s)
  {
   StringReplace(s, "\"", "'");
   return "\"" + s + "\"";
  }

void ListEvents(string &cur[])
  {
   int h = FileOpen("NNFX\\calendar\\events_list.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Out("RESULT: FAIL (cannot write NNFX\\calendar\\events_list.csv, error " + IntegerToString(GetLastError()) + ")");
      return;
     }
   FileWriteString(h, "currency,event_id,name,importance,type,sector,frequency,code\r\n");
   int total = 0, errors = 0;
   for(int c = 0; c < ArraySize(cur); c++)
     {
      MqlCalendarEvent ev[];
      ResetLastError();
      int n = CalendarEventByCurrency(cur[c], ev);
      if(n < 0)
        {
         errors++;
         Out(StringFormat("%s: CalendarEventByCurrency error %d", cur[c], GetLastError()));
         continue;
        }
      int high = 0;
      for(int i = 0; i < n; i++)
        {
         FileWriteString(h, StringFormat("%s,%I64u,%s,%s,%s,%s,%s,%s\r\n", cur[c], ev[i].id, Csv(ev[i].name),
                                         EnumToString(ev[i].importance), EnumToString(ev[i].type),
                                         EnumToString(ev[i].sector), EnumToString(ev[i].frequency), Csv(ev[i].event_code)));
         if(ev[i].importance == CALENDAR_IMPORTANCE_HIGH)
            high++;
        }
      total += n;
      Out(StringFormat("%s: %d events (%d of high importance)", cur[c], n, high));
     }
   FileClose(h);
   Out(StringFormat("RESULT: %d events listed for %d currencies, %d errors", total, ArraySize(cur), errors));
  }

void OnStart()
  {
   FolderCreate("NNFX\\calendar");
   g_report = FileOpen("NNFX\\calendar\\_summary.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out(StringFormat("NNFX_CalendarExport, mode %s, terminal build %d", InpMode, (int)TerminalInfoInteger(TERMINAL_BUILD)));
   string cur[];
   StringSplit(InpCurrencies, ',', cur);
   string detail, none[];   // the currencies are not symbols: wait for the login only
   if(!NNFXWaitConnected(none, 120, detail))
     {
      Out(NNFX_RESULT_NOT_CONNECTED + " " + detail);
      FileClose(g_report);
      return;
     }
   Out("connection: " + detail);
   Out(StringFormat("server time %s, GMT %s", TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS),
                    TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS)));
   if(InpMode == "list")
      ListEvents(cur);
   else
      Out("RESULT: FAIL (mode " + InpMode + " not built yet)");
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
