//+------------------------------------------------------------------+
//| News.mqh - N1 / N2 / X5 from an exported event file (Phase 6e)   |
//| Port of tests/python/nnfx_ref/news.py, function for function.    |
//|                                                                  |
//| One code path for the tester and live (SPEC, News filter): both  |
//| read the event file written by NNFX_CalendarExport (the calendar |
//| functions are not allowed in the tester). Live, the file is      |
//| refreshed daily; older than 24 h -> alarm (OD-12).               |
//|                                                                  |
//|  N1  t < e <= t + 24 h on either currency of the pair -> blocked |
//|  N2  owner's blackout list from the preset (OD-19) -> blocked    |
//|  X5  flag at the FIRST candle close inside an event's window     |
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
//| Status: not yet compiled.                                        |
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

bool NNFXNewsInWindow(const datetime t, const datetime e) { return t < e && e <= t + NNFX_NEWS_WINDOW; }

bool NNFXPairHas(const string sym, const string cur)
  {
   string s = sym;
   StringToUpper(s);
   return StringSubstr(s, 0, 3) == cur || StringSubstr(s, 3, 3) == cur;
  }

// N1 + N2 at the candle close t; why = the reasons, ";"-separated (same text as news.py)
bool NNFXNewsBlocked(const string sym, const datetime t, const NNFXNewsEvent &ev[], const NNFXBlackout &bo[], string &why)
  {
   why = "";
   for(int i = 0; i < ArraySize(ev); i++)
      if(NNFXPairHas(sym, ev[i].cur) && NNFXNewsInWindow(t, ev[i].time))
         why += (why == "" ? "" : ";") + "N1 " + ev[i].cur + " " + ev[i].name + " " + TimeToString(ev[i].time, TIME_DATE | TIME_MINUTES);
   for(int i = 0; i < ArraySize(bo); i++)
      if(NNFXPairHas(sym, bo[i].cur) && t >= bo[i].start && t <= bo[i].end)
         why += (why == "" ? "" : ";") + "N2 " + bo[i].cur;
   return why != "";
  }

// X5 / I-10: the first candle close inside some event's window. prevT = the previous ACTUAL close (0 = none seen)
bool NNFXNewsFirstClose(const string sym, const datetime t, const datetime prevT, const NNFXNewsEvent &ev[])
  {
   for(int i = 0; i < ArraySize(ev); i++)
      if(NNFXPairHas(sym, ev[i].cur) && NNFXNewsInWindow(t, ev[i].time) && (prevT == 0 || !NNFXNewsInWindow(prevT, ev[i].time)))
         return true;
   return false;
  }

#endif
