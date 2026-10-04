//+------------------------------------------------------------------+
//| Settings.mqh - NNFX rule settings and their approved defaults    |
//| Mirrors tests/python/nnfx_ref/settings.py field for field.       |
//| Source of the defaults: docs/SPEC.md, Settings table.            |
//+------------------------------------------------------------------+
#ifndef NNFX_SETTINGS_MQH
#define NNFX_SETTINGS_MQH

struct NNFXSettings
  {
   // Money and trade management
   double            risk_pct;          // M2 (percent of balance, S-3)
   double            sl_atr;            // M3
   double            tp1_atr;           // T1
   double            max_dist_atr;      // E1-E3
   // T4 trailing stop (R-1)
   bool              trail_on;
   double            trail_start_atr;   // switch on: a close this many ENTRY ATRs beyond entry
   double            trail_dist_atr;    // distance behind the close, in CURRENT ATRs
   // T7 runner cap (R-11); 0 = off
   double            runner_cap_atr;
   // Exits (R-2)
   bool              exit_on_exit_ind;  // X2
   bool              exit_on_c1;        // X3
   bool              exit_on_baseline;  // X4
   bool              news_exit;         // X5
   // Entries
   bool              pullback_on;       // E3
   bool              one_candle;        // E4 (R-4)
   bool              btf_on;            // E5 (R-5)
   int               btf_bars;
   string            continuation;      // E6 (R-6): "off", "a" or "b"

   void              Defaults(void)
     {
      risk_pct         = 2.0;
      sl_atr           = 1.5;
      tp1_atr          = 1.0;
      max_dist_atr     = 1.0;
      trail_on         = true;
      trail_start_atr  = 2.0;
      trail_dist_atr   = 1.5;
      runner_cap_atr   = 0.0;
      exit_on_exit_ind = true;
      exit_on_c1       = true;
      exit_on_baseline = true;
      news_exit        = true;
      pullback_on      = true;
      one_candle       = true;
      btf_on           = true;
      btf_bars         = 7;
      continuation     = "a";
     }

   // Set one field from text (used by the fixture runner). Returns false for an unknown key.
   bool              Set(const string key, const string value)
     {
      bool   b = (value == "1" || value == "true");
      double d = (value == "none") ? 0.0 : StringToDouble(value);
      if(key == "risk_pct")              { risk_pct = d;            return true; }
      if(key == "sl_atr")                { sl_atr = d;              return true; }
      if(key == "tp1_atr")               { tp1_atr = d;             return true; }
      if(key == "max_dist_atr")          { max_dist_atr = d;        return true; }
      if(key == "trail_on")              { trail_on = b;            return true; }
      if(key == "trail_start_atr")       { trail_start_atr = d;     return true; }
      if(key == "trail_dist_atr")        { trail_dist_atr = d;      return true; }
      if(key == "runner_cap_atr")        { runner_cap_atr = d;      return true; }
      if(key == "exit_on_exit_ind")      { exit_on_exit_ind = b;    return true; }
      if(key == "exit_on_c1")            { exit_on_c1 = b;          return true; }
      if(key == "exit_on_baseline")      { exit_on_baseline = b;    return true; }
      if(key == "news_exit")             { news_exit = b;           return true; }
      if(key == "pullback_on")           { pullback_on = b;         return true; }
      if(key == "one_candle")            { one_candle = b;          return true; }
      if(key == "btf_on")                { btf_on = b;              return true; }
      if(key == "btf_bars")              { btf_bars = (int)d;       return true; }
      if(key == "continuation")          { continuation = value;    return true; }
      return false;
     }

   bool              Validate(string &err)
     {
      if(continuation != "off" && continuation != "a" && continuation != "b")
        { err = "continuation must be off, a or b"; return false; }
      if(risk_pct <= 0 || sl_atr <= 0 || tp1_atr <= 0 || max_dist_atr <= 0 ||
         trail_start_atr <= 0 || trail_dist_atr <= 0)
        { err = "ATR multiples and risk must be > 0"; return false; }
      if(btf_bars < 1)
        { err = "btf_bars must be >= 1"; return false; }
      if(runner_cap_atr < 0)
        { err = "runner_cap_atr must be >= 0 (0 = off)"; return false; }
      err = "";
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
