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
//|   (OD-11: news/news_events.txt, approved by the owner).      |
//| InpMode = "export": month by month from InpFrom to InpTo, every  |
//|   calendar value of the 8 currencies whose event matches the     |
//|   approved list (News.mqh NNFXNewsMatch: id or role pattern,     |
//|   D6e-1) -> Common\Files\NNFX\calendar\events_<from>_<to>.txt     |
//|   (time order, in UTC, the News.mqh format) and                  |
//|   MQL5\Files\NNFX\calendar\_summary.txt: one line per month and  |
//|   "RESULT: <m> of <m> months exported, <e> errors".              |
//| InpMode = "compare" (PLAN 6e "Tester gives the same block as     |
//|   live"): for one week, every H1 close of the 5 pairs, the N1    |
//|   block and the X5 flag from the LIVE calendar vs from the       |
//|   exported file (the path the tester uses). RESULT: identical or |
//|   the mismatches.                                                |
//| InpMode = "depth": the earliest January with USD events, 2000 to |
//|   2019 (recorded, not pass/fail).                                |
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
input string InpEventFile  = "NNFX\\calendar\\events_2019.01_2026.09.txt"; // compare: the export (Common\Files)
input string InpWeekStart  = "2026.09.21";                         // compare: Monday of the week (server date)
input string InpPairs      = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY"; // compare: VP's 5 test pairs
input int    InpWinterOffset = 2;                                  // compare: broker clock rule (D6d-4, a setting)
input string InpDst        = "US";                                 // compare: "none", "EU" or "US"

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
   // The calendar gives every past event in TODAY's server offset (run calendar_export_20261006_181154, kept in
   // invalid\: 243 of 246 US releases at exactly +3.00 h, summer and winter). So the file stores UTC = calendar time
   // - the offset now; News.mqh turns UTC into server time per date with the broker's clock rule (Guard.mqh).
   int offsetNow = (int)(TimeTradeServer() - TimeGMT());
   offsetNow = (int)MathRound(offsetNow / 900.0) * 900;   // whole quarter hours
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
   FileWriteString(h, StringFormat("# NNFX news events, generated %s GMT, times in UTC (calendar time - server offset %+.2f h at export), months %s to %s, list %s, %s\r\n",
                                   TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES), offsetNow / 3600.0, InpFrom, InpTo,
                                   InpList, status));
   FileWriteString(h, "time_utc|currency|event_id|name|vp\r\n");
   for(int i = 0; i < n; i++)
      FileWriteString(h, StringFormat("%s|%s|%s|%s|%s\r\n", TimeToString(ev[idx[i]].time, TIME_DATE | TIME_MINUTES),
                                      ev[idx[i]].cur, ev[idx[i]].id, ev[idx[i]].name, ev[idx[i]].vp));
   FileClose(h);
   Out(StringFormat("written Common\\Files\\%s: %d events", name, n));
   Out(StringFormat("RESULT: %d of %d months exported, %d errors", monthsOk, months, errors));
  }

// The live path: the calendar's values around the week, matched to the approved list, calendar time -> UTC (the
// offset now) -> server time with the broker's rule. The same steps as the export plus News.mqh's load, but straight
// from the calendar.
int LiveEvents(string &cur[], const NNFXNewsEntry &entries[], const NNFXBroker &b, const datetime from, const datetime to,
               NNFXNewsEvent &out[])
  {
   ArrayResize(out, 0);
   int offsetNow = (int)MathRound((TimeTradeServer() - TimeGMT()) / 900.0) * 900;
   for(int c = 0; c < ArraySize(cur); c++)
     {
      MqlCalendarValue vals[];
      if(CalendarValueHistory(vals, from, to, NULL, cur[c]) < 0)
         return -1;
      for(int i = 0; i < ArraySize(vals); i++)
        {
         MqlCalendarEvent e;
         if(!CalendarEventById(vals[i].event_id, e))
            return -1;
         string id = StringFormat("%I64u", vals[i].event_id);
         if(NNFXNewsMatch(entries, cur[c], id, e.name) < 0)
            continue;
         int k = ArraySize(out);
         ArrayResize(out, k + 1);
         out[k].time = NNFXUtcToServer(b, vals[i].time - offsetNow);
         out[k].cur = cur[c];
         out[k].id = id;
         out[k].name = e.name;
         out[k].vp = "";
        }
     }
   return ArraySize(out);
  }

void CompareWeek(string &cur[])
  {
   string listLines[];
   NNFXNewsEntry entries[];
   if(!NNFXNewsReadLines(InpList, listLines, false) || NNFXNewsParseList(listLines, entries) == 0)
     {
      Out("RESULT: FAIL (cannot read the event list)");
      return;
     }
   NNFXBroker b;
   b.name = AccountInfoString(ACCOUNT_SERVER);
   b.winter_offset = InpWinterOffset;
   b.dst = InpDst;
   NNFXNewsEvent fromFile[], live[];
   datetime gen;
   int nf = NNFXNewsLoad(InpEventFile, true, b, fromFile, gen);
   datetime w0 = StringToTime(InpWeekStart), w1 = w0 + 7 * 86400;
   int nl = LiveEvents(cur, entries, b, w0 - 2 * 86400, w1 + 2 * 86400, live);
   Out(StringFormat("compare week from %s: %d events in the file, %d live events around the week (rule GMT+%d %s)",
                    InpWeekStart, nf, nl, InpWinterOffset, InpDst));
   if(nf <= 0 || nl < 0)
     {
      Out("RESULT: FAIL (no file events or a calendar error)");
      return;
     }
   string pairs[];
   int np = StringSplit(InpPairs, ',', pairs);
   NNFXBlackout none[];
   int compared = 0, mismatches = 0, blocks = 0, flags = 0;
   for(int k = 0; k < np; k++)
     {
      datetime prev = 0;
      for(datetime tc = w0 + 3600; tc <= w1; tc += 3600)
        {
         MqlDateTime s;
         TimeToStruct(tc - 3600, s);
         if(s.day_of_week == 0 || s.day_of_week == 6)
            continue;   // no candle opens on the weekend
         string wf, wl;
         bool bf = NNFXNewsBlocked(pairs[k], tc, fromFile, none, wf);
         bool bl = NNFXNewsBlocked(pairs[k], tc, live, none, wl);
         bool xf = NNFXNewsFirstClose(pairs[k], tc, prev, fromFile);
         bool xl = NNFXNewsFirstClose(pairs[k], tc, prev, live);
         compared++;
         blocks += bf ? 1 : 0;
         flags += xf ? 1 : 0;
         if(wf != wl || xf != xl)
           {
            mismatches++;
            if(mismatches <= 10)
               Out(StringFormat("MISMATCH %s %s: file [%s] X5 %d, live [%s] X5 %d", pairs[k],
                                TimeToString(tc, TIME_DATE | TIME_MINUTES), wf, xf ? 1 : 0, wl, xl ? 1 : 0));
           }
         prev = tc;
        }
     }
   Out(StringFormat("compared %d H1 closes of %d pairs: %d blocked by N1, %d X5 first closes", compared, np, blocks, flags));
   Out(mismatches == 0 ? StringFormat("RESULT: identical (0 mismatches, %d candle closes compared)", compared)
                       : StringFormat("RESULT: FAIL (%d mismatches)", mismatches));
  }

void Depth(void)
  {
   int first = 0;
   for(int y = 2000; y <= 2019; y++)
     {
      MqlCalendarValue vals[];
      int n = CalendarValueHistory(vals, StringToTime(StringFormat("%d.01.01", y)), StringToTime(StringFormat("%d.02.01", y)) - 1, NULL, "USD");
      Out(StringFormat("January %d: %d USD values", y, n));
      if(n > 0 && first == 0)
         first = y;
     }
   Out(first > 0 ? StringFormat("RESULT: earliest January with USD events: %d (recorded, not pass/fail)", first)
                 : "RESULT: no USD events 2000-2019");
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
   else if(InpMode == "compare")
      CompareWeek(cur);
   else if(InpMode == "depth")
      Depth();
   else
      Out("RESULT: FAIL (unknown mode " + InpMode + ")");
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
