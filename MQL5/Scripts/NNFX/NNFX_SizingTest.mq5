//+------------------------------------------------------------------+
//| NNFX_SizingTest.mq5                                              |
//| Phase 6a check: the MQL5 sizing and exposure ports give the same |
//| answers as the Python answer key on identical, hand-worked cases.|
//|                                                                  |
//|  1. Sizing cases    MQL5\Files\NNFX\sizing\sizing_cases.txt      |
//|  2. Exposure cases  MQL5\Files\NNFX\exposure\exposure_cases.txt  |
//|  3. LIVE read (information only, not counted): for each pair,    |
//|     tick value, tick value for a loss, the one used (OD-6), and  |
//|     the sizing it would give now for a 1.5 x ATR(14) H1 stop.    |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_SizingTest.txt          |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| 42/42, run 20261004_125319).                                       |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\Sizing.mqh>
#include <NNFX\Exposure.mqh>
#include <NNFX\Connection.mqh>

input string InpSizingCases   = "NNFX\\sizing\\sizing_cases.txt";      // Sizing cases (MQL5\Files)
input string InpExposureCases = "NNFX\\exposure\\exposure_cases.txt";  // Exposure cases (MQL5\Files)
input string InpLiveSymbols   = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY";  // Pairs for the live read
input double InpLiveRiskPct   = 2.0;                                   // Risk % for the live read
input int    InpConnectWait   = 60;                                    // Seconds to wait for login (live read only)

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

string Trim(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
  }

bool Near(const double a, const double b, const double tol)
  {
   return MathAbs(a - b) <= tol;
  }

// Reads non-comment lines of a case file into lines[]. False if the file can't be opened.
bool ReadCases(const string path, string &lines[])
  {
   ArrayResize(lines, 0);
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      Result(false, "open " + path + " (error " + IntegerToString(GetLastError()) + ")");
      return false;
     }
   while(!FileIsEnding(h))
     {
      string line = Trim(FileReadString(h));
      if(line == "" || StringGetCharacter(line, 0) == '#')
         continue;
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = line;
     }
   FileClose(h);
   return true;
  }

double VolMax(const string text)
  {
   return (text == "-") ? 0.0 : StringToDouble(text);
  }

void RunSizingCases()
  {
   string lines[];
   if(!ReadCases(InpSizingCases, lines))
      return;
   for(int i = 0; i < ArraySize(lines); i++)
     {
      string p[];
      int n = StringSplit(lines[i], '|', p);
      string kind = (n > 0) ? p[0] : "";
      if(kind == "SZ" && n == 14)
        {
         NNFXSize s;
         bool ok = NNFXSizeTrade(StringToDouble(p[2]), StringToDouble(p[3]), StringToDouble(p[4]),
                                 StringToDouble(p[5]), StringToDouble(p[6]), StringToDouble(p[7]),
                                 StringToDouble(p[8]), VolMax(p[9]), s);
         bool wantSkip = (p[10] == "1");
         bool good = ok && s.skipped == wantSkip &&
                     Near(s.half_lots, StringToDouble(p[11]), 1e-9) &&
                     Near(s.total_lots, StringToDouble(p[12]), 1e-9) &&
                     Near(s.risk_money, StringToDouble(p[13]), 1e-6) &&
                     s.risk_money <= s.target_risk_money + 1e-9 &&
                     (!wantSkip || s.reason == "too small to size");
         Result(good, StringFormat("sizing %s: expected skip=%s half=%s total=%s risk=%s; got ok=%s skip=%s half=%.8f total=%.8f risk=%.6f target=%.6f %s",
                                   p[1], p[10], p[11], p[12], p[13], ok ? "1" : "0", s.skipped ? "1" : "0",
                                   s.half_lots, s.total_lots, s.risk_money, s.target_risk_money, s.reason));
        }
      else if(kind == "SE" && n == 10)
        {
         NNFXSize s;
         bool ok = NNFXSizeTrade(StringToDouble(p[2]), StringToDouble(p[3]), StringToDouble(p[4]),
                                 StringToDouble(p[5]), StringToDouble(p[6]), StringToDouble(p[7]),
                                 StringToDouble(p[8]), VolMax(p[9]), s);
         Result(!ok, StringFormat("sizing %s: inputs must be rejected; got %s %s", p[1],
                                  ok ? "ACCEPTED" : "rejected", s.reason));
        }
      else if(kind == "TV" && n == 5)
        {
         double got = NNFXTickValueForSizing(StringToDouble(p[2]), StringToDouble(p[3]));
         Result(Near(got, StringToDouble(p[4]), 1e-12),
                StringFormat("tick value %s: expected %s got %.8f", p[1], p[4], got));
        }
      else
         Result(false, "sizing case: unreadable line " + lines[i]);
     }
   Out(StringFormat("(%d sizing cases read)", ArraySize(lines)));
  }

// "EURUSD:1;GBPJPY:-1" or "-" -> positions
void ParsePositions(const string text, NNFXPos &out[])
  {
   ArrayResize(out, 0);
   if(text == "-")
      return;
   string items[];
   int n = StringSplit(text, ';', items);
   ArrayResize(out, n);
   for(int i = 0; i < n; i++)
     {
      string kv[];
      StringSplit(items[i], ':', kv);
      out[i].sym = kv[0];
      out[i].dir = (int)StringToInteger(kv[1]);
     }
  }

void RunExposureCases()
  {
   string lines[];
   if(!ReadCases(InpExposureCases, lines))
      return;
   for(int i = 0; i < ArraySize(lines); i++)
     {
      string p[];
      int n = StringSplit(lines[i], '|', p);
      string kind = (n > 0) ? p[0] : "";
      if(kind == "EX" && n == 7)
        {
         NNFXPos open[], sig[];
         ParsePositions(p[4], open);
         ParsePositions(p[5], sig);
         double got[];
         string log;
         bool ok = NNFXAllocate(open, sig, StringToDouble(p[3]), p[2], got, log);
         string want[];
         int nw = StringSplit(p[6], ';', want);
         bool good = ok && nw == ArraySize(got);
         string gotText = "";
         for(int k = 0; k < ArraySize(got); k++)
           {
            gotText += (k > 0 ? ";" : "") + DoubleToString(got[k], 4);
            if(good && !Near(got[k], StringToDouble(want[k]), 1e-12))
               good = false;
           }
         Result(good, StringFormat("exposure %s: expected %s got %s%s", p[1], p[6], gotText,
                                   log == "" ? "" : " [" + log + "]"));
        }
      else if(kind == "CUR" && n == 6)
        {
         string base, quote;
         bool read = NNFXCurrencies(p[2], base, quote);
         bool good;
         if(p[3] == "-")
            good = !read;
         else
            good = read && base == p[3] && quote == p[4];
         bool fx = NNFXIsFx(p[2]);
         good = good && (fx == (p[5] == "1"));
         Result(good, StringFormat("currencies %s (%s): expected %s/%s fx=%s got %s/%s fx=%s", p[1], p[2],
                                   p[3], p[4], p[5], read ? base : "-", read ? quote : "-", fx ? "1" : "0"));
        }
      else
         Result(false, "exposure case: unreadable line " + lines[i]);
     }
   Out(StringFormat("(%d exposure cases read)", ArraySize(lines)));
  }

// Information only: never counted in RESULT.
void LiveRead()
  {
   Out("");
   Out("LIVE read (information only, not a fixture; not counted in RESULT)");
   string syms[];
   int n = StringSplit(InpLiveSymbols, ',', syms);
   for(int i = 0; i < n; i++)
      syms[i] = Trim(syms[i]);
   string detail;
   if(!NNFXWaitConnected(syms, InpConnectWait, detail))
     {
      Out("LIVE: " + detail + "; no live read");
      return;
     }
   Out("LIVE connection: " + detail);
   Out(StringFormat("LIVE balance %.2f %s, risk %.2f%%", AccountInfoDouble(ACCOUNT_BALANCE),
                    AccountInfoString(ACCOUNT_CURRENCY), InpLiveRiskPct));
   for(int i = 0; i < n; i++)
     {
      string s = syms[i];
      double tv = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE);
      double tvl = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_LOSS);
      double tvp = SymbolInfoDouble(s, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      int digits = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
      string atrText = "ATR not ready";
      double stop = 0.0;
      int h = iATR(s, PERIOD_H1, 14);
      if(h != INVALID_HANDLE)
        {
         double atr[1];
         for(int k = 0; k < 40; k++)
           {
            if(CopyBuffer(h, 0, 1, 1, atr) == 1 && atr[0] > 0)
              {
               stop = 1.5 * atr[0];
               atrText = StringFormat("ATR(14) H1 %s, stop 1.5xATR %s", DoubleToString(atr[0], digits),
                                      DoubleToString(stop, digits));
               break;
              }
            Sleep(250);
           }
         IndicatorRelease(h);
        }
      string sizeText = "";
      if(stop > 0.0)
        {
         NNFXSize sz;
         double used;
         bool ok = NNFXSizeForSymbol(s, InpLiveRiskPct, stop, sz, used);
         sizeText = ok ? StringFormat("half %.2f total %.2f risk %.2f of target %.2f%s", sz.half_lots, sz.total_lots,
                                      sz.risk_money, sz.target_risk_money, sz.skipped ? " SKIPPED " + sz.reason : "")
                       : "not sized: " + sz.reason;
        }
      Out(StringFormat("LIVE %s: tick value %.5f, for a loss %.5f, for a profit %.5f, used %.5f (OD-6); %s; %s",
                       s, tv, tvl, tvp, NNFXTickValueForSizing(tv, tvl), atrText, sizeText));
     }
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_SizingTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_SizingTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   RunSizingCases();
   RunExposureCases();
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", g_pass, g_fail, g_pass + g_fail));
   LiveRead();
   Out("== END ==");
   if(g_report != INVALID_HANDLE)
     {
      FileClose(g_report);
      Print("NNFX_SizingTest: report written to MQL5\\Files\\NNFX_SizingTest.txt");
     }
  }
//+------------------------------------------------------------------+
