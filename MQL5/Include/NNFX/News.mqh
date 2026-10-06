//+------------------------------------------------------------------+
//| News.mqh - N1 / N2 / X5 from an exported event file (Phase 6e)   |
//| Port of tests/python/nnfx_ref/news.py, function for function.    |
//|                                                                  |
//| One code path for the tester and live (SPEC, News filter): both  |
//| read the event file written by NNFX_CalendarExport (the calendar |
//| functions are not allowed in the tester). Live, the file is      |
//| refreshed daily; older than 24 h -> alarm (OD-12).               |
//|                                                                  |
//|  N1  (owner rule D6e-3) per event: from the EARLIER of 24 h      |
//|      before it and 15:00 New York on the previous trading day,   |
//|      until the 17:00 New York close that ends its trading day;   |
//|      a close t is blocked when start <= t < end (an event at a   |
//|      candle close is inside; trading resumes AT the 17:00 close) |
//|  N2  owner's blackout list from the preset (OD-19) -> blocked    |
//|  X5  flag at the FIRST candle close inside an event's block      |
//|      (I-10), using the actual previous close (weekends)          |
//| Matching (D6e-1, R-15): id in the entry's ids OR the name fits   |
//| its role pattern ("*" = any text): a new chair is still caught.  |
//|                                                                  |
//| Event file (pipe-separated, times in UTC):                       |
//|   # NNFX news events, generated YYYY.MM.DD HH:MM GMT, ...        |
//|   time_utc|currency|event_id|name|vp                             |
//|   2026.06.05 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm ...   |
//| NNFXNewsLoad turns UTC into the broker's server time for each    |
//| date with its clock rule (Guard.mqh, D6d-4): the calendar gives  |
//| history in TODAY's offset, so the file cannot hold server time.  |
//| Never TimeLocal (D6d-4). No trading calls.                       |
//| Status: compiled 2026-10-06 (build 6241, 0 errors, 0 warnings);  |
//| NewsTest 61/61 with D6e-3; planted bugs 11 of 11 (N1-N11).       |
//+------------------------------------------------------------------+
#ifndef NNFX_NEWS_MQH
#define NNFX_NEWS_MQH

#include <NNFX\Guard.mqh>

#define NNFX_NEWS_WINDOW (24 * 3600)

struct NNFXNewsEntry
  {
   string            cur;
   string            vp;
   string            pattern;
   string            ids;      // ",id1,id2," (commas around each, for an exact search)
  };

struct NNFXNewsEvent
  {
   datetime          time;
   string            cur;
   string            id;
   string            name;
   string            vp;
  };

struct NNFXBlackout
  {
   string            cur;
   datetime          start;    // 00:00 of the first day
   datetime          end;      // 23:59 of the last day
  };

// "*" matches any text (possibly empty); everything else must match exactly (case-sensitive, like fnmatchcase)
bool NNFXGlob(const string s, const string p, const int si = 0, const int pi = 0)
  {
   int ns = StringLen(s), np = StringLen(p);
   if(pi == np)
      return si == ns;
   ushort c = StringGetCharacter(p, pi);
   if(c == '*')
     {
      for(int k = si; k <= ns; k++)
         if(NNFXGlob(s, p, k, pi + 1))
            return true;
      return false;
     }
   return si < ns && StringGetCharacter(s, si) == c && NNFXGlob(s, p, si + 1, pi + 1);
  }

// news/news_events.txt lines: EVENT|currency|vp|pattern|id1,id2
int NNFXNewsParseList(const string &lines[], NNFXNewsEntry &out[])
  {
   ArrayResize(out, 0);
   for(int i = 0; i < ArraySize(lines); i++)
     {
      if(StringFind(lines[i], "EVENT|") != 0)
         continue;
      string p[];
      if(StringSplit(lines[i], '|', p) != 5)
         continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k].cur = p[1];
      out[k].vp = p[2];
      out[k].pattern = p[3];
      out[k].ids = "," + p[4] + ",";
     }
   return ArraySize(out);
  }

// index of the matching entry, -1 if the event is not one of VP's
int NNFXNewsMatch(const NNFXNewsEntry &entries[], const string cur, const string id, const string name)
  {
   for(int i = 0; i < ArraySize(entries); i++)
      if(entries[i].cur == cur && (StringFind(entries[i].ids, "," + id + ",") >= 0 || NNFXGlob(name, entries[i].pattern)))
         return i;
   return -1;
  }

bool NNFXNewsReadLines(const string path, string &lines[], const bool common)
  {
   ArrayResize(lines, 0);
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | (common ? FILE_COMMON : 0));
   if(h == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(h))
     {
      string s = FileReadString(h);
      StringTrimRight(s);
      int k = ArraySize(lines);
      ArrayResize(lines, k + 1);
      lines[k] = s;
     }
   FileClose(h);
   return true;
  }

// The export file: events in time order, each time turned from UTC into the broker's server time (its clock rule
// for that date). Returns the count, -1 if it cannot be read. generatedGmt from line 1.
int NNFXNewsLoad(const string path, const bool common, const NNFXBroker &broker, NNFXNewsEvent &out[], datetime &generatedGmt)
  {
   ArrayResize(out, 0);
   generatedGmt = 0;
   string lines[];
   if(!NNFXNewsReadLines(path, lines, common))
      return -1;
   for(int i = 0; i < ArraySize(lines); i++)
     {
      string s = lines[i];
      if(StringFind(s, "#") == 0)
        {
         int g = StringFind(s, "generated ");
         if(g >= 0)
            generatedGmt = StringToTime(StringSubstr(s, g + 10, 16));
         continue;
        }
      string p[];
      if(StringSplit(s, '|', p) != 5 || p[0] == "time_utc")
         continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k].time = NNFXUtcToServer(broker, StringToTime(p[0]));
      out[k].cur = p[1];
      out[k].id = p[2];
      out[k].name = p[3];
      out[k].vp = p[4];
     }
   return ArraySize(out);
  }

// OD-12: live, the file must be refreshed daily. Age in hours from the file's own "generated ... GMT" line and
// TimeGMT() (never the PC clock, D6d-4); -1 if the file has no such line.
double NNFXNewsAgeHours(const datetime generatedGmt)
  {
   if(generatedGmt <= 0)
      return -1.0;
   return (double)(TimeGMT() - generatedGmt) / 3600.0;
  }

// Preset text "CUR:YYYY.MM.DD-YYYY.MM.DD;CUR:..." ("" = none, OD-19). Returns the count, -1 on a malformed item.
int NNFXParseBlackouts(const string text, NNFXBlackout &out[])
  {
   ArrayResize(out, 0);
   string items[];
   int n = StringSplit(text, ';', items);
   for(int i = 0; i < n; i++)
     {
      string it = items[i];
      StringTrimLeft(it);
      StringTrimRight(it);
      if(it == "")
         continue;
      string cs[], ds[];
      if(StringSplit(it, ':', cs) != 2 || StringSplit(cs[1], '-', ds) != 2)
         return -1;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k].cur = cs[0];
      StringToUpper(out[k].cur);
      out[k].start = StringToTime(ds[0]);
      out[k].end = StringToTime(ds[1]) + 23 * 3600 + 59 * 60;
     }
   return ArraySize(out);
  }

// New York wall clock <-> UTC (US daylight saving: EDT from the 2nd Sunday of March 07:00 UTC to the 1st Sunday of
// November 06:00 UTC). nyToUtc is used for 15:00 and 17:00 only, never in the changeover hour.
datetime NNFXUtcToNy(const datetime u)
  {
   datetime s, e;
   NNFXUsDstDates(NNFXYear(u), s, e);
   bool edt = (u >= s + 7 * 3600 && u < e + 6 * 3600);
   return u - (edt ? 4 : 5) * 3600;
  }

datetime NNFXNyToUtc(const datetime ny)
  {
   datetime s, e;
   NNFXUsDstDates(NNFXYear(ny), s, e);
   datetime d = NNFXDayOf(ny);
   return ny + ((d >= s && d < e) ? 4 : 5) * 3600;
  }

// D6e-3: the block of one event (server time): [start, end). The news day is the trading day the event falls in
// (17:00-17:00 New York; an event at exactly 17:00 starts a new day; a day ending on a weekend ends on Monday).
// start = the EARLIER of 15:00 New York on the previous trading day (the weekday before the close date) and 24 h
// before the event; end = the 17:00 New York close of the news day.
void NNFXNewsBlockWindow(const datetime eServer, const NNFXBroker &b, datetime &start, datetime &end)
  {
   datetime u = NNFXServerToUtc(b, eServer);
   datetime ny = NNFXUtcToNy(u);
   datetime closeDate = NNFXDayOf(ny);
   if(ny - closeDate >= 17 * 3600)
      closeDate += 86400;
   while(NNFXDow(closeDate) == 0 || NNFXDow(closeDate) == 6)
      closeDate += 86400;
   datetime prev = closeDate - 86400;
   while(NNFXDow(prev) == 0 || NNFXDow(prev) == 6)
      prev -= 86400;
   datetime a = NNFXNyToUtc(prev + 15 * 3600);
   datetime c = u - NNFX_NEWS_WINDOW;
   start = NNFXUtcToServer(b, MathMin(a, c));
   end = NNFXUtcToServer(b, NNFXNyToUtc(closeDate + 17 * 3600));
  }

bool NNFXNewsInBlock(const datetime t, const datetime eServer, const NNFXBroker &b)
  {
   datetime s, e;
   NNFXNewsBlockWindow(eServer, b, s, e);
   return t >= s && t < e;
  }

bool NNFXPairHas(const string sym, const string cur)
  {
   string s = sym;
   StringToUpper(s);
   return StringSubstr(s, 0, 3) == cur || StringSubstr(s, 3, 3) == cur;
  }

// N1 + N2 at the candle close t; why = the reasons, ";"-separated (same text as news.py)
bool NNFXNewsBlocked(const string sym, const datetime t, const NNFXNewsEvent &ev[], const NNFXBroker &b,
                     const NNFXBlackout &bo[], string &why)
  {
   why = "";
   for(int i = 0; i < ArraySize(ev); i++)
      if(NNFXPairHas(sym, ev[i].cur) && NNFXNewsInBlock(t, ev[i].time, b))
         why += (why == "" ? "" : ";") + "N1 " + ev[i].cur + " " + ev[i].name + " " + TimeToString(ev[i].time, TIME_DATE | TIME_MINUTES);
   for(int i = 0; i < ArraySize(bo); i++)
      if(NNFXPairHas(sym, bo[i].cur) && t >= bo[i].start && t <= bo[i].end)
         why += (why == "" ? "" : ";") + "N2 " + bo[i].cur;
   return why != "";
  }

// X5 / I-10 with D6e-3: the first candle close inside some event's block. prevT = the previous ACTUAL close (0 = none)
bool NNFXNewsFirstClose(const string sym, const datetime t, const datetime prevT, const NNFXNewsEvent &ev[],
                        const NNFXBroker &b)
  {
   for(int i = 0; i < ArraySize(ev); i++)
      if(NNFXPairHas(sym, ev[i].cur) && NNFXNewsInBlock(t, ev[i].time, b) && (prevT == 0 || !NNFXNewsInBlock(prevT, ev[i].time, b)))
         return true;
   return false;
  }

#endif
