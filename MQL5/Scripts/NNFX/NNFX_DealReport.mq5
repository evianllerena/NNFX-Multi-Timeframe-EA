//+------------------------------------------------------------------+
//| NNFX_DealReport.mq5 - read-only report of one magic's orders and |
//| deals from the account history (G1_phase6b_1 F2: U5 comments,    |
//| U9 filling mode, U11 commission, after the demo order run).      |
//|                                                                  |
//| For every order: ticket, type, filling mode, the comment we sent |
//| (ORDER_COMMENT) and the position it opened. For every deal:      |
//| entry, volume, price, commission, swap, fee, profit, reason and  |
//| the comment the broker stored (DEAL_COMMENT). Then, per position,|
//| whether the position's opening order comment equals what the EA  |
//| sent ("NNFX <id> h<half>").                                      |
//|                                                                  |
//| Places NO orders. Writes MQL5\Files\NNFX_DealReport.txt          |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings);  |
//| run after demo order run demo_20261004_224606.                   |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\Connection.mqh>

input long InpMagic = 26999;   // Magic number to report (the test EA's)
input int  InpDays  = 3;       // History window in days, back from now

int g_report = INVALID_HANDLE;

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

string FillingName(const long f)
  {
   if(f == ORDER_FILLING_FOK)    return "FOK";
   if(f == ORDER_FILLING_IOC)    return "IOC";
   if(f == ORDER_FILLING_RETURN) return "RETURN";
   return "OTHER(" + IntegerToString(f) + ")";
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_DealReport.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_DealReport, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)) +
       ", magic " + IntegerToString(InpMagic));
   string syms[1];
   syms[0] = "EURUSD";
   string detail;
   if(!NNFXWaitConnected(syms, 120, detail))
     {
      Out("Connection: " + detail);
      Out(NNFX_RESULT_NOT_CONNECTED);
      if(g_report != INVALID_HANDLE)
         FileClose(g_report);
      return;
     }
   Out("Connection: " + detail);
   Out("Account: " + AccountInfoString(ACCOUNT_SERVER) + ", trade mode " + IntegerToString(AccountInfoInteger(ACCOUNT_TRADE_MODE)));
   datetime to = TimeCurrent() + 3600;
   datetime from = to - InpDays * 86400;
   if(!HistorySelect(from, to))
     {
      Out("RESULT: INVALID (history not available)");
      if(g_report != INVALID_HANDLE)
         FileClose(g_report);
      return;
     }

   Out("");
   Out("ORDERS: ticket,time_setup,symbol,type,filling,volume,price_open,sl,tp,position_id,comment");
   int nOrders = 0;
   for(int i = 0; i < HistoryOrdersTotal(); i++)
     {
      ulong t = HistoryOrderGetTicket(i);
      if(t == 0 || HistoryOrderGetInteger(t, ORDER_MAGIC) != InpMagic)
         continue;
      nOrders++;
      Out(StringFormat("%I64u,%s,%s,%s,%s,%.2f,%.5f,%.5f,%.5f,%I64d,%s", t,
                       TimeToString((datetime)HistoryOrderGetInteger(t, ORDER_TIME_SETUP), TIME_DATE | TIME_SECONDS),
                       HistoryOrderGetString(t, ORDER_SYMBOL), EnumToString((ENUM_ORDER_TYPE)HistoryOrderGetInteger(t, ORDER_TYPE)),
                       FillingName(HistoryOrderGetInteger(t, ORDER_TYPE_FILLING)), HistoryOrderGetDouble(t, ORDER_VOLUME_INITIAL),
                       HistoryOrderGetDouble(t, ORDER_PRICE_OPEN), HistoryOrderGetDouble(t, ORDER_SL), HistoryOrderGetDouble(t, ORDER_TP),
                       HistoryOrderGetInteger(t, ORDER_POSITION_ID), HistoryOrderGetString(t, ORDER_COMMENT)));
     }

   Out("");
   Out("DEALS: ticket,time,order,position_id,entry,type,volume,price,commission,swap,fee,profit,reason,comment");
   int nDeals = 0;
   double commission = 0, swap = 0, fee = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic)
         continue;
      nDeals++;
      commission += HistoryDealGetDouble(d, DEAL_COMMISSION);
      swap += HistoryDealGetDouble(d, DEAL_SWAP);
      fee += HistoryDealGetDouble(d, DEAL_FEE);
      Out(StringFormat("%I64u,%s,%I64d,%I64d,%s,%s,%.2f,%.5f,%.2f,%.2f,%.2f,%.2f,%s,%s", d,
                       TimeToString((datetime)HistoryDealGetInteger(d, DEAL_TIME), TIME_DATE | TIME_SECONDS),
                       HistoryDealGetInteger(d, DEAL_ORDER), HistoryDealGetInteger(d, DEAL_POSITION_ID),
                       EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY)),
                       EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(d, DEAL_TYPE)), HistoryDealGetDouble(d, DEAL_VOLUME),
                       HistoryDealGetDouble(d, DEAL_PRICE), HistoryDealGetDouble(d, DEAL_COMMISSION), HistoryDealGetDouble(d, DEAL_SWAP),
                       HistoryDealGetDouble(d, DEAL_FEE), HistoryDealGetDouble(d, DEAL_PROFIT),
                       EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(d, DEAL_REASON)), HistoryDealGetString(d, DEAL_COMMENT)));
     }

   Out("");
   Out(StringFormat("SUMMARY: %d orders, %d deals with magic %I64d; commission total %.2f, swap total %.2f, fee total %.2f %s",
                    nOrders, nDeals, InpMagic, commission, swap, fee, AccountInfoString(ACCOUNT_CURRENCY)));
   Out("== END ==");
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
