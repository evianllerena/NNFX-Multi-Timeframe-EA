//+------------------------------------------------------------------+
//| NNFX_GuardTest.mq5                                               |
//| Phase 6d check: Guard.mqh gives the same answers as the Python   |
//| answer key (nnfx_ref/guard.py) on the shared, hand-worked cases  |
//|   MQL5\Files\NNFX\guard\guard_cases.txt                          |
//| (trading day boundary, rollover, weekend, daily loss, drawdown,  |
//| block string). Then INFO lines, never counted: this terminal's   |
//| server offset now, and the master global variable.               |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_GuardTest.txt           |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\Guard.mqh>
#include <NNFX\Connection.mqh>

input string InpCases = "NNFX\\guard\\guard_cases.txt";   // Guard cases (MQL5\Files)

int g_report = INVALID_HANDLE;
int g_pass = 0, g_fail = 0;
NNFXBroker g_brokers[];

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

void Check(const string kind, const string id, const bool ok, const string detail)
  {
   if(ok)
      g_pass++;
   else
     {
      g_fail++;
      Out("FAIL " + kind + " " + id + ": " + detail);
     }
  }

int FindBroker(const string name)
  {
   for(int i = 0; i < ArraySize(g_brokers); i++)
      if(g_brokers[i].name == name)
         return i;
   return -1;
  }

string Fmt(const datetime t) { return TimeToString(t, TIME_DATE | TIME_MINUTES); }

void RunLine(string &p[])
  {
   string k = p[0];
   int n = ArraySize(p);
   if(k == "BROKER")
     {
      int i = ArraySize(g_brokers);
      ArrayResize(g_brokers, i + 1);
      g_brokers[i].name = p[1];
      g_brokers[i].winter_offset = (int)StringToInteger(p[2]);
      g_brokers[i].dst = p[3];
      return;
     }
   int bi = (n > 2) ? FindBroker(k == "DD" ? "" : (k == "BLK" ? p[6] : p[2])) : -1;
   if(k != "DD" && bi < 0)
     {
      Check(k, p[1], false, "unknown broker");
      return;
     }
   if(k == "TDB")
     {
      string got = Fmt(NNFXTradingDayStart(g_brokers[bi], StringToTime(p[3])));
      Check(k, p[1], got == p[4], "expected " + p[4] + " got " + got);
     }
   else if(k == "ROLL")
     {
      int got = NNFXInRollover(g_brokers[bi], StringToTime(p[3])) ? 1 : 0;
      Check(k, p[1], got == (int)StringToInteger(p[4]), StringFormat("expected %s got %d", p[4], got));
     }
   else if(k == "WEEK")
     {
      int got = NNFXInWeekendBlock(g_brokers[bi], StringToTime(p[3]), StringToDouble(p[4])) ? 1 : 0;
      Check(k, p[1], got == (int)StringToInteger(p[5]), StringFormat("expected %s got %d", p[5], got));
     }
   else if(k == "DLOSS")
     {
      datetime times[];
      double profits[];
      if(p[6] != "-")
        {
         string items[];
         int m = StringSplit(p[6], ';', items);
         ArrayResize(times, m);
         ArrayResize(profits, m);
         for(int i = 0; i < m; i++)
           {
            string kv[];
            StringSplit(items[i], '=', kv);
            times[i] = StringToTime(kv[0]);
            profits[i] = StringToDouble(kv[1]);
           }
        }
      double pl, limit;
      bool blocked = NNFXDailyLoss(g_brokers[bi], StringToTime(p[3]), StringToDouble(p[4]), StringToDouble(p[5]),
                                   times, profits, pl, limit);
      bool ok = MathAbs(pl - StringToDouble(p[7])) < 1e-6 && MathAbs(limit - StringToDouble(p[8])) < 1e-6 &&
                (blocked ? 1 : 0) == (int)StringToInteger(p[9]);
      Check(k, p[1], ok, StringFormat("expected %s/%s/%s got %.6f/%.6f/%d", p[7], p[8], p[9], pl, limit, blocked ? 1 : 0));
     }
   else if(k == "DD")
     {
      string toks[], want[];
      int m = StringSplit(p[2], ',', toks);
      StringSplit(p[3], ',', want);
      NNFXDrawdown dd;
      dd.peak = 0.0;
      dd.paused = false;
      double last = 0.0;
      string got = "";
      for(int i = 0; i < m; i++)
        {
         if(toks[i] == "R")
            NNFXDrawdownReset(dd, last);
         else
           {
            string eb[];
            StringSplit(StringSubstr(toks[i], 2), '/', eb);
            last = StringToDouble(eb[0]);
            NNFXDrawdownSample(dd, last);
           }
         got += (i > 0 ? "," : "") + StringFormat("%d:%.0f", dd.paused ? 1 : 0, dd.peak);
        }
      Check(k, p[1], got == p[3], "expected " + p[3] + " got " + got);
     }
   else if(k == "BLK")
     {
      datetime t = StringToTime(p[7]);
      int master = (p[2] == "-") ? -1 : (int)StringToInteger(p[2]);
      string got = NNFXGuardBlocks(master, p[3] == "1", p[4] == "1", p[5] == "1", NNFXInRollover(g_brokers[bi], t),
                                   NNFXInWeekendBlock(g_brokers[bi], t, StringToDouble(p[8])), StringToDouble(p[9]),
                                   StringToDouble(p[10]), p[11] == "1");
      if(got == "")
         got = "-";
      Check(k, p[1], got == p[12], "expected " + p[12] + " got " + got);
     }
   else
      Check(k, p[1], false, "unknown line kind");
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_GuardTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_GuardTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   int h = FileOpen(InpCases, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Out("cannot open " + InpCases + ", error " + IntegerToString(GetLastError()));
      g_fail++;
     }
   else
     {
      while(!FileIsEnding(h))
        {
         string line = FileReadString(h);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(line == "" || StringGetCharacter(line, 0) == '#')
            continue;
         string p[];
         StringSplit(line, '|', p);
         RunLine(p);
        }
      FileClose(h);
     }
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", g_pass, g_fail, g_pass + g_fail));
   // INFO, never counted. The live server offset only after login: before it, TimeTradeServer() read the same as
   // TimeGMT() (run 20261006_102315: "+0.00 hours" on MetaQuotes-Demo, which is GMT+3)
   string syms[1];
   syms[0] = _Symbol;
   string detail;
   if(NNFXWaitConnected(syms, 60, detail))
      Out(StringFormat("INFO server - GMT now: %+.2f hours (TimeTradeServer %s, TimeGMT %s; %s)",
                       (double)(TimeTradeServer() - TimeGMT()) / 3600.0, Fmt(TimeTradeServer()), Fmt(TimeGMT()), detail));
   else
      Out("INFO server - GMT not read: not logged in (" + detail + ")");
   int ms = NNFXMasterState();
   Out("INFO master switch " + NNFX_GV_MASTER + ": " + (ms < 0 ? "missing (counts as OFF)" : (ms == 1 ? "on" : "off")));
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
