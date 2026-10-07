//+------------------------------------------------------------------+
//| NNFX_CoreStateTest.mq5                                           |
//| Phase 6f check (DESIGN_6F section 5): the rules core's memory    |
//| survives a restart exactly. For every rule fixture (the same     |
//| files as NNFX_RulesTest, MQL5\Files\NNFX\fixtures\*.txt) and     |
//| every split point k: run candles 0..k-1, Snapshot(), restore     |
//| into a NEW core, run candles k..end. Every event from k on must  |
//| equal the uninterrupted run's (candle index, event, rule, dir,   |
//| price, note), and Restore(Snapshot()) must give the same line.   |
//| Places NO orders. Writes MQL5\Files\NNFX_CoreStateTest.txt       |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\RulesCore.mqh>

input string InpFolder = "NNFX\\fixtures";   // the rule fixtures (MQL5\Files)

int g_report = INVALID_HANDLE;

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

string EventText(const NNFXEvent &e)
  {
   return StringFormat("%d|%s|%s|%d|%s|%s", e.i, e.ev, e.rule, e.dir, e.has_price ? DoubleToString(e.price, 10) : "-", e.note);
  }

bool ReadFixture(const string file, NNFXSettings &s, NNFXBar &bars[], string &name)
  {
   name = file;
   int h = FileOpen(InpFolder + "\\" + file, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   s.Defaults();
   ArrayResize(bars, 0);
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      string p[];
      int n = StringSplit(line, '|', p);
      if(n < 1)
         continue;
      if(p[0] == "NAME" && n >= 2)
         name = p[1];
      else if(p[0] == "SET" && n >= 3)
         s.Set(p[1], p[2]);
      else if(p[0] == "BAR" && n >= 14)
        {
         int k = ArraySize(bars);
         ArrayResize(bars, k + 1);
         bars[k].t = StringToInteger(p[1]);
         bars[k].o = StringToDouble(p[2]);
         bars[k].h = StringToDouble(p[3]);
         bars[k].l = StringToDouble(p[4]);
         bars[k].c = StringToDouble(p[5]);
         bars[k].atr = StringToDouble(p[6]);
         bars[k].base = StringToDouble(p[7]);
         bars[k].c1 = (int)StringToInteger(p[8]);
         bars[k].c2 = (int)StringToInteger(p[9]);
         bars[k].ex = (int)StringToInteger(p[10]);
         bars[k].vol = (p[11] == "1");
         bars[k].block = p[12];
         bars[k].news = (p[13] == "1");
        }
     }
   FileClose(h);
   return ArraySize(bars) > 0;
  }

bool RunFixture(const string file, string &name, int &splits)
  {
   NNFXSettings s;
   NNFXBar bars[];
   splits = 0;
   if(!ReadFixture(file, s, bars, name))
     {
      Out("FAIL " + file + ": cannot read");
      return false;
     }
   int n = ArraySize(bars);
   CNNFXPairCore full;
   full.Init("TEST", s);
   for(int k = 0; k < n; k++)
      full.OnBar(bars[k]);
   string ref[];
   ArrayResize(ref, full.EventCount());
   NNFXEvent e;
   for(int k = 0; k < full.EventCount(); k++)
      if(full.GetEvent(k, e))
         ref[k] = EventText(e);
   for(int split = 1; split < n; split++)
     {
      CNNFXPairCore a;
      a.Init("TEST", s);
      for(int k = 0; k < split; k++)
         a.OnBar(bars[k]);
      string snap = a.Snapshot();
      CNNFXPairCore b;
      b.Init("TEST", s);
      if(!b.Restore(snap) || b.Snapshot() != snap)
        {
         Out(StringFormat("FAIL %s: split %d: Restore(Snapshot()) not identical", name, split));
         return false;
        }
      for(int k = split; k < n; k++)
         b.OnBar(bars[k]);
      // the uninterrupted run's events from candle 'split' on
      string want[];
      for(int k = 0; k < ArraySize(ref); k++)
        {
         string q[];
         StringSplit(ref[k], '|', q);
         if((int)StringToInteger(q[0]) >= split)
           {
            int w = ArraySize(want);
            ArrayResize(want, w + 1);
            want[w] = ref[k];
           }
        }
      bool ok = (b.EventCount() == ArraySize(want));
      for(int k = 0; ok && k < b.EventCount(); k++)
         ok = b.GetEvent(k, e) && EventText(e) == want[k];
      if(!ok)
        {
         Out(StringFormat("FAIL %s: split %d: the restored core's events differ from the uninterrupted run", name, split));
         return false;
        }
      splits++;
     }
   Out(StringFormat("PASS %s (%d splits)", name, splits));
   return true;
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_CoreStateTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_CoreStateTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   string found;
   int pass = 0, fail = 0, splitsAll = 0;
   long search = FileFindFirst(InpFolder + "\\*.txt", found);
   if(search != INVALID_HANDLE)
     {
      do
        {
         string name;
         int splits;
         if(RunFixture(found, name, splits))
            pass++;
         else
            fail++;
         splitsAll += splits;
        }
      while(FileFindNext(search, found));
      FileFindClose(search);
     }
   Out(StringFormat("%d split points checked", splitsAll));
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", pass, fail, pass + fail));
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
