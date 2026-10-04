//+------------------------------------------------------------------+
//| NNFX_RulesTest.mq5                                               |
//| Runs every rule fixture through the MQL5 rules core and compares |
//| the result with the expected answer (docs/SPEC.md, Check 1a).    |
//|                                                                  |
//| The fixtures are the same cases the Python answer key passes:    |
//| tests/fixtures/mql5/*.txt in the repo, copied to                 |
//|   <MT5 data folder>\MQL5\Files\NNFX\fixtures\                     |
//|                                                                  |
//| Places NO orders. Reads the fixture files and writes one report: |
//|   MQL5\Files\NNFX_RulesTest.txt                                  |
//|                                                                  |
//| Status: compiled 2026-10-03, MT5 build 6235, 0 errors 0 warnings;|
//| NNFX_RulesTest 47/47 (docs/VERIFICATION.md).                     |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <NNFX\RulesCore.mqh>

input string InpFolder = "NNFX\\fixtures"; // Fixture folder inside MQL5\Files

int g_report = INVALID_HANDLE;

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

bool InList(const string s, const string &arr[])
  {
   for(int k = 0; k < ArraySize(arr); k++)
      if(arr[k] == s)
         return true;
   return false;
  }

void PushString(string &arr[], const string s)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = s;
  }

// Runs one fixture file. Returns true if it passes; explains any failure in the report.
bool RunFixture(const string file, string &name)
  {
   name = file;
   int h = FileOpen(InpFolder + "\\" + file, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Out("FAIL " + file + ": cannot open (error " + IntegerToString(GetLastError()) + ")");
      return false;
     }
   NNFXSettings s;
   s.Defaults();
   string check[];
   string expect[];
   double expect_r[];
   NNFXBar bars[];
   bool ended = false;
   string problem = "";

   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      if(line == "")
         continue;
      string p[];
      int n = StringSplit(line, '|', p);
      string tag = p[0];
      if(tag == "NAME" && n >= 2)
         name = p[1];
      else if(tag == "RULE")
         continue;
      else if(tag == "SET" && n >= 3)
        {
         if(!s.Set(p[1], p[2]))
            problem = "unknown setting " + p[1];
        }
      else if(tag == "CHECK" && n >= 2)
         StringSplit(p[1], ',', check);
      else if(tag == "BAR" && n >= 14)
        {
         int k = ArraySize(bars);
         ArrayResize(bars, k + 1);
         bars[k].t    = StringToInteger(p[1]);
         bars[k].o    = StringToDouble(p[2]);
         bars[k].h    = StringToDouble(p[3]);
         bars[k].l    = StringToDouble(p[4]);
         bars[k].c    = StringToDouble(p[5]);
         bars[k].atr  = StringToDouble(p[6]);
         bars[k].base = StringToDouble(p[7]);
         bars[k].c1   = (int)StringToInteger(p[8]);
         bars[k].c2   = (int)StringToInteger(p[9]);
         bars[k].ex   = (int)StringToInteger(p[10]);
         bars[k].vol  = (p[11] == "1");
         bars[k].block = p[12];
         bars[k].news = (p[13] == "1");
        }
      else if(tag == "EXP" && n >= 5)
         PushString(expect, p[1] + "|" + p[2] + "|" + p[3] + "|" + p[4]);
      else if(tag == "EXPR" && n >= 2)
        {
         int k = ArraySize(expect_r);
         ArrayResize(expect_r, k + 1);
         expect_r[k] = StringToDouble(p[1]);
        }
      else if(tag == "END")
        {
         ended = true;
         break;
        }
      else
         problem = "unreadable line: " + line;
     }
   FileClose(h);
   if(!ended)
      problem = "file has no END line (truncated?)";
   if(problem != "")
     {
      Out("FAIL " + name + ": " + problem);
      return false;
     }

   CNNFXPairCore core;
   if(!core.Init("TEST", s))
     {
      Out("FAIL " + name + ": settings rejected");
      return false;
     }
   for(int k = 0; k < ArraySize(bars); k++)
      core.OnBar(bars[k]);

   string got[];
   NNFXEvent e;
   for(int k = 0; k < core.EventCount(); k++)
      if(core.GetEvent(k, e) && InList(e.ev, check))
         PushString(got, IntegerToString(e.i) + "|" + e.ev + "|" + e.rule + "|" + IntegerToString(e.dir));

   bool ok = (ArraySize(got) == ArraySize(expect));
   for(int k = 0; ok && k < ArraySize(got); k++)
      ok = (got[k] == expect[k]);

   bool r_ok = true;
   if(ArraySize(expect_r) > 0)
     {
      r_ok = (core.ClosedCount() == ArraySize(expect_r));
      for(int k = 0; r_ok && k < ArraySize(expect_r); k++)
         r_ok = (MathAbs(core.ClosedR(k) - expect_r[k]) < 1e-5);
     }

   if(ok && r_ok)
     {
      Out("PASS " + name);
      return true;
     }

   Out("FAIL " + name);
   string ex_line = "  expected:";
   for(int k = 0; k < ArraySize(expect); k++)
      ex_line += " [" + expect[k] + "]";
   Out(ex_line);
   string got_line = "  got:     ";
   for(int k = 0; k < ArraySize(got); k++)
      got_line += " [" + got[k] + "]";
   Out(got_line);
   if(!r_ok)
     {
      string rl = "  R expected:";
      for(int k = 0; k < ArraySize(expect_r); k++)
         rl += " " + DoubleToString(expect_r[k], 6);
      rl += "  got:";
      for(int k = 0; k < core.ClosedCount(); k++)
         rl += " " + DoubleToString(core.ClosedR(k), 6);
      Out(rl);
     }
   Out("  full trace:");
   for(int k = 0; k < core.EventCount(); k++)
      if(core.GetEvent(k, e))
         Out(StringFormat("    bar %d  %-8s %-4s dir=%+d  price=%s  %s", e.i, e.ev, e.rule, e.dir,
                          e.has_price ? DoubleToString(e.price, 6) : "-", e.note));
   return false;
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_RulesTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_RulesTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));

   string files[];
   string found;
   long search = FileFindFirst(InpFolder + "\\*.txt", found);
   if(search == INVALID_HANDLE)
     {
      Out("No fixtures found in MQL5\\Files\\" + InpFolder + " (copy tests/fixtures/mql5/*.txt there)");
     }
   else
     {
      do
         PushString(files, found);
      while(FileFindNext(search, found));
      FileFindClose(search);
     }
   // (FileFindNext order is used as-is: ArraySort only sorts numeric arrays in MQL5)

   int pass = 0, fail = 0;
   for(int k = 0; k < ArraySize(files); k++)
     {
      string name;
      if(RunFixture(files[k], name))
         pass++;
      else
         fail++;
     }
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", pass, fail, pass + fail));
   if(g_report != INVALID_HANDLE)
     {
      FileClose(g_report);
      Print("NNFX_RulesTest: report written to MQL5\\Files\\NNFX_RulesTest.txt");
     }
  }
//+------------------------------------------------------------------+
