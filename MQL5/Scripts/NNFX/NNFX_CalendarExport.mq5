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
//| InpMode = "export": month by month from InpFrom to InpTo, every  |
//|   calendar value of the 8 currencies whose event matches the     |
//|   approved list (News.mqh NNFXNewsMatch: id or role pattern,     |
//|   D6e-1) -> Common\Files\NNFX\calendar\events_<from>_<to>.txt     |
//|   (time order, server time, the News.mqh format) and             |
//|   MQL5\Files\NNFX\calendar\_summary.txt: one line per month and  |
//|   "RESULT: <m> of <m> months exported, <e> errors".              |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\Connection.mqh>
#include <NNFX\News.mqh>

input string InpMode       = "list";                               // "list" (catalogue)
input string InpCurrencies = "USD,EUR,GBP,CAD,AUD,NZD,JPY,CHF";    // VP's 8 currencies (rulebook)
input string InpList       = "NNFX\\news\\news_events.txt";         // export: the approved list (MQL5\Files)
input string InpFrom       = "2019.01";                            // export: first month (YYYY.MM)
input string InpTo         = "2026.09";                            // export: last month (YYYY.MM)

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

datetime MonthStart(const string ym)
  {
   return StringToTime(ym + ".01 00:00");
  }

datetime NextMonth(const datetime m)
  {
   MqlDateTime s;
   TimeToStruct(m, s);
   s.mon++;
   if(s.mon > 12)
     {
      s.mon = 1;
      s.year++;
     }
   s.day = 1;
   s.hour = 0;
   s.min = 0;
   s.sec = 0;
   return StructToTime(s);
  }

void ExportEvents(string &cur[])
  {
   string listLines[];
   NNFXNewsEntry entries[];
   if(!NNFXNewsReadLines(InpList, listLines, false) || NNFXNewsParseList(listLines, entries) == 0)
     {
      Out("RESULT: FAIL (cannot read the event list " + InpList + ")");
      return;
     }
   string status = "";
   for(int i = 0; i < ArraySize(listLines); i++)
      if(StringFind(listLines[i], "# STATUS:") == 0)
         status = StringSubstr(listLines[i], 2);
   Out(StringFormat("event list %s: %d entries; %s", InpList, ArraySize(entries), status));
   if(StringFind(status, "STATUS: APPROVED") != 0)
     {
      Out("RESULT: FAIL (the event list is not approved, OD-11)");
      return;
     }
   NNFXNewsEvent ev[];
   int months = 0, monthsOk = 0, errors = 0;
   datetime first = MonthStart(InpFrom), last = MonthStart(InpTo);
   for(datetime m = first; m <= last; m = NextMonth(m))
     {
      months++;
      int found = 0, errs = 0;
      for(int c = 0; c < ArraySize(cur); c++)
        {
         MqlCalendarValue vals[];
         ResetLastError();
         // one month at a time (SPEC: longer requests can time out)
         if(CalendarValueHistory(vals, m, NextMonth(m) - 1, NULL, cur[c]) < 0)
           {
            errs++;
            Out(StringFormat("%s %s: CalendarValueHistory error %d", TimeToString(m, TIME_DATE), cur[c], GetLastError()));
            continue;
           }
         for(int i = 0; i < ArraySize(vals); i++)
           {
            MqlCalendarEvent e;
            if(!CalendarEventById(vals[i].event_id, e))
              {
               errs++;
               continue;
              }
            string id = StringFormat("%I64u", vals[i].event_id);
            int k = NNFXNewsMatch(entries, cur[c], id, e.name);
            if(k < 0)
               continue;
            int j = ArraySize(ev);
            ArrayResize(ev, j + 1);
            ev[j].time = vals[i].time;
            ev[j].cur = cur[c];
            ev[j].id = id;
            ev[j].name = e.name;
            ev[j].vp = entries[k].vp;
            found++;
           }
        }
      errors += errs;
      if(errs == 0)
         monthsOk++;
      Out(StringFormat("month %s: %d events, %d errors", StringSubstr(TimeToString(m, TIME_DATE), 0, 7), found, errs));
     }
   // time order (insertion sort on an index; a few thousand rows)
   int n = ArraySize(ev);
   int idx[];
   ArrayResize(idx, n);
   for(int i = 0; i < n; i++)
     {
      idx[i] = i;
      for(int j = i; j > 0 && (ev[idx[j - 1]].time > ev[idx[j]].time ||
                                (ev[idx[j - 1]].time == ev[idx[j]].time && ev[idx[j - 1]].cur + ev[idx[j - 1]].id > ev[idx[j]].cur + ev[idx[j]].id)); j--)
        {
         int x = idx[j];
         idx[j] = idx[j - 1];
         idx[j - 1] = x;
        }
     }
   string name = StringFormat("NNFX\\calendar\\events_%s_%s.txt", InpFrom, InpTo);
   FolderCreate("NNFX\\calendar", FILE_COMMON);
   int h = FileOpen(name, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      Out("RESULT: FAIL (cannot write Common\\Files\\" + name + ")");
      return;
     }
   FileWriteString(h, StringFormat("# NNFX news events, generated %s GMT, server - GMT %+.2f h, months %s to %s, list %s, %s\r\n",
                                   TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES),
                                   (double)(TimeTradeServer() - TimeGMT()) / 3600.0, InpFrom, InpTo, InpList, status));
   FileWriteString(h, "time|currency|event_id|name|vp\r\n");
   for(int i = 0; i < n; i++)
      FileWriteString(h, StringFormat("%s|%s|%s|%s|%s\r\n", TimeToString(ev[idx[i]].time, TIME_DATE | TIME_MINUTES),
                                      ev[idx[i]].cur, ev[idx[i]].id, ev[idx[i]].name, ev[idx[i]].vp));
   FileClose(h);
   Out(StringFormat("written Common\\Files\\%s: %d events", name, n));
   Out(StringFormat("RESULT: %d of %d months exported, %d errors", monthsOk, months, errors));
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
   else if(InpMode == "export")
      ExportEvents(cur);
   else
      Out("RESULT: FAIL (unknown mode " + InpMode + ")");
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
