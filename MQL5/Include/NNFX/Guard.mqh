//+------------------------------------------------------------------+
//| Guard.mqh - switches and limits that block NEW entries (6d)      |
//| Port of tests/python/nnfx_ref/guard.py, function for function.   |
//| Open trades keep being managed whatever the guard says (S-2).    |
//|                                                                  |
//| Block reasons, in this fixed order, comma separated:             |
//|   master     terminal global variable NNFX_MASTER; missing = OFF |
//|   instance   this instance's switch                              |
//|   drawdown   equity <= 90% of the peak (R-12, OD-2); hand reset  |
//|   dailyloss  day's closed P/L <= -3 x risk % (S-5, OD-3 update)  |
//|   rollover   [boundary - 15 min, boundary + 60 min) (R-10)       |
//|   weekend    last N hours before the Friday boundary; 0 = off    |
//|   spread     spread > max spread; max 0 = off                    |
//|   indicator  an indicator failed on this pair                    |
//|                                                                  |
//| Trading day boundary = 17:00 New York in server time (OD-3       |
//| update, owner 2026-10-06), never server midnight. New York       |
//| follows US daylight saving; the server follows the broker's rule |
//| (a setting: winter offset + "none"/"EU"/"US"). Pure functions    |
//| take server times; nothing here reads the clock. Never          |
//| TimeLocal() (D6d-4). No trading calls.                           |
//| Status: compiled 2026-10-06 (build 6241, 0 errors, 0 warnings);  |
//| GuardTest 56/56; planted bugs 9 of 9 (G1-G9).                    |
//+------------------------------------------------------------------+
#ifndef NNFX_GUARD_MQH
#define NNFX_GUARD_MQH

#define NNFX_GUARD_ROLL_BEFORE (15 * 60)
#define NNFX_GUARD_ROLL_AFTER  (60 * 60)
#define NNFX_GUARD_DD_PAUSE    0.10
#define NNFX_GUARD_DL_X        3.0
#define NNFX_GV_MASTER         "NNFX_MASTER"        // 1 = on, 0 = off; missing = off
#define NNFX_GV_DD_PEAK        "NNFX_DD_PEAK"       // shared by all instances (account-wide)
#define NNFX_GV_DD_PAUSED      "NNFX_DD_PAUSED"
#define NNFX_GV_DD_RESET       "NNFX_DD_RESET"      // the owner sets 1 to reset the pause by hand (S-6)

struct NNFXBroker
  {
   string            name;
   int               winter_offset;   // hours east of UTC outside daylight saving
   string            dst;             // "none", "EU" or "US"
  };

datetime NNFXGuardDate(const int y, const int m, const int d, const int h = 0)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year = y;
   s.mon = m;
   s.day = d;
   s.hour = h;
   return StructToTime(s);
  }

datetime NNFXDayOf(const datetime t) { return t - (t % 86400); }

int NNFXDow(const datetime t)          // 0 = Sunday ... 6 = Saturday
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day_of_week;
  }

int NNFXYear(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.year;
  }

datetime NNFXNthSunday(const int y, const int m, const int n)
  {
   datetime d = NNFXGuardDate(y, m, 1);
   d += ((7 - NNFXDow(d)) % 7) * 86400;
   return d + (n - 1) * 7 * 86400;
  }

datetime NNFXLastSunday(const int y, const int m)
  {
   datetime d = (m == 12 ? NNFXGuardDate(y + 1, 1, 1) : NNFXGuardDate(y, m + 1, 1)) - 86400;
   return d - NNFXDow(d) * 86400;
  }

// US: 2nd Sunday of March to 1st Sunday of November; EU: last Sunday of March to last Sunday of October (dates)
void NNFXUsDstDates(const int y, datetime &s, datetime &e) { s = NNFXNthSunday(y, 3, 2); e = NNFXNthSunday(y, 11, 1); }
void NNFXEuDstDates(const int y, datetime &s, datetime &e) { s = NNFXLastSunday(y, 3); e = NNFXLastSunday(y, 10); }

bool NNFXDstActive(const string rule, const datetime utc, bool &ok)
  {
   ok = true;
   datetime s, e;
   if(rule == "none")
      return false;
   if(rule == "EU")
     {
      NNFXEuDstDates(NNFXYear(utc), s, e);
      return utc >= s + 3600 && utc < e + 3600;
     }
   if(rule == "US")
     {
      NNFXUsDstDates(NNFXYear(utc), s, e);
      return utc >= s + 7 * 3600 && utc < e + 6 * 3600;
     }
   ok = false;   // unknown rule
   return false;
  }

int NNFXServerOffset(const NNFXBroker &b, const datetime utc)
  {
   bool ok;
   return (b.winter_offset + (NNFXDstActive(b.dst, utc, ok) ? 1 : 0)) * 3600;
  }

datetime NNFXServerToUtc(const NNFXBroker &b, const datetime t)
  {
   for(int h = b.winter_offset + 1; h >= b.winter_offset; h--)
     {
      datetime u = t - h * 3600;
      if(NNFXServerOffset(b, u) == h * 3600)
         return u;
     }
   return t - b.winter_offset * 3600;   // the skipped hour of a spring change
  }

datetime NNFXUtcToServer(const NNFXBroker &b, const datetime utc) { return utc + NNFXServerOffset(b, utc); }

// 17:00 New York on New York date d (midnight of that date), in UTC
datetime NNFXNyCloseUtc(const datetime d)
  {
   datetime s, e;
   NNFXUsDstDates(NNFXYear(d), s, e);
   return d + ((d >= s && d < e) ? 21 : 22) * 3600;
  }

// The latest 17:00 New York at or before server time t, in server time (the trading day start)
datetime NNFXTradingDayStart(const NNFXBroker &b, const datetime t)
  {
   datetime u = NNFXServerToUtc(b, t);
   datetime c = NNFXNyCloseUtc(NNFXDayOf(u));
   if(c > u)
      c = NNFXNyCloseUtc(NNFXDayOf(u) - 86400);
   return NNFXUtcToServer(b, c);
  }

// The first 17:00 New York strictly after server time t (server time); nyDate = its New York date
datetime NNFXNextBoundary(const NNFXBroker &b, const datetime t, datetime &nyDate)
  {
   datetime u = NNFXServerToUtc(b, t);
   datetime d = NNFXDayOf(u) - 86400;
   while(NNFXNyCloseUtc(d) <= u)
      d += 86400;
   nyDate = d;
   return NNFXUtcToServer(b, NNFXNyCloseUtc(d));
  }

bool NNFXInRollover(const NNFXBroker &b, const datetime t)
  {
   datetime start = NNFXTradingDayStart(b, t + NNFX_GUARD_ROLL_BEFORE);
   return t >= start - NNFX_GUARD_ROLL_BEFORE && t < start + NNFX_GUARD_ROLL_AFTER;
  }

bool NNFXInWeekendBlock(const NNFXBroker &b, const datetime t, const double hours)
  {
   if(hours <= 0)
      return false;
   datetime nyDate;
   datetime nb = NNFXNextBoundary(b, t, nyDate);
   return NNFXDow(nyDate) == 5 && t >= nb - (long)MathRound(hours * 3600.0);
  }

// Today's net closed P/L, the limit (negative) and whether new entries are blocked. Closed trades only (OD-3);
// the day starts at the trading day boundary; limit = 3 x risk % of the day's starting balance = balance now -
// today's P/L; exactly the limit blocks (D6d-2).
bool NNFXDailyLoss(const NNFXBroker &b, const datetime t, const double balanceNow, const double riskPct,
                   const datetime &closeTimes[], const double &profits[], double &pl, double &limit)
  {
   datetime start = NNFXTradingDayStart(b, t);
   pl = 0.0;
   for(int i = 0; i < ArraySize(closeTimes); i++)
      if(closeTimes[i] >= start && closeTimes[i] <= t)
         pl += profits[i];
   limit = -NNFX_GUARD_DL_X * riskPct / 100.0 * (balanceNow - pl);
   return pl <= limit + 1e-9;
  }

struct NNFXDrawdown
  {
   double            peak;
   bool              paused;
  };

// At each candle close (OD-2): the peak of equity; pause at 10% below it; never resets itself (S-6)
void NNFXDrawdownSample(NNFXDrawdown &dd, const double equity)
  {
   dd.peak = MathMax(dd.peak, equity);
   if(equity <= dd.peak * (1.0 - NNFX_GUARD_DD_PAUSE) + 1e-9)
      dd.paused = true;
  }

// By hand only (S-6, D6d-3): the pause ends and the peak restarts from the equity now. Called only by
// NNFXDrawdownResetRequested (and the fixture test)
void NNFXDrawdownReset(NNFXDrawdown &dd, const double equity)
  {
   dd.paused = false;
   dd.peak = equity;
  }

// master: 1 on, 0 off, -1 = the global variable is missing (counts as off)
string NNFXGuardBlocks(const int master, const bool instanceOn, const bool ddPaused, const bool dlBlocked,
                       const bool rollover, const bool weekend, const double spread, const double maxSpread,
                       const bool indicatorOk)
  {
   string s = "";
   if(master != 1)
      s += ",master";
   if(!instanceOn)
      s += ",instance";
   if(ddPaused)
      s += ",drawdown";
   if(dlBlocked)
      s += ",dailyloss";
   if(rollover)
      s += ",rollover";
   if(weekend)
      s += ",weekend";
   if(maxSpread > 0 && spread > maxSpread)
      s += ",spread";
   if(!indicatorOk)
      s += ",indicator";
   return StringSubstr(s, 1);
  }

//--- live helpers (terminal global variables; shared by every instance on this terminal) ---

// 1 on, 0 off, -1 missing (D6d-1: missing counts as OFF)
int NNFXMasterState(void)
  {
   if(!GlobalVariableCheck(NNFX_GV_MASTER))
      return -1;
   return GlobalVariableGet(NNFX_GV_MASTER) != 0.0 ? 1 : 0;
  }

void NNFXDrawdownLoad(NNFXDrawdown &dd)
  {
   dd.peak = GlobalVariableCheck(NNFX_GV_DD_PEAK) ? GlobalVariableGet(NNFX_GV_DD_PEAK) : 0.0;
   dd.paused = GlobalVariableCheck(NNFX_GV_DD_PAUSED) && GlobalVariableGet(NNFX_GV_DD_PAUSED) != 0.0;
  }

// The pause and its peak must survive a crash (G1_phase6d_1 item 2): MT5 writes global variables to disk only from
// time to time, so on any change they are flushed at once (GlobalVariablesFlush).
void NNFXDrawdownSave(const NNFXDrawdown &dd)
  {
   bool changed = !GlobalVariableCheck(NNFX_GV_DD_PEAK) || GlobalVariableGet(NNFX_GV_DD_PEAK) != dd.peak ||
                  !GlobalVariableCheck(NNFX_GV_DD_PAUSED) || (GlobalVariableGet(NNFX_GV_DD_PAUSED) != 0.0) != dd.paused;
   GlobalVariableSet(NNFX_GV_DD_PEAK, dd.peak);
   GlobalVariableSet(NNFX_GV_DD_PAUSED, dd.paused ? 1.0 : 0.0);
   if(changed)
      GlobalVariablesFlush();
  }

// The owner's reset by hand (S-6, D6d-3): NNFX_DD_RESET = 1, set by the owner (or by the chart button after its
// confirm step). The ONLY caller of NNFXDrawdownReset outside the fixture test (source scan, test_guard_rules.py):
// never automatic. Returns true if a reset was done; logText says what changed and MUST be logged by the caller.
bool NNFXDrawdownResetRequested(NNFXDrawdown &dd, const double equity, string &logText)
  {
   logText = "";
   if(!GlobalVariableCheck(NNFX_GV_DD_RESET) || GlobalVariableGet(NNFX_GV_DD_RESET) == 0.0)
      return false;
   double oldPeak = dd.peak;
   bool wasPaused = dd.paused;
   NNFXDrawdownReset(dd, equity);
   NNFXDrawdownSave(dd);
   GlobalVariableSet(NNFX_GV_DD_RESET, 0.0);
   GlobalVariablesFlush();
   logText = StringFormat("drawdown reset by hand (D6d-3): was %s, peak %.2f -> %.2f (equity now %.2f)",
                          wasPaused ? "paused" : "not paused", oldPeak, dd.peak, equity);
   Print("NNFX: ", logText);
   return true;
  }

// Log + Alert + optional push (push needs a MetaQuotes ID set in MT5; unverified on this PC)
void NNFXNotify(const string text, const bool push = false)
  {
   Print("NNFX: ", text);
   Alert("NNFX: ", text);
   if(push)
      SendNotification("NNFX: " + text);
  }

#endif
