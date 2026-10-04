//+------------------------------------------------------------------+
//| TradeLog.mqh - one CSV row per order event                       |
//|                                                                  |
//| Read by tools/check_trades.py (SPEC Check 1c). Written to        |
//| Common\Files\NNFX\trades\<name>.csv so the terminal, the tester  |
//| agent and the checker all find it in one place.                  |
//|                                                                  |
//| Events: OPEN (one per half, the broker-held SL/TP read back      |
//| after the fill), MODIFY (SL/TP re-set from the fill price,       |
//| OD-14), TP1, BE, TRAILON, TRAIL, TP2, SL, CLOSE, EXIT, ABORT,    |
//| REFUSE,                                                          |
//| RETRY, ALARM, TESTSTOPLESS (test build only).                    |
//|                                                                  |
//| Places NO orders.                                                |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_TRADELOG_MQH
#define NNFX_TRADELOG_MQH

#define NNFX_TRADELOG_HEADER "time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note"

struct NNFXLogRow
  {
   string            event;
   string            trade_id;
   int               half;        // 1, 2, or 0 = whole trade
   string            symbol;
   int               dir;
   long              magic;
   ulong             ticket;
   double            lots;
   double            price;
   double            sl;
   double            tp;
   double            prev_sl;
   double            entry;
   double            atr_entry;
   double            atr;
   double            close;
   double            balance;
   double            risk_pct;
   double            tick_size;
   double            tick_value;
   double            planned_risk;
   double            target_risk;
   double            cap_atr;     // runner cap in ATRs on OPEN rows; -1 = off
   string            note;
  };

void NNFXLogRowClear(NNFXLogRow &r)
  {
   r.event = "";
   r.trade_id = "";
   r.half = 0;
   r.symbol = "";
   r.dir = 0;
   r.magic = 0;
   r.ticket = 0;
   r.lots = 0;
   r.price = 0;
   r.sl = 0;
   r.tp = 0;
   r.prev_sl = 0;
   r.entry = 0;
   r.atr_entry = 0;
   r.atr = 0;
   r.close = 0;
   r.balance = 0;
   r.risk_pct = 0;
   r.tick_size = 0;
   r.tick_value = 0;
   r.planned_risk = 0;
   r.target_risk = 0;
   r.cap_atr = 0;
   r.note = "";
  }

class CNNFXTradeLog
  {
private:
   int               m_handle;
   string            m_path;

   string            N(const double v) { return StringFormat("%.10g", v); }
   string            Clean(string s)
     {
      StringReplace(s, ",", ";");
      StringReplace(s, "\r", " ");
      StringReplace(s, "\n", " ");
      return s;
     }

public:
                     CNNFXTradeLog(void) : m_handle(INVALID_HANDLE), m_path("") {}
                    ~CNNFXTradeLog(void) { Close(); }

   // name: file name inside Common\Files\NNFX\trades\ (a new file each run).
   bool              Open(const string name)
     {
      Close();
      m_path = "NNFX\\trades\\" + name;
      m_handle = FileOpen(m_path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(m_handle == INVALID_HANDLE)
        {
         Print("NNFX trade log: cannot open Common\\Files\\", m_path, " error ", GetLastError());
         return false;
        }
      FileWriteString(m_handle, NNFX_TRADELOG_HEADER + "\r\n");
      FileFlush(m_handle);
      return true;
     }

   void              Close(void)
     {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
      m_handle = INVALID_HANDLE;
     }

   string            Path(void) const { return m_path; }

   void              Write(const NNFXLogRow &r)
     {
      string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "," + r.event + "," + r.trade_id + "," +
                    IntegerToString(r.half) + "," + r.symbol + "," + IntegerToString(r.dir) + "," +
                    IntegerToString(r.magic) + "," + IntegerToString((long)r.ticket) + "," + N(r.lots) + "," +
                    N(r.price) + "," + N(r.sl) + "," + N(r.tp) + "," + N(r.prev_sl) + "," + N(r.entry) + "," +
                    N(r.atr_entry) + "," + N(r.atr) + "," + N(r.close) + "," + N(r.balance) + "," + N(r.risk_pct) + "," +
                    N(r.tick_size) + "," + N(r.tick_value) + "," + N(r.planned_risk) + "," + N(r.target_risk) + "," +
                    N(r.cap_atr) + "," + Clean(r.note);
      Print("NNFX trade log: ", line);
      if(m_handle != INVALID_HANDLE)
        {
         FileWriteString(m_handle, line + "\r\n");
         FileFlush(m_handle);
        }
     }
  };

#endif
