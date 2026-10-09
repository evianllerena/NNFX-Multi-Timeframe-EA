//+------------------------------------------------------------------+
//| CalendarExport.mqh - MT5's economic calendar to the News.mqh     |
//| event file (Phase 6e export, moved here in 6f unchanged so the   |
//| script NNFX_CalendarExport and the EA run the SAME code).        |
//|                                                                  |
//| NNFXCalendarExport: month by month from `from` to `to` (months), |
//| every calendar value of the currencies whose event matches the   |
//| approved list (NNFXNewsMatch: id or role pattern, D6e-1), in     |
//| time order, times in UTC (calendar time - the server offset now: |
//| the calendar gives history in TODAY's offset), written to        |
//| Common\Files\<outName>. The list must be "# STATUS: APPROVED"    |
//| (OD-11). Live chart only: the calendar functions are not allowed |
//| in the Strategy Tester (error 4014). Places NO orders.           |
//| Live use by NNFX_EA (OD-12): at start and every day, the file    |
//| events_live.txt from last month to next month; read back with    |
//| NNFXNewsLoad, the same path as the tester (DESIGN_6F) [C].       |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_CALENDAREXPORT_MQH
#define NNFX_CALENDAREXPORT_MQH

#include <NNFX\News.mqh>

datetime NNFXMonthStart(const string ym)
  {
   return StringToTime(ym + ".01 00:00");
  }

datetime NNFXNextMonth(const datetime m)
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

string NNFXMonthText(const datetime m) { return StringSubstr(TimeToString(m, TIME_DATE), 0, 7); }

void NNFXAddLine(string &lines[], const string s)
  {
   int n = ArraySize(lines);
   ArrayResize(lines, n + 1);
   lines[n] = s;
  }

// Returns the number of events written, or -1 (why in log[]). log[]: one line per step and per month, as the script
// prints them. monthsOk / months / errors: as the script's RESULT line.
int NNFXCalendarExport(const string listPath, const string &cur[], const datetime firstMonth, const datetime lastMonth,
                       const string outName, string &log[], int &monthsOk, int &months, int &errors)
  {
   ArrayResize(log, 0);
   monthsOk = 0;
   months = 0;
   errors = 0;
   string listLines[];
   NNFXNewsEntry entries[];
   if(!NNFXNewsReadLines(listPath, listLines, false) || NNFXNewsParseList(listLines, entries) == 0)
     {
      NNFXAddLine(log, "RESULT: FAIL (cannot read the event list " + listPath + ")");
      return -1;
     }
   string status = "";
   for(int i = 0; i < ArraySize(listLines); i++)
      if(StringFind(listLines[i], "# STATUS:") == 0)
         status = StringSubstr(listLines[i], 2);
   NNFXAddLine(log, StringFormat("event list %s: %d entries; %s", listPath, ArraySize(entries), status));
   if(StringFind(status, "STATUS: APPROVED") != 0)
     {
      NNFXAddLine(log, "RESULT: FAIL (the event list is not approved, OD-11)");
      return -1;
     }
   // The calendar gives every past event in TODAY's server offset (run calendar_export_20261006_181154, kept in
   // invalid\: 243 of 246 US releases at exactly +3.00 h, summer and winter). So the file stores UTC = calendar time
   // - the offset now; News.mqh turns UTC into server time per date with the broker's clock rule (Guard.mqh).
   int offsetNow = (int)(TimeTradeServer() - TimeGMT());
   offsetNow = (int)MathRound(offsetNow / 900.0) * 900;   // whole quarter hours
   NNFXNewsEvent ev[];
   for(datetime m = firstMonth; m <= lastMonth; m = NNFXNextMonth(m))
     {
      months++;
      int found = 0, errs = 0;
      for(int c = 0; c < ArraySize(cur); c++)
        {
         MqlCalendarValue vals[];
         ResetLastError();
         // one month at a time (SPEC: longer requests can time out)
         if(CalendarValueHistory(vals, m, NNFXNextMonth(m) - 1, NULL, cur[c]) < 0)
           {
            errs++;
            NNFXAddLine(log, StringFormat("%s %s: CalendarValueHistory error %d", TimeToString(m, TIME_DATE), cur[c], GetLastError()));
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
            ev[j].time = vals[i].time - offsetNow;   // UTC
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
      NNFXAddLine(log, StringFormat("month %s: %d events, %d errors", NNFXMonthText(m), found, errs));
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
   FolderCreate("NNFX\\calendar", FILE_COMMON);
   // written to a .tmp file and moved over the old one, so a reader never sees half a file
   string tmp = outName + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
     {
      NNFXAddLine(log, "RESULT: FAIL (cannot write Common\\Files\\" + outName + ")");
      return -1;
     }
   FileWriteString(h, StringFormat("# NNFX news events, generated %s GMT, times in UTC (calendar time - server offset %+.2f h at export), months %s to %s, list %s, %s\r\n",
                                   TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES), offsetNow / 3600.0,
                                   NNFXMonthText(firstMonth), NNFXMonthText(lastMonth), listPath, status));
   FileWriteString(h, "time_utc|currency|event_id|name|vp\r\n");
   for(int i = 0; i < n; i++)
      FileWriteString(h, StringFormat("%s|%s|%s|%s|%s\r\n", TimeToString(ev[idx[i]].time, TIME_DATE | TIME_MINUTES),
                                      ev[idx[i]].cur, ev[idx[i]].id, ev[idx[i]].name, ev[idx[i]].vp));
   FileClose(h);
   if(!FileMove(tmp, FILE_COMMON, outName, FILE_COMMON | FILE_REWRITE))
     {
      NNFXAddLine(log, StringFormat("RESULT: FAIL (cannot move the new file over Common\\Files\\%s, error %d)", outName, GetLastError()));
      return -1;
     }
   NNFXAddLine(log, StringFormat("written Common\\Files\\%s: %d events", outName, n));
   NNFXAddLine(log, StringFormat("RESULT: %d of %d months exported, %d errors", monthsOk, months, errors));
   return n;
  }

#endif
