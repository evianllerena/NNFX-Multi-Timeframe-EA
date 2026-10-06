//+------------------------------------------------------------------+
//| Orders.mqh - the ONLY module that sends, modifies or closes      |
//| orders (docs/PLAN_PHASE6.md sections 1 and 3).                   |
//|                                                                  |
//| SAFETY: every public method of CNNFXOrders calls                 |
//| NNFXOrdersAllowed() as its first statement. Orders are allowed   |
//| only in the Strategy Tester or on a DEMO account (OD-18). This   |
//| is checked by tests/python/test_order_calls.py (S2, S2b).        |
//|                                                                  |
//| Rules: both halves carry the 1.5 x ATR stop in the same request  |
//| (M3, T1, P-5); half 1 has TP1 at 1 x ATR, half 2 no target or    |
//| the runner cap (T3, T7); SL/TP re-set from the fill price and    |
//| any fill accepted (OD-14); not sent if the stop is inside the    |
//| broker's minimum distance or the margin is not free (OD-5);      |
//| up to 3 retries 1 s apart with a duplicate check first (OD-13);  |
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
bool NNFXOrdersAllowed(string &why)
  {
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   bool tester = (MQLInfoInteger(MQL_TESTER) != 0);
   if(NNFXOrdersAllowedFor(mode, tester))
     {
      why = tester ? "orders allowed: TESTER" : "orders allowed: DEMO";
      return true;
     }
   why = "orders refused: account trade mode " + IntegerToString(mode) + " is not DEMO and not in the tester";
   return false;
  }

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
   NNFXTrade         m_trades[];
   ulong             m_alarmed[];     // manual stopless positions already alarmed (one alarm each)
   double            m_sl_atr, m_tp1_atr, m_trail_start, m_trail_dist;
#ifdef NNFX_TEST_BUILD
   bool              m_lose_next_reply;
   bool              m_fail_next_half2;     // one-shot: half 2's send fails -> ABORT
   long              m_stops_override;      // one-shot: stops level in points (-1 = off) -> REFUSE
   double            m_margin_override;     // one-shot: free margin (-1 = off) -> REFUSE (OD-5)
   int               m_fill_offset;         // one-shot: plan SL/TP from price + dir x points -> MODIFY (OD-14)
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

   bool              ClosePosition(const ulong posId)
     {
      if(!SelectPosition(posId))
         return false;
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      string sym = PositionGetString(POSITION_SYMBOL);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      MqlTick tick;
      SymbolInfoTick(sym, tick);
      req.action = TRADE_ACTION_DEAL;
      req.position = (ulong)PositionGetInteger(POSITION_TICKET);
      req.symbol = sym;
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.type = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price = isBuy ? tick.bid : tick.ask;
      req.deviation = NNFX_DEVIATION;
      req.type_filling = Filling(sym);
      req.magic = m_magic;
      return OrderSend(req, res) && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);
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
                     CNNFXOrders(void) : m_magic(0), m_log(NULL), m_session_checked(false),
                     m_sl_atr(1.5), m_tp1_atr(1.0), m_trail_start(2.0), m_trail_dist(1.5)
     {
#ifdef NNFX_TEST_BUILD
      m_lose_next_reply = false;
      m_fail_next_half2 = false;
      m_stops_override = -1;
      m_margin_override = -1.0;
      m_fill_offset = 0;
#endif
     }

   bool              Init(const long magic, CNNFXTradeLog *log, const double slAtr, const double tp1Atr,
                          const double trailStart, const double trailDist)
     {
      if(!NNFXOrdersAllowed(m_why))
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
      Note("INFO", "", "", m_why);
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
         basis = price + dir * m_fill_offset * point;   // towards profit: the planned stop is closer, never wider
         Note("TEST", tradeId, sym, StringFormat("TEST: SL/TP planned from %d points away from the price (fill offset)", m_fill_offset));
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
      double planned = 2.0 * NNFXPlannedRisk(half, price, sl, tickSize, tickValue);
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
         bool closed = ClosePosition(t.pos1);
         double cprice = 0;
         long creason = -1;
         if(closed && ClosingDeal(t.pos1, cprice, creason))
           {
            NNFXLogRow c;
            NNFXLogRowClear(c);
            c.event = "CLOSE";
            c.trade_id = tradeId;
            c.half = 1;
            c.symbol = sym;
            c.dir = dir;
            c.ticket = t.pos1;
            c.lots = half;
            c.price = cprice;
            c.tick_size = tickSize;
            c.note = "closed by ABORT, deal reason " + IntegerToString(creason);
            Row(c);
           }
         Note("ABORT", tradeId, sym, closed ? "half 2 not opened; half 1 closed" : "half 2 not opened; HALF 1 CLOSE FAILED",
              t.pos1);
         if(!closed)
            Alert("NNFX: ABORT of ", tradeId, ": half 1 could not be closed");
         return false;
        }
      t.open2 = true;

      // Read back what the broker holds, then re-set SL/TP from each half's fill price (OD-14).
      ulong ids[2];
      ids[0] = t.pos1;
      ids[1] = t.pos2;
      double entries[2];
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
                 StringFormat("requested %s, slippage %s, filling %d", DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                              DoubleToString(entries[h] - price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), (int)req.type_filling));
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
               if(m_trades[i].open2)
                  MoveStop(m_trades[i].id, NNFXBreakevenPrice(m_trades[i].entry2), "BE", 0.0, 0.0, "via=" + via);
              }
           }
        }
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
      if(!ModifyPosition(m_trades[k].pos2, newSl, tp))
        {
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
      double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      for(int i = 0; i < ArraySize(m_trades); i++)
        {
         if(m_trades[i].sym != sym || !m_trades[i].tp1_done || !m_trades[i].open2)
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
      if(m_trades[k].open1)
         ok = ClosePosition(m_trades[k].pos1) && ok;
      if(m_trades[k].open2)
         ok = ClosePosition(m_trades[k].pos2) && ok;
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

   // TEST BUILD ONLY: the next trade's SL/TP are planned from `points` away from the price (towards profit), so
   // the real fill differs and the SL/TP must be re-set from the fill (MODIFY, OD-14).
   void              TestFillOffset(const int points)
     {
      if(!NNFXOrdersAllowed(m_why))
         return;
      if(MQLInfoInteger(MQL_TESTER) == 0)
         return;
      m_fill_offset = points;
     }
#endif
  };

#endif
