//+------------------------------------------------------------------+
//| Orders.mqh - the ONLY module that sends, modifies or closes      |
//| orders (docs/PLAN_PHASE6.md sections 1 and 3).                   |
//|                                                                  |
//| SAFETY: every public method of CNNFXOrders calls                 |
//| NNFXOrdersAllowed() as its first statement. Orders are allowed   |
//| only in the Strategy Tester or on a DEMO account (OD-18), and    |
//| only on a HEDGING account (A7, review 2026-10-14). This          |
//| is checked by tests/python/test_order_calls.py (S2, S2b).        |
//|                                                                  |
//| Rules: both halves carry the 1.5 x ATR stop in the same request  |
//| (M3, T1, P-5); half 1 has TP1 at 1 x ATR, half 2 no target or    |
//| the runner cap (T3, T7); SL/TP re-set from the fill price and    |
//| any fill accepted (OD-14); not sent if the stop is inside the    |
//| broker's minimum distance or the margin is not free (OD-5);      |
//| up to 3 retries 1 s apart with a duplicate check first (OD-13);  |
//| refusals a retry cannot clear are not retried (B3);              |
//| TP1 filled -> half 2 to exactly its entry at once (T2, OD-15);   |
//| trail at candle closes (T4); a stopless position with our magic  |
//| is closed at once with an alarm, a manual one only alarms (OD-8).|
//|                                                                  |
//| NNFXTestOpenWithoutStop and the Test* hooks exist only when      |
//| NNFX_TEST_BUILD is defined (the test EA NNFX_OrderTest) and      |
//| refuse outside the Strategy Tester (G2 verdict F3; G1_phase6b_1  |
//| F1: force ABORT, REFUSE stops level, REFUSE margin, MODIFY).     |
//|                                                                  |
//| Status: compiled 2026-10-04 (build 6238, 0 errors, 0 warnings;   |
//| tester order run, check_trades PASS, run 20261004_162607).       |
//| Review fixes A4, A7, B3 and trail_on (2026-10-14): not yet       |
//| compiled.                                                        |
//| G1_review2_1 F1/F2 (2026-10-16): breakeven checked on every      |
//| trade after TP1 (a rebuilt one included); a rebuilt lone half 1  |
//| (an ABORT not yet closed) is closed. Test hooks TestHoldBe,      |
//| TestHoldAbort (restart tests R5, R6).                            |
//+------------------------------------------------------------------+
#ifndef NNFX_ORDERS_MQH
#define NNFX_ORDERS_MQH

#include "OrderMath.mqh"
#include "Sizing.mqh"
#include "Connection.mqh"
#include "TradeLog.mqh"

#define NNFX_RETRIES      3      // OD-13
#define NNFX_RETRY_MS     1000   // OD-13
#define NNFX_DEVIATION    1000   // points; OD-14 accepts any fill (market execution ignores it)

// Section 1 SAFETY, the wrapper: reads the two values now (the account can change while running).
// atInit: Init only. Live and not yet logged in, the margin mode reads 0 (= netting) until login, so Init skips the
// A7 check then (review fixes set 2); every order method calls this without atInit, and the EA's start-up waits
// for login and refuses to start on a non-hedging account (NNFX_EA.mq5 ReadyToStart).
bool NNFXOrdersAllowed(string &why, const bool atInit = false)
  {
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   bool tester = (MQLInfoInteger(MQL_TESTER) != 0);
   if(!NNFXOrdersAllowedFor(mode, tester))
     {
      why = "orders refused: account trade mode " + IntegerToString(mode) + " is not DEMO and not in the tester";
      return false;
     }
   bool loggedIn = tester || (TerminalInfoInteger(TERMINAL_CONNECTED) != 0 && AccountInfoInteger(ACCOUNT_LOGIN) != 0);
   if(!loggedIn)
     {
      why = atInit ? "orders allowed: DEMO; margin mode not known before login, checked at the start-up (A7)"
                   : "orders refused: not logged in, the margin mode is not known (A7)";
      return atInit;
     }
   // A7: both halves of a trade are separate positions on one symbol; a netting account would merge them
   long margin = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(!NNFXHedgingOk(margin))
     {
      why = "orders refused: account margin mode " + IntegerToString(margin) + " is not HEDGING (A7)";
      return false;
     }
   why = tester ? "orders allowed: TESTER, hedging" : "orders allowed: DEMO, hedging";
   return true;
  }

// A8 (review fixes set 2): a close that failed, tried again from Poll
struct NNFXPendingClose
  {
   ulong             pos;
   string            trade;
   int               half;
   bool              log_close;   // write the CLOSE row here (the half is not in m_trades: an ABORT's half 1)
   string            sym;
   int               dir;
   double            lots;
   int               fails;
   datetime          last;
  };

struct NNFXTrade
  {
   string            id;
   string            sym;
   int               dir;
   ulong             pos1, pos2;      // position identifiers
   bool              open1, open2;
   double            lots;            // per half
   double            entry1, entry2;  // fill prices
   double            sl2;             // half 2's current stop
   double            atr_entry;
   double            cap_atr;         // NNFX_CAP_OFF if off
   bool              tp1_done;
   bool              trail_active;
  };

class CNNFXOrders
  {
private:
   long              m_magic;
   CNNFXTradeLog    *m_log;
   string            m_why;
   bool              m_session_checked;
   bool              m_algo_alarmed;  // "Algo Trading is off" alarmed (once until it is back on)
   NNFXTrade         m_trades[];
   ulong             m_alarmed[];     // manual stopless positions already alarmed (one alarm each)
   double            m_sl_atr, m_tp1_atr, m_trail_start, m_trail_dist;
   bool              m_trail_on;   // T4 on/off, the same setting the rules core gets (review 2026-10-14)
   // A1/A8 (review fixes set 2): closes that failed, tried again from Poll (NNFXPendingDue)
   NNFXPendingClose  m_pc[];
   // A1: breakeven moves that failed, per trade id
   string            m_be_id[];
   int               m_be_fails[];
   datetime          m_be_last[];
#ifdef NNFX_TEST_BUILD
   bool              m_lose_next_reply;
   bool              m_fail_next_be;        // one-shot: the next BE stop move is refused -> retried (A1)
   bool              m_fail_next_close;     // one-shot: the next close is refused -> pending, retried (A8)
   bool              m_fail_next_half2;     // one-shot: half 2's send fails -> ABORT
   long              m_stops_override;      // one-shot: stops level in points (-1 = off) -> REFUSE
   double            m_margin_override;     // one-shot: free margin (-1 = off) -> REFUSE (OD-5)
   int               m_fill_offset;         // one-shot: plan SL/TP from price + dir x points -> MODIFY (OD-14)
   string            m_hold_be_id;          // every BE move of this trade refused until a restart (G1_review2_1 F1)
   bool              m_hold_abort;          // the next ABORT's half 1: every close refused until a restart (F2)
   ulong             m_hold_close_pos;      // the position whose closes are refused (0 = none)
#endif

   void              Row(NNFXLogRow &r)
     {
      r.magic = m_magic;
      if(m_log != NULL)
         m_log.Write(r);
     }

   void              Note(const string event, const string tradeId, const string sym, const string note,
                          const ulong ticket = 0)
     {
      NNFXLogRow r;
      NNFXLogRowClear(r);
      r.event = event;
      r.trade_id = tradeId;
      r.symbol = sym;
      r.ticket = ticket;
      r.note = note;
      Row(r);
     }

   ENUM_ORDER_TYPE_FILLING Filling(const string sym)
     {
      long modes = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
      if((modes & SYMBOL_FILLING_FOK) != 0)
         return ORDER_FILLING_FOK;
      if((modes & SYMBOL_FILLING_IOC) != 0)
         return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
     }

   string            Comment(const string tradeId, const int half)
     {
      return "NNFX " + tradeId + " h" + IntegerToString(half);
     }

   // Our open position for this trade and half (magic + comment), or 0.
   ulong             FindPosition(const string sym, const string comment)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) == m_magic && PositionGetString(POSITION_SYMBOL) == sym &&
            PositionGetString(POSITION_COMMENT) == comment)
            return (ulong)PositionGetInteger(POSITION_IDENTIFIER);
        }
      return 0;
     }

   // Sends a market order, retrying up to NNFX_RETRIES times. Before every retry it looks for a
   // position with this comment, so a request whose reply was lost is never sent twice (OD-13).
   // Returns the position identifier, or 0.
   ulong             SendOpen(MqlTradeRequest &req, const string tradeId, const int half)
     {
      for(int attempt = 0; attempt <= NNFX_RETRIES; attempt++)
        {
         if(attempt > 0)
           {
            ulong existing = FindPosition(req.symbol, req.comment);
            if(existing != 0)
              {
               Note("RETRY", tradeId, req.symbol, "half " + IntegerToString(half) +
                    ": position already exists (reply lost?), not sent again; position " + IntegerToString((long)existing));
               return existing;
              }
            Sleep(NNFX_RETRY_MS);
            MqlTick tick;
            if(SymbolInfoTick(req.symbol, tick))
               req.price = (req.type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
           }
         MqlTradeResult res;
         ZeroMemory(res);
         bool sent = OrderSend(req, res);
#ifdef NNFX_TEST_BUILD
         if(m_lose_next_reply && sent)
           {
            m_lose_next_reply = false;
            Note("RETRY", tradeId, req.symbol, "TEST: reply of a filled request deliberately dropped");
            continue;
           }
#endif
         if(sent && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
           {
            ulong pos = FindPosition(req.symbol, req.comment);
            if(pos != 0)
               return pos;
            if(res.deal > 0 && HistoryDealSelect(res.deal))
               return (ulong)HistoryDealGetInteger(res.deal, DEAL_POSITION_ID);
           }
         Note("RETRY", tradeId, req.symbol, "half " + IntegerToString(half) + " attempt " + IntegerToString(attempt + 1) +
              " retcode " + IntegerToString(res.retcode) + " " + res.comment);
         // Algo Trading off at the terminal (10027) or the server (10026): a retry cannot recover (G1_phase6b_2 note 2)
         if(res.retcode == TRADE_RETCODE_CLIENT_DISABLES_AT || res.retcode == TRADE_RETCODE_SERVER_DISABLES_AT)
           {
            Note("RETRY", tradeId, req.symbol, "Algo Trading is off (retcode " + IntegerToString(res.retcode) + "): not retried");
            Alert("NNFX: Algo Trading is off (retcode ", res.retcode, "): orders cannot be sent");
            return 0;
           }
         // B3: no money, invalid stops/volume/fill, market closed...: a retry 1 s later cannot succeed, and each
         // wasted attempt blocks this thread (and leaves half 1 alone while half 2 is retried)
         if(!NNFXRetcodeRetryable(res.retcode))   // OrderSend returns false with the retcode set for most refusals
           {
            Note("RETRY", tradeId, req.symbol, "half " + IntegerToString(half) + ": retcode " + IntegerToString(res.retcode) +
                 " cannot clear on a retry: not retried (B3)");
            return 0;
           }
        }
      return 0;
     }

   bool              SelectPosition(const ulong posId)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket != 0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER) == posId)
            return true;
        }
      return false;
     }

   bool              ModifyPosition(const ulong posId, const double sl, const double tp)
     {
      if(!SelectPosition(posId))
         return false;
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action = TRADE_ACTION_SLTP;
      req.position = (ulong)PositionGetInteger(POSITION_TICKET);
      req.symbol = PositionGetString(POSITION_SYMBOL);
      req.sl = sl;
      req.tp = tp;
      req.magic = m_magic;
      return OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE;
     }

   // A8 (review fixes set 2): the price is read and checked before the request; a refusal that can clear is tried
   // again up to NNFX_RETRIES times 1 s apart, the position looked up again first (it may have closed meanwhile).
   bool              ClosePosition(const ulong posId)
     {
#ifdef NNFX_TEST_BUILD
      if(m_fail_next_close && MQLInfoInteger(MQL_TESTER) != 0 && SelectPosition(posId))
        {
         m_fail_next_close = false;
         Note("TEST", "", PositionGetString(POSITION_SYMBOL), "TEST: close of position " + IntegerToString((long)posId) +
              " forced to fail", posId);
         return false;
        }
      if(m_hold_close_pos != 0 && posId == m_hold_close_pos && MQLInfoInteger(MQL_TESTER) != 0 && SelectPosition(posId))
        {
         Note("TEST", "", PositionGetString(POSITION_SYMBOL), "TEST: close of position " + IntegerToString((long)posId) +
              " refused (held until the restart)", posId);
         return false;
        }
#endif
      for(int attempt = 0; attempt <= NNFX_RETRIES; attempt++)
        {
         if(attempt > 0)
            Sleep(NNFX_RETRY_MS);
         if(!SelectPosition(posId))
            return attempt > 0;   // gone during the retries: closed (by us or its stop); Poll logs how
         MqlTradeRequest req;
         MqlTradeResult res;
         ZeroMemory(req);
         ZeroMemory(res);
         string sym = PositionGetString(POSITION_SYMBOL);
         bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         MqlTick tick;
         if(!SymbolInfoTick(sym, tick) || !(isBuy ? tick.bid > 0 : tick.ask > 0))
           {
            Note("RETRY", "", sym, "close of position " + IntegerToString((long)posId) + ": no price (SymbolInfoTick), not sent (A8)", posId);
            continue;
           }
         req.action = TRADE_ACTION_DEAL;
         req.position = (ulong)PositionGetInteger(POSITION_TICKET);
         req.symbol = sym;
         req.volume = PositionGetDouble(POSITION_VOLUME);
         req.type = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price = isBuy ? tick.bid : tick.ask;
         req.deviation = NNFX_DEVIATION;
         req.type_filling = Filling(sym);
         req.magic = m_magic;
         if(OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
            return true;
         Note("RETRY", "", sym, "close of position " + IntegerToString((long)posId) + " attempt " + IntegerToString(attempt + 1) +
              " retcode " + IntegerToString(res.retcode) + " " + res.comment, posId);
         if(!NNFXRetcodeRetryable(res.retcode))
            return false;
        }
      return false;
     }

   // A8: a close that failed goes on the pending list and is tried again from Poll.
   void              AddPendingClose(const ulong posId, const string tradeId, const int half, const bool logClose)
     {
      for(int i = 0; i < ArraySize(m_pc); i++)
         if(m_pc[i].pos == posId)
            return;
      if(!SelectPosition(posId))
         return;   // already gone
      int n = ArraySize(m_pc);
      ArrayResize(m_pc, n + 1);
      m_pc[n].pos = posId;
      m_pc[n].trade = tradeId;
      m_pc[n].half = half;
      m_pc[n].log_close = logClose;
      m_pc[n].sym = PositionGetString(POSITION_SYMBOL);
      m_pc[n].dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      m_pc[n].lots = PositionGetDouble(POSITION_VOLUME);
      m_pc[n].fails = 1;
      m_pc[n].last = TimeCurrent();
      Note("RETRY", tradeId, m_pc[n].sym, StringFormat("close of position %I64u failed: pending, tried again (A8)", posId), posId);
     }

   void              RemovePendingClose(const int i)
     {
      int last = ArraySize(m_pc) - 1;
      if(i != last)
         m_pc[i] = m_pc[last];
      ArrayResize(m_pc, last);
     }

   // A CLOSE row for a half this object does not track (an ABORT's half 1).
   void              LogClose(const string tradeId, const int half, const string sym, const int dir, const ulong posId,
                              const double lots, const string note)
     {
      double cprice = 0;
      long creason = -1;
      if(!ClosingDeal(posId, cprice, creason))
         return;
      NNFXLogRow c;
      NNFXLogRowClear(c);
      c.event = "CLOSE";
      c.trade_id = tradeId;
      c.half = half;
      c.symbol = sym;
      c.dir = dir;
      c.ticket = posId;
      c.lots = lots;
      c.price = cprice;
      c.tick_size = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      c.note = note + ", deal reason " + IntegerToString(creason);
      Row(c);
     }

   // A8: the pending closes, each when due (NNFXPendingDue). Called from Poll.
   void              RetryPendingCloses(void)
     {
      for(int i = ArraySize(m_pc) - 1; i >= 0; i--)
        {
         ulong posId = m_pc[i].pos;
         if(!SelectPosition(posId))
           {
            // gone (its stop or target): Poll logs the halves it tracks; an ABORT's half 1 is logged here
            if(m_pc[i].log_close)
               LogClose(m_pc[i].trade, m_pc[i].half, m_pc[i].sym, m_pc[i].dir, posId, m_pc[i].lots, "closed while pending (A8)");
            RemovePendingClose(i);
            continue;
           }
         if(!NNFXPendingDue(m_pc[i].fails, (long)(TimeCurrent() - m_pc[i].last)))
            continue;
         if(ClosePosition(posId))
           {
            Note("RETRY", m_pc[i].trade, m_pc[i].sym, StringFormat("close retry %d of position %I64u: closed (A8)", m_pc[i].fails, posId), posId);
            if(m_pc[i].log_close)
               LogClose(m_pc[i].trade, m_pc[i].half, m_pc[i].sym, m_pc[i].dir, posId, m_pc[i].lots,
                        "closed by retry " + IntegerToString(m_pc[i].fails) + " (A8)");
            RemovePendingClose(i);
            continue;
           }
         m_pc[i].fails++;
         m_pc[i].last = TimeCurrent();
         Note("RETRY", m_pc[i].trade, m_pc[i].sym, StringFormat("close retry of position %I64u failed (%d failures)", posId, m_pc[i].fails), posId);
         if(m_pc[i].fails == NNFX_PENDING_FAST_N)
           {
            Note("ALARM", m_pc[i].trade, m_pc[i].sym, StringFormat("position %I64u still not closed after %d tries; tried every %d s from now",
                                                                   posId, m_pc[i].fails, NNFX_PENDING_SLOW_S), posId);
            Alert("NNFX: position ", posId, " could not be closed after ", m_pc[i].fails, " tries");
           }
        }
     }

   int               BeIndex(const string tradeId)
     {
      for(int i = 0; i < ArraySize(m_be_id); i++)
         if(m_be_id[i] == tradeId)
            return i;
      return -1;
     }

   // A1: after TP1, half 2's stop at the broker must be at breakeven or better. A failed move is tried again when
   // due; if the price has already passed breakeven, half 2 is closed at market (NNFXBeAction 2). Called from Poll.
   // G1_review2_1 F1: EVERY trade after TP1 is checked, not only those with a failed move on record (that record is in
   // memory only). A trade rebuilt after a restart, whose refused move was not yet retried or whose TP1 filled while
   // the EA was stopped, has tp1_done from the deal history but its stop where it was: it is set at once.
   void              MaintainBreakeven(const string via)
     {
      for(int i = 0; i < ArraySize(m_trades); i++)
        {
         if(!m_trades[i].tp1_done || !m_trades[i].open2 || !(m_trades[i].entry2 > 0) || !SelectPosition(m_trades[i].pos2))
            continue;
         string id = m_trades[i].id;
         int k = BeIndex(id);
         string sym = m_trades[i].sym;
         MqlTick tick;
         if(!SymbolInfoTick(sym, tick))
            continue;
         double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         // No failure on record: the memory's stop is checked first. A move made a moment ago is in memory (MoveStop)
         // before the terminal may show it on the position; without this it would be sent twice on a live server.
         if(k < 0 && NNFXBeAction(m_trades[i].dir, m_trades[i].entry2, m_trades[i].sl2, tick.bid, tick.ask, tickSize) == 0)
            continue;
         int action = NNFXBeAction(m_trades[i].dir, m_trades[i].entry2, PositionGetDouble(POSITION_SL), tick.bid, tick.ask, tickSize);
         if(action == 0)
           {
            if(k >= 0)
               BeForget(k);   // in place (moved by a retry, the trail, or by hand)
            continue;
           }
         if(k < 0)
           {
            // not at breakeven after TP1 and no failed move on record: a restart, or TP1 while stopped. Due now.
            BeFailed(id);
            k = BeIndex(id);
            m_be_fails[k] = 0;
            Note("RETRY", id, sym, "BE: not in place after TP1 and no failed move on record (restart, or TP1 while stopped): set now (A1)",
                 m_trades[i].pos2);
           }
         if(!NNFXPendingDue(m_be_fails[k], (long)(TimeCurrent() - m_be_last[k])))
            continue;
         if(action == 2)
           {
            Note("EXIT", id, sym, StringFormat("BE price already passed after %d failed moves: half 2 closed at market (A1, RV-A1)",
                                               m_be_fails[k]), m_trades[i].pos2);
            if(!ClosePosition(m_trades[i].pos2))
               AddPendingClose(m_trades[i].pos2, id, 2, false);
            BeForget(k);
            continue;
           }
         string how = (m_be_fails[k] == 0) ? "restored after a restart" : "retry " + IntegerToString(m_be_fails[k]);
         if(MoveStop(id, NNFXBreakevenPrice(m_trades[i].entry2), "BE", 0.0, 0.0, "via=" + via + "; " + how + " (A1)"))
           {
            BeForget(k);
            continue;
           }
         m_be_fails[k]++;
         m_be_last[k] = TimeCurrent();
         if(m_be_fails[k] == NNFX_PENDING_FAST_N)
           {
            Note("ALARM", id, sym, StringFormat("BE: still not set after %d tries; tried every %d s from now", m_be_fails[k],
                                                NNFX_PENDING_SLOW_S), m_trades[i].pos2);
            Alert("NNFX: breakeven of ", id, " still not set after ", m_be_fails[k], " tries");
           }
        }
     }

   void              BeFailed(const string tradeId)
     {
      if(BeIndex(tradeId) >= 0)
         return;
      int n = ArraySize(m_be_id);
      ArrayResize(m_be_id, n + 1);
      ArrayResize(m_be_fails, n + 1);
      ArrayResize(m_be_last, n + 1);
      m_be_id[n] = tradeId;
      m_be_fails[n] = 1;
      m_be_last[n] = TimeCurrent();
     }

   void              BeForget(const int k)
     {
      int last = ArraySize(m_be_id) - 1;
      m_be_id[k] = m_be_id[last];
      m_be_fails[k] = m_be_fails[last];
      m_be_last[k] = m_be_last[last];
      ArrayResize(m_be_id, last);
      ArrayResize(m_be_fails, last);
      ArrayResize(m_be_last, last);
     }

   // The deal that closed a position: its price and reason. False if the position is still open.
   bool              ClosingDeal(const ulong posId, double &price, long &reason)
     {
      if(!HistorySelectByPosition(posId))
         return false;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d != 0 && HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_OUT)
           {
            price = HistoryDealGetDouble(d, DEAL_PRICE);
            reason = HistoryDealGetInteger(d, DEAL_REASON);
            return true;
           }
        }
      return false;
     }

   int               FindTrade(const string tradeId)
     {
      for(int i = 0; i < ArraySize(m_trades); i++)
         if(m_trades[i].id == tradeId)
            return i;
      return -1;
     }

   void              LogFill(const string event, NNFXTrade &t, const int half, const ulong posId, const double prevSl,
                             const double planned, const double target, const double balance, const double riskPct,
                             const double tickValue, const string note)
     {
      if(!SelectPosition(posId))
         return;
      NNFXLogRow r;
      NNFXLogRowClear(r);
      r.event = event;
      r.trade_id = t.id;
      r.half = half;
      r.symbol = t.sym;
      r.dir = t.dir;
      r.ticket = posId;
      r.lots = PositionGetDouble(POSITION_VOLUME);
      r.price = PositionGetDouble(POSITION_PRICE_OPEN);
      r.sl = PositionGetDouble(POSITION_SL);
      r.tp = PositionGetDouble(POSITION_TP);
      r.prev_sl = prevSl;
      r.entry = r.price;
      r.atr_entry = t.atr_entry;
      r.balance = balance;
      r.risk_pct = riskPct;
      r.tick_size = SymbolInfoDouble(t.sym, SYMBOL_TRADE_TICK_SIZE);
      r.tick_value = tickValue;
      r.planned_risk = planned;
      r.target_risk = target;
      r.cap_atr = t.cap_atr;
      r.note = note;
      Row(r);
     }

public:
                     CNNFXOrders(void) : m_magic(0), m_log(NULL), m_session_checked(false), m_algo_alarmed(false),
                     m_sl_atr(1.5), m_tp1_atr(1.0), m_trail_start(2.0), m_trail_dist(1.5), m_trail_on(true)
     {
#ifdef NNFX_TEST_BUILD
      m_lose_next_reply = false;
      m_fail_next_be = false;
      m_fail_next_close = false;
      m_fail_next_half2 = false;
      m_stops_override = -1;
      m_margin_override = -1.0;
      m_fill_offset = 0;
      m_hold_be_id = "";
      m_hold_abort = false;
      m_hold_close_pos = 0;
#endif
     }

   bool              Init(const long magic, CNNFXTradeLog *log, const double slAtr, const double tp1Atr,
                          const double trailStart, const double trailDist, const bool trailOn = true)
     {
      if(!NNFXOrdersAllowed(m_why, true))
        {
         Print("NNFX orders: ", m_why);
         return false;
        }
      m_magic = magic;
      m_log = log;
      m_sl_atr = slAtr;
      m_tp1_atr = tp1Atr;
      m_trail_start = trailStart;
      m_trail_dist = trailDist;
      m_trail_on = trailOn;
      Note("INFO", "", "", m_why + (trailOn ? "" : "; T4 trail off"));
      return true;
     }

   // Opens both halves of one trade. atr: ATR(14) of the decision candle. minLots: each half at the
   // broker's minimum lot instead of the sized amount (demo test only; still refused above target).
   bool              OpenTrade(const string sym, const int dir, const double atr, const double riskPct,
                               const double capAtr, const string tradeId, const bool minLots)
     {
      if(!NNFXOrdersAllowed(m_why))
        {
         Note("REFUSE", tradeId, sym, m_why);
         return false;
        }
      // Carry-over 1: wait for login before the first order of a session. In the Strategy Tester there is
      // no server connection to wait for, so the check applies to live (demo) running only.
      if(!m_session_checked && MQLInfoInteger(MQL_TESTER) != 0)
         m_session_checked = true;
      if(!m_session_checked)
        {
         string syms[1];
         syms[0] = sym;
         string detail;
         if(!NNFXWaitConnected(syms, 60, detail))
           {
            Note("REFUSE", tradeId, sym, "not connected: " + detail);
            return false;
           }
         m_session_checked = true;
        }
      // Algo Trading pre-check, live (G1_phase6b_2 note 2): off at the terminal or for this EA = refused, alarm once
      if(MQLInfoInteger(MQL_TESTER) == 0 &&
         (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)))
        {
         Note("REFUSE", tradeId, sym, "Algo Trading is off (terminal or this EA): nothing sent");
         if(!m_algo_alarmed)
            Alert("NNFX: Algo Trading is off: orders are refused until it is switched on");
         m_algo_alarmed = true;
         return false;
        }
      m_algo_alarmed = false;
      if((dir != 1 && dir != -1) || !(atr > 0))
        {
         Note("REFUSE", tradeId, sym, "bad direction or ATR");
         return false;
        }
      // Size (6a) from values read now; the stop distance the lots are sized for.
      double stopDist = m_sl_atr * atr;
      NNFXSize size;
      double tickValue;
      if(!NNFXSizeForSymbol(sym, riskPct, stopDist, size, tickValue))
        {
         Note("REFUSE", tradeId, sym, size.reason);
         return false;
        }
      if(size.skipped)
        {
         Note("REFUSE", tradeId, sym, size.reason);
         return false;
        }
      double half = size.half_lots;
      if(minLots)
         half = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      MqlTick tick;
      if(!SymbolInfoTick(sym, tick))
        {
         Note("REFUSE", tradeId, sym, "no price");
         return false;
        }
      double price = (dir == 1) ? tick.ask : tick.bid;
      double basis = price;   // the price SL/TP are planned from before the fill
#ifdef NNFX_TEST_BUILD
      if(m_fill_offset != 0 && MQLInfoInteger(MQL_TESTER) != 0)
        {
         // > 0: towards profit, the planned stop is closer; < 0: an ADVERSE fill (the fill is worse than the price
         // the stop was planned from), so the stop sent is wider than 1.5 x ATR until the MODIFY (G1_phase6b_2 note 3)
         basis = price + dir * m_fill_offset * point;
         Note("TEST", tradeId, sym, StringFormat("TEST: SL/TP planned from %d points away from the price (fill offset%s)",
                                                 m_fill_offset, m_fill_offset < 0 ? ", adverse" : ""));
        }
      m_fill_offset = 0;
#endif
      double sl, tp1, tp2;
      if(!NNFXPlanPrices(dir, basis, atr, tickSize, m_sl_atr, m_tp1_atr, capAtr, sl, tp1, tp2))
        {
         Note("REFUSE", tradeId, sym, "prices not plannable");
         return false;
        }
      long stopsLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
#ifdef NNFX_TEST_BUILD
      if(m_stops_override >= 0 && MQLInfoInteger(MQL_TESTER) != 0)
        {
         stopsLevel = m_stops_override;
         Note("TEST", tradeId, sym, "TEST: stops level overridden to " + IntegerToString(m_stops_override) + " points");
        }
      m_stops_override = -1;
#endif
      if(!NNFXStopDistanceOk(price, sl, stopsLevel, point) || !NNFXStopDistanceOk(price, tp1, stopsLevel, point))
        {
         Note("REFUSE", tradeId, sym, "stop or target inside the broker's minimum distance (" + IntegerToString(stopsLevel) + " points)");
         return false;
        }
      // the risk as planned: from the price the stop was planned from (basis = price, except in the test build's
      // fill-offset test, where it plays the requested price and the fill comes 20 points away; G1_phase6b_2 note 3)
      double planned = 2.0 * NNFXPlannedRisk(half, basis, sl, tickSize, tickValue);
      if(planned > size.target_risk_money + 1e-6)
        {
         Note("REFUSE", tradeId, sym, StringFormat("planned risk %.2f above target %.2f", planned, size.target_risk_money));
         return false;
        }
      // OD-5: skip and log if the margin for both halves is not free.
      double margin = 0.0;
      ENUM_ORDER_TYPE type = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!OrderCalcMargin(type, sym, 2.0 * half, price, margin))
        {
         Note("REFUSE", tradeId, sym, "margin could not be calculated, error " + IntegerToString(GetLastError()));
         return false;
        }
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
#ifdef NNFX_TEST_BUILD
      if(m_margin_override >= 0.0 && MQLInfoInteger(MQL_TESTER) != 0)
        {
         free = m_margin_override;
         Note("TEST", tradeId, sym, StringFormat("TEST: free margin overridden to %.2f", m_margin_override));
        }
      m_margin_override = -1.0;
#endif
      if(margin > free)
        {
         Note("REFUSE", tradeId, sym, StringFormat("not enough free margin: needs %.2f, free %.2f (OD-5)", margin, free));
         return false;
        }

      NNFXTrade t;
      t.id = tradeId;
      t.sym = sym;
      t.dir = dir;
      t.pos1 = 0;
      t.pos2 = 0;
      t.open1 = false;
      t.open2 = false;
      t.lots = half;
      t.entry1 = 0;
      t.entry2 = 0;
      t.sl2 = 0;
      t.atr_entry = atr;
      t.cap_atr = capAtr;
      t.tp1_done = false;
      t.trail_active = false;

      MqlTradeRequest req;
      ZeroMemory(req);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = sym;
      req.volume = half;
      req.type = type;
      req.price = price;
      req.sl = sl;
      req.tp = tp1;
      req.deviation = NNFX_DEVIATION;
      req.type_filling = Filling(sym);
      req.magic = m_magic;
      req.comment = Comment(tradeId, 1);
      t.pos1 = SendOpen(req, tradeId, 1);
      if(t.pos1 == 0)
        {
         Note("REFUSE", tradeId, sym, "half 1 not opened");
         return false;
        }
      t.open1 = true;
      req.tp = tp2;
      req.comment = Comment(tradeId, 2);
      bool failHalf2 = false;
#ifdef NNFX_TEST_BUILD
      failHalf2 = m_fail_next_half2 && MQLInfoInteger(MQL_TESTER) != 0;
      m_fail_next_half2 = false;
      if(failHalf2)
         Note("TEST", tradeId, sym, "TEST: half 2 send forced to fail");
#endif
      t.pos2 = failHalf2 ? 0 : SendOpen(req, tradeId, 2);
      if(t.pos2 == 0)
        {
         // Never leave one half alone: halves must be equal (M5). Log half 1's OPEN and its close.
         LogFill("OPEN", t, 1, t.pos1, 0.0, 0.0, size.target_risk_money, balance, riskPct, tickValue, "half 2 failed");
#ifdef NNFX_TEST_BUILD
         if(m_hold_abort)
           {
            m_hold_abort = false;
            m_hold_close_pos = t.pos1;
           }
#endif
         bool closed = ClosePosition(t.pos1);
         if(closed)
            LogClose(tradeId, 1, sym, dir, t.pos1, half, "closed by ABORT");
         Note("ABORT", tradeId, sym, closed ? "half 2 not opened; half 1 closed" :
              "half 2 not opened; HALF 1 CLOSE FAILED; pending, tried again (A8)", t.pos1);
         if(!closed)
           {
            AddPendingClose(t.pos1, tradeId, 1, true);
            Alert("NNFX: ABORT of ", tradeId, ": half 1 could not be closed yet; tried again");
           }
         return false;
        }
      t.open2 = true;

      // Read back what the broker holds, then re-set SL/TP from each half's fill price (OD-14).
      ulong ids[2];
      ids[0] = t.pos1;
      ids[1] = t.pos2;
      // A4: 0 = fill unknown (the half was already gone at readback); never left uninitialised
      double entries[2] = {0.0, 0.0};
      for(int h = 0; h < 2; h++)
        {
         if(!SelectPosition(ids[h]))
            continue;
         entries[h] = PositionGetDouble(POSITION_PRICE_OPEN);
         double heldSl = PositionGetDouble(POSITION_SL);
         double fsl, ftp1, ftp2;
         NNFXPlanPrices(dir, entries[h], atr, tickSize, m_sl_atr, m_tp1_atr, capAtr, fsl, ftp1, ftp2);
         double wantTp = (h == 0) ? ftp1 : ftp2;
         double fPlanned = 2.0 * NNFXPlannedRisk(half, entries[h], fsl, tickSize, tickValue);
         LogFill("OPEN", t, h + 1, ids[h], 0.0, fPlanned, size.target_risk_money, balance, riskPct, tickValue,
                 // "requested" = the price SL/TP were planned from (the price sent, or the test's offset basis), so
                 // check_trades can bound the window before the MODIFY by the slippage (G1_phase6b_2 note 3)
                 StringFormat("requested %s, slippage %s, filling %d", DoubleToString(basis, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                              DoubleToString(entries[h] - basis, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), (int)req.type_filling));
         if(MathAbs(heldSl - fsl) > tickSize * 0.5 || MathAbs(PositionGetDouble(POSITION_TP) - wantTp) > tickSize * 0.5)
           {
            if(ModifyPosition(ids[h], fsl, wantTp))
               LogFill("MODIFY", t, h + 1, ids[h], heldSl, fPlanned, size.target_risk_money, balance, riskPct, tickValue,
                       "SL/TP re-set from the fill price (OD-14)");
            else
               Note("ALARM", tradeId, sym, "half " + IntegerToString(h + 1) + ": SL/TP could not be re-set from the fill");
           }
        }
      t.entry1 = entries[0];
      t.entry2 = entries[1];
      if(SelectPosition(t.pos2))
         t.sl2 = PositionGetDouble(POSITION_SL);
      int n = ArraySize(m_trades);
      ArrayResize(m_trades, n + 1);
      m_trades[n] = t;
      return true;
     }

   // Follows closures (SL, TP1, TP2) from the deal history; on TP1 moves half 2 to breakeven at once
   // (T2, OD-15). Call from OnTradeTransaction (via "transaction") and on every tick (via "tick");
   // the BE row records which one moved the stop (G1_phase6b_1 F5, U12).
   void              Poll(const string via)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      for(int i = 0; i < ArraySize(m_trades); i++)
        {
         for(int h = 1; h <= 2; h++)
           {
            bool isOpen = (h == 1) ? m_trades[i].open1 : m_trades[i].open2;
            ulong posId = (h == 1) ? m_trades[i].pos1 : m_trades[i].pos2;
            if(!isOpen || SelectPosition(posId))
               continue;
            double price = 0;
            long reason = -1;
            if(!ClosingDeal(posId, price, reason))
               continue;
            if(h == 1)
               m_trades[i].open1 = false;
            else
               m_trades[i].open2 = false;
            string ev = "CLOSE";
            if(reason == DEAL_REASON_SL)
               ev = "SL";
            else if(reason == DEAL_REASON_TP)
               ev = (h == 1) ? "TP1" : "TP2";
            NNFXLogRow r;
            NNFXLogRowClear(r);
            r.event = ev;
            r.trade_id = m_trades[i].id;
            r.half = h;
            r.symbol = m_trades[i].sym;
            r.dir = m_trades[i].dir;
            r.ticket = posId;
            r.lots = m_trades[i].lots;
            r.price = price;
            r.entry = (h == 1) ? m_trades[i].entry1 : m_trades[i].entry2;
            r.atr_entry = m_trades[i].atr_entry;
            r.tick_size = SymbolInfoDouble(m_trades[i].sym, SYMBOL_TRADE_TICK_SIZE);
            r.note = "deal reason " + IntegerToString(reason);
            Row(r);
            if(ev == "TP1")
              {
               m_trades[i].tp1_done = true;
               // A4: half 2's fill unknown at readback: read it from the position if it is still there
               if(m_trades[i].open2 && !(m_trades[i].entry2 > 0) && SelectPosition(m_trades[i].pos2))
                  m_trades[i].entry2 = PositionGetDouble(POSITION_PRICE_OPEN);
               if(m_trades[i].open2 && !(m_trades[i].entry2 > 0))
                  Note("ALARM", m_trades[i].id, m_trades[i].sym, "TP1: half 2's fill price is unknown, no breakeven move (A4)");
               else if(m_trades[i].open2)
                  MoveStop(m_trades[i].id, NNFXBreakevenPrice(m_trades[i].entry2), "BE", 0.0, 0.0, "via=" + via);
              }
           }
        }
      MaintainBreakeven(via);   // A1: failed BE moves, tried again when due
      RetryPendingCloses();     // A8: failed closes, tried again when due
     }

   // Moves half 2's stop (BE or TRAIL). Never backwards.
   bool              MoveStop(const string tradeId, const double newSl, const string event, const double close,
                              const double atr, const string note = "")
     {
      if(!NNFXOrdersAllowed(m_why))
        {
         Note("REFUSE", tradeId, "", m_why);
         return false;
        }
      int k = FindTrade(tradeId);
      if(k < 0 || !m_trades[k].open2 || !SelectPosition(m_trades[k].pos2))
         return false;
      double prev = PositionGetDouble(POSITION_SL);
      if((newSl - prev) * m_trades[k].dir <= 0.0)
         return false;   // never backwards
      double tp = PositionGetDouble(POSITION_TP);
      bool forced = false;
#ifdef NNFX_TEST_BUILD
      bool held = (m_hold_be_id != "" && m_hold_be_id == tradeId);
      forced = (m_fail_next_be || held) && event == "BE" && MQLInfoInteger(MQL_TESTER) != 0;
      if(forced)
        {
         if(!held)
            m_fail_next_be = false;
         Note("TEST", tradeId, m_trades[k].sym, held ? "TEST: BE stop move refused (held until the restart)" :
              "TEST: BE stop move forced to fail", m_trades[k].pos2);
        }
#endif
      if(forced || !ModifyPosition(m_trades[k].pos2, newSl, tp))
        {
         if(event == "BE")
           {
            // A1: not the end of it: MaintainBreakeven tries again (ALARM after NNFX_PENDING_FAST_N failures)
            Note("RETRY", tradeId, m_trades[k].sym, "BE: stop move to " + DoubleToString(newSl, 10) + " refused; tried again (A1)",
                 m_trades[k].pos2);
            BeFailed(tradeId);
           }
         else
            Note("ALARM", tradeId, m_trades[k].sym, event + ": stop move to " + DoubleToString(newSl, 10) + " refused by the broker");
         return false;
        }
      m_trades[k].sl2 = newSl;
      NNFXLogRow r;
      NNFXLogRowClear(r);
      r.event = event;
      r.trade_id = tradeId;
      r.half = 2;
      r.symbol = m_trades[k].sym;
      r.dir = m_trades[k].dir;
      r.ticket = m_trades[k].pos2;
      r.lots = m_trades[k].lots;
      r.sl = newSl;
      r.tp = tp;
      r.prev_sl = prev;
      r.entry = m_trades[k].entry2;
      r.atr_entry = m_trades[k].atr_entry;
      r.atr = atr;
      r.close = close;
      r.tick_size = SymbolInfoDouble(m_trades[k].sym, SYMBOL_TRADE_TICK_SIZE);
      r.note = (m_trades[k].trail_active ? "trail active" : "") + (note == "" ? "" : (m_trades[k].trail_active ? "; " : "") + note);
      Row(r);
      return true;
     }

   // At a candle close: trail half 2 of every trade after TP1 (T4, I-11).
   void              OnBarClose(const string sym, const double close, const double atr)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(!m_trail_on)   // T4 off: breakeven only, as in the rules core (InpTrailOn; review 2026-10-14)
         return;
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      for(int i = 0; i < ArraySize(m_trades); i++)
        {
         if(m_trades[i].sym != sym || !m_trades[i].tp1_done || !m_trades[i].open2 || !(m_trades[i].entry2 > 0))
            continue;
         double newSl;
         bool was = m_trades[i].trail_active;
         bool active = was;
         bool moved = NNFXTrailStep(m_trades[i].dir, m_trades[i].entry2, m_trades[i].atr_entry, m_trades[i].sl2, active,
                                    close, atr, tickSize, m_trail_start, m_trail_dist, newSl);
         m_trades[i].trail_active = active;
         if(active && !was)
           {
            NNFXLogRow r;
            NNFXLogRowClear(r);
            r.event = "TRAILON";
            r.trade_id = m_trades[i].id;
            r.half = 2;
            r.symbol = sym;
            r.dir = m_trades[i].dir;
            r.ticket = m_trades[i].pos2;
            r.entry = m_trades[i].entry2;
            r.atr_entry = m_trades[i].atr_entry;
            r.atr = atr;
            r.close = close;
            r.sl = m_trades[i].sl2;
            r.tick_size = tickSize;
            r.note = "trail switched on (T4): close is start x entry ATR beyond entry";
            Row(r);
           }
         if(moved)
            MoveStop(m_trades[i].id, newSl, "TRAIL", close, atr);
        }
     }

   // Closes whatever is left of a trade (X2-X5 or close-all).
   bool              CloseRemaining(const string tradeId, const string reason)
     {
      if(!NNFXOrdersAllowed(m_why))
        {
         Note("REFUSE", tradeId, "", m_why);
         return false;
        }
      int k = FindTrade(tradeId);
      if(k < 0)
         return false;
      Note("EXIT", tradeId, m_trades[k].sym, reason);
      bool ok = true;
      for(int h = 1; h <= 2; h++)
        {
         bool isOpen = (h == 1) ? m_trades[k].open1 : m_trades[k].open2;
         ulong posId = (h == 1) ? m_trades[k].pos1 : m_trades[k].pos2;
         if(isOpen && !ClosePosition(posId))
           {
            ok = false;
            AddPendingClose(posId, tradeId, h, false);   // A8: tried again from Poll
           }
        }
      Poll("close");
      return ok;
     }

   // Every tick: a position without a stop. Ours (our magic): closed at once with an alarm.
   // Anyone else's (manual): an alarm only, once per position (OD-8). Returns the number found.
   int               EnforceStops(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return 0;
      int found = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetDouble(POSITION_SL) != 0.0)
            continue;
         found++;
         ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         string sym = PositionGetString(POSITION_SYMBOL);
         if(PositionGetInteger(POSITION_MAGIC) == m_magic)
           {
            bool closed = ClosePosition(posId);
            Note("ALARM", "", sym, StringFormat("missing stop on our position %I64u: %s", posId,
                                                 closed ? "closed at once" : "CLOSE FAILED"), posId);
            Alert("NNFX: position ", posId, " had no stop; ", closed ? "closed" : "close FAILED");
           }
         else
           {
            bool seen = false;
            for(int k = 0; k < ArraySize(m_alarmed); k++)
               if(m_alarmed[k] == posId)
                  seen = true;
            if(!seen)
              {
               int n = ArraySize(m_alarmed);
               ArrayResize(m_alarmed, n + 1);
               m_alarmed[n] = posId;
               Note("ALARM", "", sym, StringFormat("manual position %I64u has no stop: alarm only, not closed (OD-8)", posId), posId);
               Alert("NNFX: manual position ", posId, " has no stop");
              }
           }
        }
      return found;
     }

   // Number of trades this object has opened (for test reports).
   int               TradeCount(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return 0;
      return ArraySize(m_trades);
     }

   // True if the trade still has an open half.
   bool              IsOpen(const string tradeId)
     {
      if(!NNFXOrdersAllowed(m_why))
         return false;
      int k = FindTrade(tradeId);
      return k >= 0 && (m_trades[k].open1 || m_trades[k].open2);
     }

   // Phase 6c: the trades this object manages, for the state file (State.mqh).
   int               ExportTrades(NNFXTrade &out[])
     {
      if(!NNFXOrdersAllowed(m_why))
         return 0;
      ArrayResize(out, 0);
      for(int i = 0; i < ArraySize(m_trades); i++)
         if(m_trades[i].open1 || m_trades[i].open2)
           {
            int n = ArraySize(out);
            ArrayResize(out, n + 1);
            out[n] = m_trades[i];
           }
      return ArraySize(out);
     }

   // Phase 6c: replaces this object's memory with the trades rebuilt after a restart (State.mqh NNFXRebuildPure).
   void              ImportTrades(const NNFXTrade &in[])
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      ArrayResize(m_trades, 0);
      int closed = 0;
      for(int i = 0; i < ArraySize(in); i++)
        {
         // G1_review2_1 F2: a lone half 1 whose half 2 was never opened is an ABORT whose close had not gone through
         // before the restart (A8's pending list is in memory only). It is closed now, as the ABORT intended (M5: never
         // one half alone). Not under a fallback ID ("R..."): that pairing is a guess (same second), so only alarmed.
         if(in[i].open1 && !in[i].open2 && in[i].pos2 == 0 && !in[i].tp1_done)
           {
            if(StringSubstr(in[i].id, 0, 1) != "R")
              {
               Note("EXIT", in[i].id, in[i].sym, "lone half 1, half 2 never opened (an ABORT not yet closed before the restart): closed (A8)",
                    in[i].pos1);
               if(ClosePosition(in[i].pos1))
                  LogClose(in[i].id, 1, in[i].sym, in[i].dir, in[i].pos1, in[i].lots, "ABORT leftover closed after the restart (A8)");
               else
                  AddPendingClose(in[i].pos1, in[i].id, 1, true);
               closed++;
               continue;
              }
            Note("ALARM", in[i].id, in[i].sym, "lone half 1 under a fallback ID (pairing by time): left to its stop; check it by hand",
                 in[i].pos1);
           }
         int n = ArraySize(m_trades);
         ArrayResize(m_trades, n + 1);
         m_trades[n] = in[i];
        }
      Note("INFO", "", "", "memory rebuilt: " + IntegerToString(ArraySize(m_trades)) + " open trades imported" +
           (closed > 0 ? StringFormat("; %d lone half 1 closed (ABORT leftover)", closed) : ""));
     }

   // Phase 6c, each new candle: our memory against the broker. A mismatch is logged and the broker wins (SPEC).
   // Returns the number of mismatches.
   int               Reconcile(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return 0;
      int found = 0;
      for(int i = 0; i < ArraySize(m_trades); i++)
        {
         if(m_trades[i].open2 && SelectPosition(m_trades[i].pos2))
           {
            double brokerSl = PositionGetDouble(POSITION_SL);
            double tick = SymbolInfoDouble(m_trades[i].sym, SYMBOL_TRADE_TICK_SIZE);
            if(MathAbs(brokerSl - m_trades[i].sl2) > tick * 0.5)
              {
               Note("RECONCILE", m_trades[i].id, m_trades[i].sym,
                    StringFormat("half 2 stop: memory %s, broker %s; broker used", DoubleToString(m_trades[i].sl2, 10),
                                 DoubleToString(brokerSl, 10)), m_trades[i].pos2);
               m_trades[i].sl2 = brokerSl;
               found++;
              }
           }
        }
      for(int p = PositionsTotal() - 1; p >= 0; p--)
        {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         bool known = false;
         for(int i = 0; i < ArraySize(m_trades); i++)
            if((m_trades[i].open1 && m_trades[i].pos1 == posId) || (m_trades[i].open2 && m_trades[i].pos2 == posId))
               known = true;
         string comment = PositionGetString(POSITION_COMMENT);
         if(!known && StringFind(comment, " h0") < 0)
           {
            Note("RECONCILE", "", PositionGetString(POSITION_SYMBOL),
                 "position with our magic not in memory: " + comment + "; a rebuild is needed", posId);
            found++;
           }
        }
      return found;
     }

#ifdef NNFX_TEST_BUILD
   // TEST BUILD ONLY (G2 verdict F3): opens a position with NO stop, to prove EnforceStops closes it.
   // Refuses outside the Strategy Tester.
   bool              NNFXTestOpenWithoutStop(const string sym, const int dir, const double lots, const string tradeId)
     {
      if(!NNFXOrdersAllowed(m_why))
         return false;
      if(MQLInfoInteger(MQL_TESTER) == 0)
        {
         Note("REFUSE", tradeId, sym, "TEST: stopless open refused outside the Strategy Tester");
         return false;
        }
      MqlTick tick;
      SymbolInfoTick(sym, tick);
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action = TRADE_ACTION_DEAL;
      req.symbol = sym;
      req.volume = lots;
      req.type = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      req.price = (dir == 1) ? tick.ask : tick.bid;
      req.deviation = NNFX_DEVIATION;
      req.type_filling = Filling(sym);
      req.magic = m_magic;
      req.comment = Comment(tradeId, 0);
      bool ok = OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE;
      ulong posId = ok ? FindPosition(sym, req.comment) : 0;
      Note("TESTSTOPLESS", tradeId, sym, ok ? "TEST: position opened without a stop on purpose" : "TEST: stopless open failed",
           posId);
      return ok;
     }

   // TEST BUILD ONLY: the next filled request's reply is treated as lost, to prove the retry never duplicates.
   void              TestLoseNextReply(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      m_lose_next_reply = true;
     }

   // TEST BUILD ONLY (G1_phase6b_1 F1): the next trade's half 2 is not sent, to prove ABORT closes half 1.
   void              TestFailNextHalf2(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_fail_next_half2 = true;
     }

   // TEST BUILD ONLY (review fixes set 2, A1): the next breakeven move is refused, to prove it is tried again.
   void              TestFailNextBe(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_fail_next_be = true;
     }

   // TEST BUILD ONLY (review fixes set 2, A8): the next close is refused, to prove it goes pending and is tried again.
   void              TestFailNextClose(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_fail_next_close = true;
     }

   // TEST BUILD ONLY: the next trade sees this stops level (points), to prove the REFUSE before any order.
   void              TestStopsLevelOverride(const long points)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_stops_override = points;
     }

   // TEST BUILD ONLY: the next trade sees this free margin, to prove the OD-5 REFUSE before any order.
   void              TestFreeMarginOverride(const double value)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_margin_override = value;
     }

   // TEST BUILD ONLY: the next trade's SL/TP are planned from `points` away from the price (> 0 towards profit,
   // < 0 an adverse fill), so the real fill differs and the SL/TP must be re-set from the fill (MODIFY, OD-14).
   void              TestFillOffset(const int points)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_fill_offset = points;
     }

   // TEST BUILD ONLY (G1_review2_1 F1): every breakeven move of this trade is refused until this object is thrown
   // away (the simulated restart makes a new one), so a restart lands between a refused move and its retry.
   void              TestHoldBe(const string tradeId)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_hold_be_id = tradeId;
     }

   // TEST BUILD ONLY (G1_review2_1 F2): the next trade's half 2 is not sent (ABORT) and every close of its half 1 is
   // refused until this object is thrown away (the simulated restart), so the rebuild meets a lone half 1.
   void              TestHoldAbort(void)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_fail_next_half2 = true;
      m_hold_abort = true;
     }
#endif
  };

#endif
