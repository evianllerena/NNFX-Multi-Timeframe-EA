//+------------------------------------------------------------------+
//| NNFX_SignalTest.mq5                                              |
//| Phase 5 check: the MQL5 signal layer and profile reader give the |
//| same answers as the Python answer key on identical cases.        |
//|                                                                  |
//|  1. Signal cases  MQL5\Files\NNFX\signals\signal_cases.txt       |
//|  2. Reference profiles must load                                 |
//|                   Common\Files\NNFX\profiles\ref_*.txt           |
//|  3. Bad profiles must be rejected                                |
//|                   MQL5\Files\NNFX\profiles_bad\*.txt             |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_SignalTest.txt          |
//| Status: NOT YET COMPILED.                                        |
//+------------------------------------------------------------------+
#property script_show_inputs

#include <NNFX\Slot.mqh>

input string InpCases   = "NNFX\\signals\\signal_cases.txt"; // Signal cases (MQL5\Files)
input string InpBadDir  = "NNFX\\profiles_bad";              // Bad profiles (MQL5\Files)
input string InpGoodDir = "NNFX\\profiles";                  // Reference profiles (Common\Files)

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

// Special tokens: nan, inf, empty. NaN and infinity are made with documented MQL5 behaviour:
// MathArcsin(x) for |x| > 1 returns NaN; MathLog(0) returns INF.
double Tok(const string text)
  {
   string t = NNFXTrim(text);
   if(t == "nan")
      return MathArcsin(2.0);
   if(t == "inf")
      return MathLog(0.0);
   if(t == "empty")
      return EMPTY_VALUE;
   return StringToDouble(t);
  }

void RunSignalCases()
  {
   int h = FileOpen(InpCases, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Result(false, "open " + InpCases + " (error " + IntegerToString(GetLastError()) + ")");
      return;
     }
   int count = 0;
   while(!FileIsEnding(h))
     {
      string line = NNFXTrim(FileReadString(h));
      if(line == "" || StringGetCharacter(line, 0) == '#')
         continue;
      string p[];
      int n = StringSplit(line, '|', p);
      string kind = (n > 0) ? p[0] : "";
      int got = 0, want = 0;
      bool known = true;
      if(kind == "PL" && n == 5)
        { got = NNFXPriceLineDir(Tok(p[2]), Tok(p[3])); want = (int)StringToInteger(p[4]); }
      else if(kind == "TL" && n == 5)
        { got = NNFXTwoLineDir(Tok(p[2]), Tok(p[3])); want = (int)StringToInteger(p[4]); }
      else if(kind == "CL" && n == 5)
        { got = NNFXCentreLineDir(Tok(p[2]), Tok(p[3])); want = (int)StringToInteger(p[4]); }
      else if(kind == "VL" && n == 5)
        { got = NNFXVolumeLevel(Tok(p[2]), Tok(p[3])) ? 1 : 0; want = (int)StringToInteger(p[4]); }
      else if(kind == "VC" && n == 5)
        { got = NNFXVolumeCross(Tok(p[2]), Tok(p[3])) ? 1 : 0; want = (int)StringToInteger(p[4]); }
      else if(kind == "VA" && n == 6)
        {
         string hs[];
         int m = StringSplit(p[4], ';', hs);
         double hist[];
         ArrayResize(hist, m);
         for(int k = 0; k < m; k++)
            hist[k] = Tok(hs[k]);
         got = NNFXVolumeAverage(Tok(p[2]), Tok(p[3]), hist) ? 1 : 0;
         want = (int)StringToInteger(p[5]);
        }
      else
         known = false;
      count++;
      if(!known)
         Result(false, "signal case: unreadable line " + line);
      else
         Result(got == want, StringFormat("signal %s %s: expected %d got %d", kind, p[1], want, got));
     }
   FileClose(h);
   Out(StringFormat("(%d signal cases read)", count));
  }

void RunProfiles(const string dir, const bool common, const bool must_load)
  {
   string found;
   int flags = common ? FILE_COMMON : 0;
   long search = FileFindFirst(dir + "\\*.txt", found, flags);
   if(search == INVALID_HANDLE)
     {
      Result(false, "no profiles found in " + dir + (common ? " (Common\\Files)" : " (MQL5\\Files)"));
      return;
     }
   do
     {
      CNNFXProfile p;
      bool loaded = p.Load(dir + "\\" + found, common);
      if(must_load)
         Result(loaded, "profile loads: " + found + (loaded ? "" : " -> " + p.error));
      else
         Result(!loaded, "bad profile rejected: " + found + (loaded ? " (WAS ACCEPTED)" : " -> " + p.error));
     }
   while(FileFindNext(search, found));
   FileFindClose(search);
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_SignalTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_SignalTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   RunSignalCases();
   RunProfiles(InpGoodDir, true, true);
   RunProfiles(InpBadDir, false, false);
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", g_pass, g_fail, g_pass + g_fail));
   if(g_report != INVALID_HANDLE)
     {
      FileClose(g_report);
      Print("NNFX_SignalTest: report written to MQL5\\Files\\NNFX_SignalTest.txt");
     }
  }
//+------------------------------------------------------------------+
