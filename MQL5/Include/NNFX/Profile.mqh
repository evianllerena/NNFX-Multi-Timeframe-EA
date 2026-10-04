//+------------------------------------------------------------------+
//| Profile.mqh - read and validate an indicator profile file        |
//| Format and rules: profiles/README.md.                            |
//| Mirrors tests/python/nnfx_ref/profiles.py (parse + validate).    |
//|                                                                  |
//| Status: compiled 2026-10-04, MT5 build 6238, 0 errors 0 warnings.|
//+------------------------------------------------------------------+
#ifndef NNFX_PROFILE_MQH
#define NNFX_PROFILE_MQH

#define NNFX_PROFILE_DIR "NNFX\\profiles\\"

//--- small text helpers -------------------------------------------
string NNFXTrim(const string s)
  {
   string t = s;
   StringReplace(t, "\r", "");
   StringReplace(t, "\n", "");
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
  }

bool NNFXIsDigit(const ushort ch) { return (ch >= '0' && ch <= '9'); }

// Whole number: optional '-', then digits only.
bool NNFXIsInt(const string s)
  {
   int n = StringLen(s);
   if(n == 0)
      return false;
   int i = 0;
   if(StringGetCharacter(s, 0) == '-')
      i = 1;
   if(i >= n)
      return false;
   for(; i < n; i++)
      if(!NNFXIsDigit(StringGetCharacter(s, i)))
         return false;
   return true;
  }

// Decimal number: optional sign, digits with at most one '.', optional exponent.
// (StringToDouble("abc") returns 0, so text is checked before converting.)
bool NNFXIsNumber(const string s)
  {
   int n = StringLen(s);
   int i = 0, digits = 0, dots = 0;
   if(n == 0)
      return false;
   ushort ch = StringGetCharacter(s, 0);
   if(ch == '-' || ch == '+')
      i = 1;
   for(; i < n; i++)
     {
      ch = StringGetCharacter(s, i);
      if(NNFXIsDigit(ch))
         digits++;
      else if(ch == '.')
        {
         dots++;
         if(dots > 1)
            return false;
        }
      else
         break;
     }
   if(digits == 0)
      return false;
   if(i == n)
      return true;
   if(ch != 'e' && ch != 'E')
      return false;
   i++;
   if(i < n && (StringGetCharacter(s, i) == '-' || StringGetCharacter(s, i) == '+'))
      i++;
   if(i >= n)
      return false;
   for(; i < n; i++)
      if(!NNFXIsDigit(StringGetCharacter(s, i)))
         return false;
   return true;
  }

bool NNFXInList(const string s, const string &list[])
  {
   for(int k = 0; k < ArraySize(list); k++)
      if(list[k] == s)
         return true;
   return false;
  }

//--- the profile ---------------------------------------------------
class CNNFXProfile
  {
public:
   string            name, slot, source, indicator, signal, vol_rule, notes;
   string            input_types[];
   string            input_values[];
   int               buf_main, buf_fast, buf_slow, buf_other, vol_period, warmup;
   double            centre, vol_level, vol_mult;
   bool              has_centre, has_vol_level, has_vol_mult;
   string            error;      // why loading failed ("" = loaded)
   string            file;

                     CNNFXProfile(void) { Reset(); }

   void              Reset(void)
     {
      name = slot = source = indicator = signal = vol_rule = notes = error = file = "";
      ArrayFree(input_types);
      ArrayFree(input_values);
      buf_main = buf_fast = buf_slow = buf_other = vol_period = warmup = -1;
      centre = vol_level = vol_mult = 0.0;
      has_centre = has_vol_level = has_vol_mult = false;
     }

   int               InputCount(void) const { return ArraySize(input_types); }

   // Output lines this profile reads, in a fixed order (profiles.py buffers()).
   int               Buffers(int &bufs[]) const
     {
      ArrayResize(bufs, 0);
      if(signal == "two_line")
        {
         ArrayResize(bufs, 2);
         bufs[0] = buf_fast;
         bufs[1] = buf_slow;
        }
      else if(signal == "volume" && vol_rule == "cross")
        {
         ArrayResize(bufs, 2);
         bufs[0] = buf_main;
         bufs[1] = buf_other;
        }
      else
        {
         ArrayResize(bufs, 1);
         bufs[0] = buf_main;
        }
      return ArraySize(bufs);
     }

   // Load from MQL5\Files (common=false) or the shared Common\Files folder (common=true).
   bool              Load(const string path, const bool common)
     {
      Reset();
      file = path;
      int flags = FILE_READ | FILE_TXT | FILE_ANSI;
      if(common)
         flags |= FILE_COMMON;
      int h = FileOpen(path, flags);
      if(h == INVALID_HANDLE)
        {
         error = StringFormat("cannot open %s (error %d)", path, GetLastError());
         return false;
        }
      string lines[];
      while(!FileIsEnding(h))
        {
         int k = ArraySize(lines);
         ArrayResize(lines, k + 1);
         lines[k] = FileReadString(h);
        }
      FileClose(h);
      return Parse(lines);
     }

   bool              Parse(const string &lines[])
     {
      string seen[];
      for(int n = 0; n < ArraySize(lines); n++)
        {
         string line = NNFXTrim(lines[n]);
         if(line == "" || StringGetCharacter(line, 0) == '#')
            continue;
         int eq = StringFind(line, "=");
         if(eq < 0)
            return Fail(StringFormat("line %d: expected key=value", n + 1));
         string key = NNFXTrim(StringSubstr(line, 0, eq));
         string value = NNFXTrim(StringSubstr(line, eq + 1));
         if(!SetKey(key, value, seen, n + 1))
            return false;
        }
      return Validate();
     }

private:
   bool              Fail(const string why) { error = why; return false; }

   bool              SetKey(const string key, const string value, string &seen[], const int line_no)
     {
      string keys[] = {"name", "slot", "source", "indicator", "input", "signal", "buf_main", "buf_fast",
                       "buf_slow", "centre", "vol_rule", "vol_level", "vol_period", "vol_mult",
                       "buf_other", "warmup", "notes"};
      if(!NNFXInList(key, keys))
         return Fail(StringFormat("line %d: unknown key %s", line_no, key));
      if(key != "input")
        {
         if(NNFXInList(key, seen))
            return Fail(StringFormat("line %d: %s given twice", line_no, key));
         int k = ArraySize(seen);
         ArrayResize(seen, k + 1);
         seen[k] = key;
        }
      if(key == "input")
         return AddInput(value, line_no);
      if(key == "buf_main" || key == "buf_fast" || key == "buf_slow" || key == "buf_other" ||
         key == "vol_period" || key == "warmup")
        {
         if(!NNFXIsInt(value))
            return Fail(StringFormat("%s must be a whole number, got %s", key, value));
         int v = (int)StringToInteger(value);
         if(key == "buf_main")        buf_main = v;
         else if(key == "buf_fast")   buf_fast = v;
         else if(key == "buf_slow")   buf_slow = v;
         else if(key == "buf_other")  buf_other = v;
         else if(key == "vol_period") vol_period = v;
         else                         warmup = v;
         return true;
        }
      if(key == "centre" || key == "vol_level" || key == "vol_mult")
        {
         if(!NNFXIsNumber(value))
            return Fail(StringFormat("%s must be a number, got %s", key, value));
         double d = StringToDouble(value);
         if(key == "centre")         { centre = d;    has_centre = true; }
         else if(key == "vol_level") { vol_level = d; has_vol_level = true; }
         else                        { vol_mult = d;  has_vol_mult = true; }
         return true;
        }
      if(key == "name")           name = value;
      else if(key == "slot")      slot = value;
      else if(key == "source")    source = value;
      else if(key == "indicator") indicator = value;
      else if(key == "signal")    signal = value;
      else if(key == "vol_rule")  vol_rule = value;
      else                        notes = value;
      return true;
     }

   bool              AddInput(const string value, const int line_no)
     {
      int colon = StringFind(value, ":");
      if(colon < 0)
         return Fail(StringFormat("line %d: input must be type:value", line_no));
      string t = StringSubstr(value, 0, colon);
      string v = StringSubstr(value, colon + 1);
      string types[] = {"int", "double", "bool", "string", "enum"};
      string enums[] = {"MODE_SMA", "MODE_EMA", "MODE_SMMA", "MODE_LWMA", "PRICE_CLOSE", "PRICE_OPEN",
                        "PRICE_HIGH", "PRICE_LOW", "PRICE_MEDIAN", "PRICE_TYPICAL", "PRICE_WEIGHTED",
                        "VOLUME_TICK", "VOLUME_REAL"};
      if(!NNFXInList(t, types))
         return Fail(StringFormat("line %d: unknown input type %s", line_no, t));
      if(t == "int" && !NNFXIsInt(v))
         return Fail(StringFormat("line %d: int input must be a whole number", line_no));
      if(t == "double" && !NNFXIsNumber(v))
         return Fail(StringFormat("line %d: double input must be a number", line_no));
      if(t == "bool" && v != "true" && v != "false")
         return Fail(StringFormat("line %d: bool input must be true or false", line_no));
      if(t == "enum" && !NNFXInList(v, enums))
         return Fail(StringFormat("line %d: unknown enum %s", line_no, v));
      int k = ArraySize(input_types);
      ArrayResize(input_types, k + 1);
      ArrayResize(input_values, k + 1);
      input_types[k] = t;
      input_values[k] = v;
      return true;
     }

   bool              NameOk(const string s)
     {
      int n = StringLen(s);
      if(n == 0)
         return false;
      for(int i = 0; i < n; i++)
        {
         ushort ch = StringGetCharacter(s, i);
         bool ok = NNFXIsDigit(ch) || (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_';
         if(!ok)
            return false;
        }
      return true;
     }

   bool              Validate(void)
     {
      string slots[] = {"BASELINE", "C1", "C2", "EXIT", "VOLUME"};
      string builtins[] = {"MA", "RVI", "MACD", "VOLUMES", "MOMENTUM"};
      string sigs[] = {"price_line", "two_line", "centre_line", "volume"};
      if(!NameOk(name))
         return Fail("name is required (letters, digits, _)");
      if(!NNFXInList(slot, slots))
         return Fail("slot must be BASELINE, C1, C2, EXIT or VOLUME");
      if(source != "builtin" && source != "custom")
         return Fail("source must be builtin or custom");
      if(indicator == "")
         return Fail("indicator is required");
      if(source == "builtin" && !NNFXInList(indicator, builtins))
         return Fail("unknown builtin indicator " + indicator);
      if(!NNFXInList(signal, sigs))
         return Fail("signal must be price_line, two_line, centre_line or volume");
      bool pair_ok = (slot == "BASELINE" && signal == "price_line") ||
                     ((slot == "C1" || slot == "C2" || slot == "EXIT") && (signal == "two_line" || signal == "centre_line")) ||
                     (slot == "VOLUME" && signal == "volume");
      if(!pair_ok)
         return Fail("slot " + slot + " cannot use signal " + signal);
      if(warmup < 0)
         return Fail("warmup is required and must be >= 0");
      if(signal == "two_line")
        {
         if(buf_fast < 0 || buf_slow < 0)
            return Fail("two_line needs buf_fast and buf_slow (>= 0)");
         if(buf_fast == buf_slow)
            return Fail("buf_fast and buf_slow must differ");
        }
      else if(buf_main < 0)
         return Fail(signal + " needs buf_main (>= 0)");
      if(signal == "centre_line" && !has_centre)
         return Fail("centre_line needs centre (never defaulted to 0)");
      if(signal == "volume")
        {
         if(vol_rule != "level" && vol_rule != "average" && vol_rule != "cross")
            return Fail("volume needs vol_rule: level, average or cross");
         if(vol_rule == "level" && !has_vol_level)
            return Fail("vol_rule=level needs vol_level");
         if(vol_rule == "average" && vol_period < 1)
            return Fail("vol_rule=average needs vol_period >= 1");
         if(vol_rule == "average" && (!has_vol_mult || vol_mult <= 0))
            return Fail("vol_rule=average needs vol_mult > 0");
         if(vol_rule == "cross" && buf_other < 0)
            return Fail("vol_rule=cross needs buf_other (>= 0)");
        }
      error = "";
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
