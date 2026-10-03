//+------------------------------------------------------------------+
//| NNFX_EnvCheck.mq5                                                |
//| Read-only environment check for the NNFX Multi-Timeframe EA.     |
//|                                                                  |
//| Places NO orders and changes NO settings. It only:               |
//|  - reads account, terminal and symbol properties;                |
//|  - adds each listed pair to Market Watch (needed to read it);    |
//|  - may download small amounts of price/tick history on demand;   |
//|  - writes one report file: MQL5\Files\NNFX_EnvCheck.txt          |
//|                                                                  |
//| Status: NOT YET COMPILED. Compile in MetaEditor (F7) and send    |
//| any compile errors back before running.                          |
//|                                                                  |
//| Answers docs/ENVIRONMENT.md "Still to check" items 1-4.          |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

input string InpSymbols      = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY"; // Pairs to check (VP's 5 test pairs, rulebook P2)
input bool   InpCheckTicks   = true;  // Probe real-tick history (one 3-day window per year)
input int    InpTickFromYear = 2016;  // First year to probe for ticks

int g_file = INVALID_HANDLE;

// Write one line to the report and to the Experts log.
void Out(const string line)
{
   Print(line);
   if(g_file != INVALID_HANDLE)
      FileWriteString(g_file, line + "\r\n");
}

string MarginModeName(const long mode)
{
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING) return "RETAIL_NETTING";
   if(mode == ACCOUNT_MARGIN_MODE_EXCHANGE)       return "EXCHANGE (netting)";
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return "RETAIL_HEDGING";
   return "UNKNOWN (" + IntegerToString(mode) + ")";
}

string TradeModeName(const long mode)
{
   if(mode == ACCOUNT_TRADE_MODE_DEMO)    return "DEMO";
   if(mode == ACCOUNT_TRADE_MODE_CONTEST) return "CONTEST";
   if(mode == ACCOUNT_TRADE_MODE_REAL)    return "REAL";
   return "UNKNOWN (" + IntegerToString(mode) + ")";
}

// The server's first date for a symbol can read 0 until the terminal has synced; retry briefly.
datetime ServerFirstDate(const string sym)
{
   for(int attempt = 0; attempt < 20; attempt++)
   {
      long v = SeriesInfoInteger(sym, PERIOD_M1, SERIES_SERVER_FIRSTDATE);
      if(v > 0) return (datetime)v;
      Sleep(500);
   }
   return 0;
}

void CheckAccount()
{
   Out("== ACCOUNT ==");
   Out("Server:       " + AccountInfoString(ACCOUNT_SERVER));
   Out("Company:      " + AccountInfoString(ACCOUNT_COMPANY));
   Out("Trade mode:   " + TradeModeName(AccountInfoInteger(ACCOUNT_TRADE_MODE)));
   Out("Margin mode:  " + MarginModeName(AccountInfoInteger(ACCOUNT_MARGIN_MODE)));
   Out("Currency:     " + AccountInfoString(ACCOUNT_CURRENCY));
   Out("Leverage:     1:" + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)));
   Out("Balance:      " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Out("");
}

void CheckTime(const string refSym)
{
   Out("== TIME ==");
   datetime server = TimeTradeServer();
   datetime gmt    = TimeGMT();
   long offsetSec  = (long)(server - gmt);
   Out("Server time:  " + TimeToString(server, TIME_DATE | TIME_SECONDS));
   Out("GMT:          " + TimeToString(gmt, TIME_DATE | TIME_SECONDS));
   Out("Local (PC):   " + TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
   Out(StringFormat("Server - GMT: %+.2f hours (as of now; may change with daylight saving)", offsetSec / 3600.0));
   if(SymbolSelect(refSym, true))
   {
      datetime d1 = iTime(refSym, PERIOD_D1, 0);
      datetime h4 = iTime(refSym, PERIOD_H4, 0);
      Out("Current " + refSym + " D1 candle opened (server): " + TimeToString(d1, TIME_DATE | TIME_MINUTES));
      Out("Current " + refSym + " H4 candle opened (server): " + TimeToString(h4, TIME_DATE | TIME_MINUTES));
   }
   Out("Max bars in chart (terminal setting): " + IntegerToString(TerminalInfoInteger(TERMINAL_MAXBARS)));
   Out("");
}

void CheckSymbol(const string sym)
{
   Out("== " + sym + " ==");
   if(!SymbolSelect(sym, true))
   {
      Out("NOT FOUND on this server (check the broker's exact symbol name)");
      Out("");
      return;
   }
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
   Out("Digits / point:            " + IntegerToString(digits) + " / " + DoubleToString(point, digits));
   Out("Spread now (points):       " + IntegerToString(SymbolInfoInteger(sym, SYMBOL_SPREAD))
       + (SymbolInfoInteger(sym, SYMBOL_SPREAD_FLOAT) != 0 ? " (floating)" : " (fixed)"));
   Out("Min stop distance (points): " + IntegerToString(SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL)));
   Out("Freeze level (points):     " + IntegerToString(SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL)));
   Out("Lot min / step / max:      " + DoubleToString(SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), 2) + " / "
       + DoubleToString(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), 2) + " / "
       + DoubleToString(SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX), 2));
   Out("Tick size / tick value:    " + DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE), digits) + " / "
       + DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE), 5) + " " + AccountInfoString(ACCOUNT_CURRENCY));
   Out("Swap long / short (mode " + IntegerToString(SymbolInfoInteger(sym, SYMBOL_SWAP_MODE)) + "): "
       + DoubleToString(SymbolInfoDouble(sym, SYMBOL_SWAP_LONG), 2) + " / "
       + DoubleToString(SymbolInfoDouble(sym, SYMBOL_SWAP_SHORT), 2));
   Out("Commission:                not exposed as a symbol property in MQL5 (read from a demo deal or broker terms)");

   datetime first = ServerFirstDate(sym);
   Out("Server history starts:     " + (first > 0 ? TimeToString(first, TIME_DATE) : "unknown (not synced yet; run again)")
       + "  (M1 base; 30M/1H/4H are built from it)");
   Out("Bars on disk now 30M/1H/4H: " + IntegerToString(Bars(sym, PERIOD_M30)) + " / "
       + IntegerToString(Bars(sym, PERIOD_H1)) + " / " + IntegerToString(Bars(sym, PERIOD_H4)));

   if(InpCheckTicks)
   {
      MqlDateTime now;
      TimeToStruct(TimeTradeServer(), now);
      string found = "";
      for(int y = InpTickFromYear; y <= now.year; y++)
      {
         // A 3-day window always contains at least one weekday.
         datetime from = StringToTime(IntegerToString(y) + ".01.14 00:00");
         datetime to   = StringToTime(IntegerToString(y) + ".01.17 00:00");
         MqlTick ticks[];
         int n = CopyTicksRange(sym, ticks, COPY_TICKS_ALL, (ulong)from * 1000, (ulong)to * 1000);
         found += IntegerToString(y) + ":" + (n > 0 ? "yes" : (n == 0 ? "no" : "err" + IntegerToString(GetLastError()))) + " ";
         ResetLastError();
      }
      Out("Real ticks (mid-Jan probe): " + found);
   }
   Out("");
}

void OnStart()
{
   g_file = FileOpen("NNFX_EnvCheck.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_file == INVALID_HANDLE)
      Print("NNFX_EnvCheck: could not open report file, error ", GetLastError(), " (results still printed to the Experts log)");

   Out("NNFX_EnvCheck report, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   Out("");
   CheckAccount();

   string syms[];
   int count = StringSplit(InpSymbols, ',', syms);
   for(int i = 0; i < count; i++)
   {
      StringTrimLeft(syms[i]);
      StringTrimRight(syms[i]);
   }
   CheckTime(count > 0 ? syms[0] : _Symbol);
   for(int i = 0; i < count; i++)
      if(syms[i] != "")
         CheckSymbol(syms[i]);

   Out("== END ==");
   if(g_file != INVALID_HANDLE)
   {
      FileClose(g_file);
      Print("NNFX_EnvCheck: report written to MQL5\\Files\\NNFX_EnvCheck.txt");
   }
}
//+------------------------------------------------------------------+
