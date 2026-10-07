//+------------------------------------------------------------------+
//| DecisionLog.mqh - one row per pair per closed candle (6f, F2)    |
//|                                                                  |
//| SPEC "Log: one line per candle per pair (every decision and      |
//| why)". The format is fixed so Phase 7 can replay the same inputs |
//| through the Python core and compare its events (Check 1b).       |
//|                                                                  |
//| Common\Files\NNFX\decisions\<name>.csv, columns:                 |
//|   time      the closed candle's OPEN time (server), so it is     |
//|             always on a candle boundary                          |
//|   symbol, tf, o, h, l, c, atr, base, c1, c2, ex, vol             |
//|             the core's inputs for this candle (vol 1/0)          |
//|   ind_ok    1 = every indicator value present (0 blocks entries) |
//|   block     the reasons new entries were blocked, ";" ("-" none) |
//|   news      the X5 first-close flag (1/0)                        |
//|   events    the core's events for this candle, EV:RULE:DIR ";"  |
//|             ("-" none)                                           |
//|   action    what was sent to the broker ("-" none)               |
//|   note      free text (no commas)                                |
//| Rows are flushed at once. No trading calls.                      |
//| Status: compiles (0/0, inside NNFX_CoreStateTest); NNFXEventsText |
//| checked there; Write() not yet run (the EA will).                |
//+------------------------------------------------------------------+
#ifndef NNFX_DECISIONLOG_MQH
#define NNFX_DECISIONLOG_MQH

#include <NNFX\RulesCore.mqh>

#define NNFX_DECISION_HEADER "time,symbol,tf,o,h,l,c,atr,base,c1,c2,ex,vol,ind_ok,block,news,events,action,note"

class CNNFXDecisionLog
  {
private:
   int               m_h;
   string            m_path;

   static string     Clean(string s)
     {
      StringReplace(s, ",", ";");
      StringReplace(s, "\r", " ");
      StringReplace(s, "\n", " ");
      return s == "" ? "-" : s;
     }

public:
                     CNNFXDecisionLog(void) : m_h(INVALID_HANDLE) {}
                    ~CNNFXDecisionLog(void) { Close(); }

   // name: file name inside Common\Files\NNFX\decisions\. append: continue an existing file (a restart).
   bool              Open(const string name, const bool append)
     {
      Close();
      m_path = "NNFX\\decisions\\" + name;
      FolderCreate("NNFX\\decisions", FILE_COMMON);
      bool cont = append && FileIsExist(m_path, FILE_COMMON);
      m_h = FileOpen(m_path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | (cont ? FILE_READ : 0));
      if(m_h == INVALID_HANDLE)
         return false;
      if(cont)
         FileSeek(m_h, 0, SEEK_END);
      else
         FileWriteString(m_h, NNFX_DECISION_HEADER "\r\n");
      FileFlush(m_h);
      return true;
     }

   void              Close(void)
     {
      if(m_h != INVALID_HANDLE)
        {
         FileClose(m_h);
         m_h = INVALID_HANDLE;
        }
     }

   string            Path(void) const { return m_path; }

   // events: the core's events of this candle, already as "EV:RULE:DIR;..." (or "")
   void              Write(const string sym, const string tf, const NNFXBar &b, const bool indOk, const string events,
                           const string action, const string note)
     {
      if(m_h == INVALID_HANDLE)
         return;
      int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      FileWriteString(m_h, StringFormat("%s,%s,%s,%s,%s,%s,%s,%.10g,%s,%d,%d,%d,%d,%d,%s,%d,%s,%s,%s\r\n",
                                        TimeToString((datetime)b.t, TIME_DATE | TIME_MINUTES), sym, tf,
                                        DoubleToString(b.o, dg), DoubleToString(b.h, dg), DoubleToString(b.l, dg),
                                        DoubleToString(b.c, dg), b.atr, DoubleToString(b.base, dg + 2), b.c1, b.c2, b.ex,
                                        b.vol ? 1 : 0, indOk ? 1 : 0, Clean(b.block), b.news ? 1 : 0, Clean(events),
                                        Clean(action), Clean(note)));
      FileFlush(m_h);
     }
  };

// The core's events at index >= from, as "EV:RULE:DIR;..." (the decision log's events column)
string NNFXEventsText(const CNNFXPairCore &core, const int from)
  {
   string s = "";
   NNFXEvent e;
   for(int k = from; k < core.EventCount(); k++)
      if(core.GetEvent(k, e))
         s += (s == "" ? "" : ";") + StringFormat("%s:%s:%d", e.ev, e.rule, e.dir);
   return s;
  }

#endif
