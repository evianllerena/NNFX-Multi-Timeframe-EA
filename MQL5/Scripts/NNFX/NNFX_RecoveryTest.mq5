//+------------------------------------------------------------------+
//| NNFX_RecoveryTest.mq5                                            |
//| Phase 6c check: the MQL5 rebuild (State.mqh NNFXRebuildPure) and |
//| the state-file reader give the same answers as the Python answer |
//| key (nnfx_ref/recovery.py) on identical, hand-worked cases:      |
//|   MQL5\Files\NNFX\recovery\recovery_cases.txt                    |
//|   MQL5\Files\NNFX\recovery\state_files\index.txt (+ the files)   |
//| plus the published FNV-1a test vectors for the checksum.         |
//| Broker reads are replaced by the fixture data (one interface:    |
//| the NNFXPosRec / NNFXDealRec / NNFXCandleRec arrays).            |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_RecoveryTest.txt        |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\State.mqh>

input string InpCases = "NNFX\\recovery\\recovery_cases.txt";      // Rebuild cases (MQL5\Files)
input string InpIndex = "NNFX\\recovery\\state_files\\index.txt";  // State-file cases (MQL5\Files)

int g_report = INVALID_HANDLE;
int g_pass = 0, g_fail = 0;

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

void Result(const bool ok, const string what)
  {
   if(ok)
      g_pass++;
   else
      g_fail++;
   Out((ok ? "PASS " : "FAIL ") + what);
  }

bool ReadLines(const string path, string &lines[])
  {
   ArrayResize(lines, 0);
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(h))
     {
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = FileReadString(h);
      StringReplace(lines[n], "\r", "");
     }
   FileClose(h);
   return true;
  }

// Joins p[from..] back with '|' (a comment can be empty; an EXP line is everything after "EXP|").
string Rest(const string &p[], const int from)
  {
   string s = "";
   for(int i = from; i < ArraySize(p); i++)
      s += (i > from ? "|" : "") + p[i];
   return s;
  }

void RunCases()
  {
   string lines[];
   if(!ReadLines(InpCases, lines))
     {
      Result(false, "open " + InpCases + " (error " + IntegerToString(GetLastError()) + ")");
      return;
     }
   string name = "";
   long magic = 0;
   int period = 3600;
   datetime upto = 0;
   bool ignore = false;
   string status = "absent";
   NNFXTrade st[];
   NNFXPosRec pos[];
   NNFXDealRec deals[];
   NNFXCandleRec candles[];
   string exp[], notesWanted[];
   int cases = 0;
   for(int li = 0; li < ArraySize(lines); li++)
     {
      string line = lines[li];
      if(line == "" || StringGetCharacter(line, 0) == '#')
         continue;
      string p[];
      int n = StringSplit(line, '|', p);
      string kind = p[0];
      if(kind == "CASE")
        {
         name = p[1];
         magic = 0;
         period = 3600;
         upto = 0;
         ignore = false;
         status = "absent";
         ArrayResize(st, 0);
         ArrayResize(pos, 0);
         ArrayResize(deals, 0);
         ArrayResize(candles, 0);
         ArrayResize(exp, 0);
         ArrayResize(notesWanted, 0);
        }
      else if(kind == "MAGIC")
         magic = StringToInteger(p[1]);
      else if(kind == "PERIOD")
         period = (int)StringToInteger(p[1]);
      else if(kind == "UPTO")
         upto = StringToTime(p[1]);
      else if(kind == "IGNORE_COMMENTS")
         ignore = (p[1] == "1");
      else if(kind == "STATE")
         status = p[1];
      else if(kind == "STRADE")
        {
         int k = ArraySize(st);
         ArrayResize(st, k + 1);
         NNFXParseTradeFields(p, 1, st[k]);
        }
      else if(kind == "POS" && n >= 10)
        {
         int k = ArraySize(pos);
         ArrayResize(pos, k + 1);
         pos[k].pos = (ulong)StringToInteger(p[1]);
         pos[k].sym = p[2];
         pos[k].magic = StringToInteger(p[3]);
         pos[k].dir = (int)StringToInteger(p[4]);
         pos[k].volume = StringToDouble(p[5]);
         pos[k].price = StringToDouble(p[6]);
         pos[k].sl = StringToDouble(p[7]);
         pos[k].tp = StringToDouble(p[8]);
         pos[k].comment = Rest(p, 9);
        }
      else if(kind == "DEAL" && n >= 12)
        {
         int k = ArraySize(deals);
         ArrayResize(deals, k + 1);
         deals[k].deal = (ulong)StringToInteger(p[1]);
         deals[k].time = StringToTime(p[2]);
         deals[k].pos = (ulong)StringToInteger(p[3]);
         deals[k].sym = p[4];
         deals[k].magic = StringToInteger(p[5]);
         deals[k].entry = p[6];
         deals[k].dir = (int)StringToInteger(p[7]);
         deals[k].volume = StringToDouble(p[8]);
         deals[k].price = StringToDouble(p[9]);
         deals[k].reason = p[10];
         deals[k].comment = Rest(p, 11);
        }
      else if(kind == "CANDLE" && n == 7)
        {
         int k = ArraySize(candles);
         ArrayResize(candles, k + 1);
         candles[k].sym = p[1];
         candles[k].time = StringToTime(p[2]);
         candles[k].close = StringToDouble(p[3]);
         candles[k].atr = StringToDouble(p[4]);
         candles[k].side = (int)StringToInteger(p[5]);
         candles[k].c1 = (int)StringToInteger(p[6]);
        }
      else if(kind == "EXP")
        {
         int k = ArraySize(exp);
         ArrayResize(exp, k + 1);
         exp[k] = Rest(p, 1);
        }
      else if(kind == "NOTE")
        {
         int k = ArraySize(notesWanted);
         ArrayResize(notesWanted, k + 1);
         notesWanted[k] = Rest(p, 1);
        }
      else if(kind == "END")
        {
         cases++;
         NNFXTrade out[];
         NNFXCont conts[];
         string notes;
         NNFXRebuildPure(pos, deals, status, st, candles, period, magic, upto, ignore, out, conts, notes);
         string got[];
         NNFXSerialize(out, conts, got);
         bool ok = (ArraySize(got) == ArraySize(exp));
         for(int k = 0; ok && k < ArraySize(got); k++)
            ok = (got[k] == exp[k]);
         string missing = "";
         for(int k = 0; k < ArraySize(notesWanted); k++)
            if(StringFind(notes, notesWanted[k]) < 0)
               missing += " [" + notesWanted[k] + "]";
         Result(ok && missing == "", "rebuild " + name + (ok ? "" : ": expected {" + NNFXJoin(exp, " / ") + "} got {" +
                NNFXJoin(got, " / ") + "}") + (missing == "" ? "" : "; notes missing" + missing + " in {" + notes + "}"));
        }
      else
         Result(false, "case file: unreadable line " + line);
     }
   Out(StringFormat("(%d rebuild cases read)", cases));
  }

void RunStateFiles()
  {
   string idx[];
   if(!ReadLines(InpIndex, idx))
     {
      Result(false, "open " + InpIndex);
      return;
     }
   string dir = StringSubstr(InpIndex, 0, StringFind(InpIndex, "index.txt"));
   for(int i = 0; i < ArraySize(idx); i++)
     {
      if(StringFind(idx[i], "SFTEST|") != 0)
         continue;
      string p[];
      StringSplit(idx[i], '|', p);
      string lines[];
      if(!ReadLines(dir + p[1], lines))
        {
         Result(false, "state file " + p[1] + ": cannot open");
         continue;
        }
      NNFXTrade trades[];
      NNFXCont conts[];
      datetime proc;
      string why;
      string status = NNFXStateParse(lines, trades, conts, proc, why);
      bool ok = (status == p[2] && ArraySize(trades) == (int)StringToInteger(p[3]) &&
                 ArraySize(conts) == (int)StringToInteger(p[4]));
      Result(ok, StringFormat("state file %s: expected %s %s/%s, got %s %d/%d %s", p[1], p[2], p[3], p[4], status,
                              ArraySize(trades), ArraySize(conts), why));
     }
  }

void RunChecksums()
  {
   Result(NNFXFnv1a32("") == 0x811C9DC5, StringFormat("fnv1a32(\"\") = %08x (published 811c9dc5)", NNFXFnv1a32("")));
   Result(NNFXFnv1a32("a") == 0xE40C292C, StringFormat("fnv1a32(\"a\") = %08x (published e40c292c)", NNFXFnv1a32("a")));
   Result(NNFXFnv1a32("foobar") == 0xBF9CF968, StringFormat("fnv1a32(\"foobar\") = %08x (published bf9cf968)",
                                                              NNFXFnv1a32("foobar")));
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_RecoveryTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_RecoveryTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   RunChecksums();
   RunStateFiles();
   RunCases();
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", g_pass, g_fail, g_pass + g_fail));
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
