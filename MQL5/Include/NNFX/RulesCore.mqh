//+------------------------------------------------------------------+
//| RulesCore.mqh - per-pair NNFX rules engine                       |
//|                                                                  |
//| A function-for-function port of tests/python/nnfx_ref/core.py.   |
//| Python method  ->  MQL5 method                                   |
//|   _open_position   -> OpenPosition                               |
//|   _close_half      -> CloseHalf                                  |
//|   _finish_if_flat  -> FinishIfFlat                               |
//|   _close_all       -> CloseAll                                   |
//|   _intrabar        -> Intrabar                                   |
//|   on_bar           -> OnBar                                      |
//|   _manage_open     -> ManageOpen                                 |
//|   _decide_exit     -> DecideExit                                 |
//|   _enter           -> Enter                                      |
//|   _decide_entry    -> DecideEntry                                |
//|                                                                  |
//| Contains NO trading calls and NO indicator calls: it only turns  |
//| closed-candle inputs into decisions and simulated events, so it  |
//| can be checked against the Python answer key on identical cases. |
//| Interpretations I-1..I-15: tests/python/README.md.               |
//|                                                                  |
//| Status: compiled 2026-10-03, MT5 build 6235, 0 errors 0 warnings;|
//| NNFX_RulesTest 47/47 (docs/VERIFICATION.md).                     |
//+------------------------------------------------------------------+
#ifndef NNFX_RULESCORE_MQH
#define NNFX_RULESCORE_MQH

#include "Settings.mqh"

#define NNFX_EPS 1e-12

// One closed candle, indicator values already turned into directions by the slot layer.
struct NNFXBar
  {
   long              t;
   double            o, h, l, c;
   double            atr;     // ATR(14) of this candle, chart timeframe
   double            base;    // baseline value
   int               c1, c2, ex;  // +1 / -1 / 0
   bool              vol;     // volume / volatility filter passes
   string            block;   // reasons new entries are blocked, ';'-separated ("" = none)
   bool              news;    // first close inside a 24 h window before a major event (X5)
  };

struct NNFXEvent
  {
   int               i;
   long              t;
   string            ev;
   string            rule;
   int               dir;
   double            price;
   bool              has_price;
   string            note;
  };

struct NNFXClosedTrade
  {
   string            rule;
   int               dir;
   double            entry;
   double            r;
   int               closed_i;
  };

class CNNFXPairCore
  {
private:
   NNFXSettings      m_s;
   string            m_symbol;
   int               m_i;
   NNFXEvent         m_events[];
   int               m_n_events;
   NNFXClosedTrade   m_closed[];
   int               m_n_closed;
   // previous closed candle
   bool              m_warm;
   int               m_prev_side, m_prev_c1, m_prev_c2, m_prev_ex;
   // C1 run up to the previous candle
   int               m_c1_run_dir, m_c1_run_len;
   // position
   bool              m_has_pos;
   int               m_p_dir;
   double            m_p_entry, m_p_atr, m_p_sl, m_p_tp1, m_p_tp2;
   bool              m_p_has_tp2;
   string            m_p_rule;
   bool              m_p_h1_open, m_p_h2_open, m_p_tp1_done, m_p_trail_active;
   double            m_p_r;
   // order for the next open: 0 none, 1 enter, 2 exit
   int               m_pa_kind, m_pa_dir;
   string            m_pa_rule;
   double            m_pa_atr;
   // E3 / E4 wait
   bool              m_pe_active;
   int               m_pe_dir;
   string            m_pe_rule;
   // continuation (E6)
   int               m_trend_dir;
   bool              m_armed, m_c1_flipped;
   int               m_last_exit_dir;

   static int        Sign(const double x) { return (x > 0) ? 1 : ((x < 0) ? -1 : 0); }

   void              Emit(const NNFXBar &bar, const string ev, const string rule, const int dir,
                          const double price, const bool has_price, const string note)
     {
      ArrayResize(m_events, m_n_events + 1, 256);
      m_events[m_n_events].i = m_i;
      m_events[m_n_events].t = bar.t;
      m_events[m_n_events].ev = ev;
      m_events[m_n_events].rule = rule;
      m_events[m_n_events].dir = dir;
      m_events[m_n_events].price = price;
      m_events[m_n_events].has_price = has_price;
      m_events[m_n_events].note = note;
      m_n_events++;
     }

   // ------------------------------------------------------------ fills
   void              OpenPosition(const NNFXBar &bar)
     {
      int d = m_pa_dir;
      double atr = m_pa_atr;
      m_has_pos = true;
      m_p_dir = d;
      m_p_entry = bar.o;
      m_p_atr = atr;
      m_p_sl = m_p_entry - d * m_s.sl_atr * atr;
      m_p_tp1 = m_p_entry + d * m_s.tp1_atr * atr;
      m_p_has_tp2 = (m_s.runner_cap_atr > 0);
      m_p_tp2 = m_p_has_tp2 ? m_p_entry + d * m_s.runner_cap_atr * atr : 0.0;
      m_p_rule = m_pa_rule;
      m_p_h1_open = true;
      m_p_h2_open = true;
      m_p_tp1_done = false;
      m_p_trail_active = false;
      m_p_r = 0.0;
      Emit(bar, "OPEN", m_pa_rule, d, m_p_entry, true, "");
     }

   void              CloseHalf(const int half, const double price)
     {
      double risk = m_s.sl_atr * m_p_atr;
      m_p_r += 0.5 * (price - m_p_entry) * m_p_dir / risk;
      if(half == 1)
         m_p_h1_open = false;
      else
         m_p_h2_open = false;
     }

   void              FinishIfFlat(void)
     {
      if(m_has_pos && !m_p_h1_open && !m_p_h2_open)
        {
         ArrayResize(m_closed, m_n_closed + 1, 64);
         m_closed[m_n_closed].rule = m_p_rule;
         m_closed[m_n_closed].dir = m_p_dir;
         m_closed[m_n_closed].entry = m_p_entry;
         m_closed[m_n_closed].r = m_p_r;
         m_closed[m_n_closed].closed_i = m_i;
         m_n_closed++;
         m_last_exit_dir = m_p_dir;
         m_has_pos = false;
        }
     }

   void              CloseAll(const NNFXBar &bar, const double price, const string ev, const string rule)
     {
      int d = m_p_dir;
      if(m_p_h1_open)
         CloseHalf(1, price);
      if(m_p_h2_open)
         CloseHalf(2, price);
      Emit(bar, ev, rule, d, price, true, "");
      FinishIfFlat();
     }

   bool              Reached(const double level, const double extreme, const bool favourable, const int d)
     {
      if(favourable)
         return (extreme - level) * d >= 0;
      return (level - extreme) * d >= 0;
     }

   void              Intrabar(const NNFXBar &bar)
     {
      int d = m_p_dir;
      double fav = (d > 0) ? bar.h : bar.l;
      double adv = (d > 0) ? bar.l : bar.h;
      bool sl_hit  = Reached(m_p_sl, adv, false, d);
      bool tp1_hit = m_p_h1_open && Reached(m_p_tp1, fav, true, d);
      bool tp2_hit = m_p_h2_open && m_p_has_tp2 && Reached(m_p_tp2, fav, true, d);

      if(sl_hit)
        {
         double fill = ((m_p_sl - bar.o) * d > 0) ? bar.o : m_p_sl;
         string kind = "SL", rule = "M3";
         if(m_p_tp1_done)
           {
            if(m_p_trail_active) { kind = "TRAIL_SL"; rule = "T4"; }
            else                 { kind = "BE_SL";    rule = "T2"; }
           }
         CloseAll(bar, fill, kind, rule);
         return;
        }
      if(tp1_hit)
        {
         CloseHalf(1, m_p_tp1);
         m_p_tp1_done = true;
         Emit(bar, "TP1", "T1", d, m_p_tp1, true, "");
         m_p_sl = m_p_entry;                              // T2: breakeven at once
         Emit(bar, "MOVE_BE", "T2", d, m_p_sl, true, "");
         // breakeven stop is checked from the next candle (I-15)
         if(tp2_hit)
           {
            CloseHalf(2, m_p_tp2);
            Emit(bar, "TP2", "T7", d, m_p_tp2, true, "");
            FinishIfFlat();
           }
         return;
        }
      if(tp2_hit)
        {
         CloseHalf(2, m_p_tp2);
         Emit(bar, "TP2", "T7", d, m_p_tp2, true, "");
         FinishIfFlat();
        }
     }

   // ------------------------------------------------------------ open trade
   void              DecideExit(const NNFXBar &bar, const string rule)
     {
      m_pa_kind = 2;
      m_pa_rule = rule;
      Emit(bar, "EXIT", rule, m_p_dir, 0.0, false, "");
     }

   void              ManageOpen(const NNFXBar &bar, const int side)
     {
      int d = m_p_dir;
      double c = bar.c, atr = bar.atr;
      // T4 trailing stop (half 2, after TP1), at the close, never backwards
      if(m_s.trail_on && m_p_tp1_done && m_p_h2_open)
        {
         if(!m_p_trail_active && (c - m_p_entry) * d >= m_s.trail_start_atr * m_p_atr - NNFX_EPS)
            m_p_trail_active = true;
         if(m_p_trail_active)
           {
            double new_sl = c - d * m_s.trail_dist_atr * atr;
            if((new_sl - m_p_sl) * d > NNFX_EPS)
              {
               m_p_sl = new_sl;
               Emit(bar, "TRAIL", "T4", d, new_sl, true, "");
              }
           }
        }
      // X5: first candle inside the news window
      if(m_s.news_exit && bar.news)
        {
         double gain = (c - m_p_entry) * d;
         if(gain < 0 || gain < 1.0 * atr)
           {
            DecideExit(bar, "X5");
            return;
           }
        }
      // X2-X4; first in this fixed order is the logged reason
      if(m_s.exit_on_exit_ind && bar.ex == -d)
         DecideExit(bar, "X2");
      else if(m_s.exit_on_c1 && bar.c1 == -d)
         DecideExit(bar, "X3");
      else if(m_s.exit_on_baseline && side == -d)
         DecideExit(bar, "X4");
     }

   // ------------------------------------------------------------ flat
   bool              Enter(const NNFXBar &bar, const int d, const string rule)
     {
      if(bar.block != "")
        {
         Emit(bar, "SKIP", rule, d, 0.0, false, "blocked:" + bar.block);
         return false;
        }
      m_pa_kind = 1;
      m_pa_dir = d;
      m_pa_rule = rule;
      m_pa_atr = bar.atr;
      Emit(bar, "ENTER", rule, d, 0.0, false, "");
      if(rule != "E6")
        {
         m_trend_dir = d;
         m_armed = true;
         m_c1_flipped = false;
        }
      return true;
     }

   void              DecideEntry(const NNFXBar &bar, const int side, const int cross,
                                 const int c1_fresh, const int c2_fresh, const int ex_fresh,
                                 const bool within)
     {
      int c1 = bar.c1, c2 = bar.c2;
      bool vol = bar.vol;

      // a) a trade waiting one candle (E3 / E4)
      if(m_pe_active)
        {
         int d = m_pe_dir;
         string rule = m_pe_rule;
         m_pe_active = false;
         bool ok = (side == d && c1 == d && c2 == d && vol && within);
         if(ok)
           {
            Enter(bar, d, rule);
            return;
           }
         Emit(bar, "SKIP", rule, d, 0.0, false, "expired");
         // fall through: this candle may carry its own new signal (I-7)
        }

      // b) new standard signal: baseline cross (E2) before C1 signal (E1).
      //    Work out what it would do; only an immediate entry is acted on here
      //    (I-14: a regular entry beats a continuation).
      bool   has_outcome = false;          // a refused or waiting regular signal
      string o_event = "", o_rule = "", o_note = "", o_wait = "";
      int    o_dir = 0;
      int trig = 0;
      string rule = "";
      if(cross != 0)         { trig = cross;    rule = "E2"; }
      else if(c1_fresh != 0) { trig = c1_fresh; rule = "E1"; }
      if(trig != 0)
        {
         int d = trig;
         int age = (m_c1_run_dir == d) ? m_c1_run_len : 0;
         if(rule == "E2" && m_s.btf_on && age >= m_s.btf_bars)
           {
            has_outcome = true;
            o_event = "SKIP"; o_rule = "E5"; o_dir = d; o_wait = "";
            o_note = StringFormat("C1 signal %d candles old", age);
           }
         else
           {
            string fails = "";
            int nfails = 0;
            if(rule == "E2" && c1 != d)   { fails += (nfails > 0 ? "," : "") + "c1";       nfails++; }
            if(rule == "E1" && side != d) { fails += (nfails > 0 ? "," : "") + "baseline"; nfails++; }
            if(c2 != d)                   { fails += (nfails > 0 ? "," : "") + "c2";       nfails++; }
            if(!vol)                      { fails += (nfails > 0 ? "," : "") + "volume";   nfails++; }
            if(nfails == 0 && within)
              {
               Enter(bar, d, rule);
               return;
              }
            has_outcome = true;
            o_dir = d;
            if(nfails == 0 && !within && m_s.pullback_on)
              { o_event = "PENDING"; o_rule = "E3"; o_note = "beyond 1xATR"; o_wait = "E3"; }
            else if(nfails == 1 && within && m_s.one_candle)
              { o_event = "PENDING"; o_rule = "E4"; o_note = "waiting: " + fails; o_wait = "E4"; }
            else
              {
               string why = fails;
               if(!within)
                  why += (nfails > 0 ? "," : "") + "distance";
               o_event = "SKIP"; o_rule = rule; o_note = why; o_wait = "";
              }
           }
        }

      // c) continuation (E6): checked whenever no regular entry opened (I-14)
      if(m_s.continuation != "off" && m_armed && m_trend_dir != 0 && m_last_exit_dir == m_trend_dir)
        {
         int d = m_trend_dir;
         bool fire = false;
         if(m_s.continuation == "a")
            fire = (c2_fresh == d && !m_c1_flipped);
         else
            fire = (ex_fresh == d && c1 == d && c2 == d);
         if(fire)
           {
            if(has_outcome)
               Emit(bar, "SKIP", o_rule, o_dir, 0.0, false, "continuation taken instead");
            Enter(bar, d, "E6");
            return;
           }
        }

      // d) log the regular signal's outcome (refused, or waiting one candle)
      if(has_outcome)
        {
         if(o_wait != "")
           {
            m_pe_active = true;
            m_pe_dir = o_dir;
            m_pe_rule = o_wait;
           }
         Emit(bar, o_event, o_rule, o_dir, 0.0, false, o_note);
        }
     }

public:
                     CNNFXPairCore(void) { NNFXSettings def; def.Defaults(); Init("", def); }

   bool              Init(const string symbol, const NNFXSettings &settings)
     {
      m_s = settings;
      m_symbol = symbol;
      m_i = -1;
      ArrayFree(m_events);
      m_n_events = 0;
      ArrayFree(m_closed);
      m_n_closed = 0;
      m_warm = false;
      m_prev_side = m_prev_c1 = m_prev_c2 = m_prev_ex = 0;
      m_c1_run_dir = 0;
      m_c1_run_len = 0;
      m_has_pos = false;
      m_pa_kind = 0;
      m_pe_active = false;
      m_trend_dir = 0;
      m_armed = false;
      m_c1_flipped = false;
      m_last_exit_dir = 0;
      string err;
      return m_s.Validate(err);
     }

   // Process one closed candle. Returns the number of events it emitted.
   int               OnBar(const NNFXBar &bar)
     {
      m_i++;
      int start = m_n_events;

      // 1. actions decided at the previous close are filled at this open
      if(m_pa_kind != 0)
        {
         int kind = m_pa_kind;
         m_pa_kind = 0;
         if(kind == 1)
            OpenPosition(bar);
         else
            if(kind == 2 && m_has_pos)
               CloseAll(bar, bar.o, "CLOSE", m_pa_rule);
        }

      // 2. broker-held stops and targets inside the candle
      if(m_has_pos)
         Intrabar(bar);

      // 3. decisions at the close
      int side = Sign(bar.c - bar.base);
      int cross    = (m_warm && side != 0 && side != m_prev_side) ? side : 0;
      int c1_fresh = (m_warm && bar.c1 != 0 && bar.c1 != m_prev_c1) ? bar.c1 : 0;
      int c2_fresh = (m_warm && bar.c2 != 0 && bar.c2 != m_prev_c2) ? bar.c2 : 0;
      int ex_fresh = (m_warm && bar.ex != 0 && bar.ex != m_prev_ex) ? bar.ex : 0;
      bool within = MathAbs(bar.c - bar.base) <= m_s.max_dist_atr * bar.atr + NNFX_EPS;

      // continuation tracking (E6)
      if(m_armed && m_trend_dir != 0)
        {
         if(side == -m_trend_dir)
            m_armed = false;
         if(bar.c1 == -m_trend_dir)
            m_c1_flipped = true;
        }

      if(m_has_pos)
        {
         ManageOpen(bar, side);
         m_pe_active = false;
        }
      else
         if(m_pa_kind == 0)
            DecideEntry(bar, side, cross, c1_fresh, c2_fresh, ex_fresh, within);

      // 4. remember this candle
      if(bar.c1 != 0 && bar.c1 == m_c1_run_dir)
         m_c1_run_len++;
      else
        {
         m_c1_run_dir = bar.c1;
         m_c1_run_len = (bar.c1 != 0) ? 1 : 0;
        }
      m_prev_side = side;
      m_prev_c1 = bar.c1;
      m_prev_c2 = bar.c2;
      m_prev_ex = bar.ex;
      m_warm = true;
      return m_n_events - start;
     }

   // ------------------------------------------------------------ read-only access
   int               EventCount(void) const           { return m_n_events; }
   bool              GetEvent(const int k, NNFXEvent &e) const
     {
      if(k < 0 || k >= m_n_events)
         return false;
      e = m_events[k];
      return true;
     }
   int               ClosedCount(void) const          { return m_n_closed; }
   double            ClosedR(const int k) const       { return (k >= 0 && k < m_n_closed) ? m_closed[k].r : 0.0; }
   bool              HasPosition(void) const          { return m_has_pos; }
   int               PositionDir(void) const          { return m_has_pos ? m_p_dir : 0; }
   int               PendingKind(void) const          { return m_pa_kind; }   // 0 none, 1 enter, 2 exit at the next open
   int               PendingDir(void) const           { return m_pa_kind == 1 ? m_pa_dir : 0; }   // the entry's direction

   // ------------------------------------------------------------ memory (6f, DESIGN_6F section 5)
   // Added for the real EA's restart; the decision logic above is unchanged (still the port of core.py).
   // The events emitted so far are forgotten (the EA reads them each candle); the memory is kept.
   void              ClearEvents(void)                { ArrayFree(m_events); m_n_events = 0; }

   // Everything the core remembers between candles, as one line: "CORE|1|<33 fields>". Doubles in %.17g so the
   // restore is exact. The settings are not in it: they come from the preset.
   string            Snapshot(void) const
     {
      return StringFormat("CORE|1|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.17g|%.17g|%.17g|%.17g|%.17g|%d|%s|%d|%d|%d|%d|%.17g|%d|%d|%s|%.17g|%d|%d|%s|%d|%d|%d|%d",
                          m_i, m_warm ? 1 : 0, m_prev_side, m_prev_c1, m_prev_c2, m_prev_ex, m_c1_run_dir, m_c1_run_len,
                          m_has_pos ? 1 : 0, m_p_dir, m_p_entry, m_p_atr, m_p_sl, m_p_tp1, m_p_tp2, m_p_has_tp2 ? 1 : 0,
                          m_p_rule == "" ? "-" : m_p_rule, m_p_h1_open ? 1 : 0, m_p_h2_open ? 1 : 0, m_p_tp1_done ? 1 : 0,
                          m_p_trail_active ? 1 : 0, m_p_r, m_pa_kind, m_pa_dir, m_pa_rule == "" ? "-" : m_pa_rule, m_pa_atr,
                          m_pe_active ? 1 : 0, m_pe_dir, m_pe_rule == "" ? "-" : m_pe_rule, m_trend_dir, m_armed ? 1 : 0,
                          m_c1_flipped ? 1 : 0, m_last_exit_dir);
     }

   // Restores a Snapshot() line; false (and nothing changed) if it is not one.
   bool              Restore(const string line)
     {
      string p[];
      if(StringSplit(line, '|', p) != 35 || p[0] != "CORE" || p[1] != "1")
         return false;
      int k = 2;
      m_i = (int)StringToInteger(p[k++]);
      m_warm = (p[k++] == "1");
      m_prev_side = (int)StringToInteger(p[k++]);
      m_prev_c1 = (int)StringToInteger(p[k++]);
      m_prev_c2 = (int)StringToInteger(p[k++]);
      m_prev_ex = (int)StringToInteger(p[k++]);
      m_c1_run_dir = (int)StringToInteger(p[k++]);
      m_c1_run_len = (int)StringToInteger(p[k++]);
      m_has_pos = (p[k++] == "1");
      m_p_dir = (int)StringToInteger(p[k++]);
      m_p_entry = StringToDouble(p[k++]);
      m_p_atr = StringToDouble(p[k++]);
      m_p_sl = StringToDouble(p[k++]);
      m_p_tp1 = StringToDouble(p[k++]);
      m_p_tp2 = StringToDouble(p[k++]);
      m_p_has_tp2 = (p[k++] == "1");
      m_p_rule = (p[k] == "-") ? "" : p[k];
      k++;
      m_p_h1_open = (p[k++] == "1");
      m_p_h2_open = (p[k++] == "1");
      m_p_tp1_done = (p[k++] == "1");
      m_p_trail_active = (p[k++] == "1");
      m_p_r = StringToDouble(p[k++]);
      m_pa_kind = (int)StringToInteger(p[k++]);
      m_pa_dir = (int)StringToInteger(p[k++]);
      m_pa_rule = (p[k] == "-") ? "" : p[k];
      k++;
      m_pa_atr = StringToDouble(p[k++]);
      m_pe_active = (p[k++] == "1");
      m_pe_dir = (int)StringToInteger(p[k++]);
      m_pe_rule = (p[k] == "-") ? "" : p[k];
      k++;
      m_trend_dir = (int)StringToInteger(p[k++]);
      m_armed = (p[k++] == "1");
      m_c1_flipped = (p[k++] == "1");
      m_last_exit_dir = (int)StringToInteger(p[k++]);
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
