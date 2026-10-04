//+------------------------------------------------------------------+
//| Slot.mqh - load one indicator from its profile and read it       |
//|                                                                  |
//| A slot owns one indicator handle (created with IndicatorCreate)  |
//| and turns its values into long / short / none (or pass / fail).  |
//| It never decides trades.                                         |
//|                                                                  |
//| Reads only CLOSED candles: shift >= 1 (shift 0 is still forming).|
//| Candles inside the profile's warm-up read as "not ready".        |
//|                                                                  |
//| Status: NOT YET COMPILED.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_SLOT_MQH
#define NNFX_SLOT_MQH

#include "Profile.mqh"
#include "Signals.mqh"

// Enum names allowed in profiles -> the MQL5 constant (the compiler supplies the value).
bool NNFXEnumValue(const string name, long &value)
  {
   if(name == "MODE_SMA")            value = MODE_SMA;
   else if(name == "MODE_EMA")       value = MODE_EMA;
   else if(name == "MODE_SMMA")      value = MODE_SMMA;
   else if(name == "MODE_LWMA")      value = MODE_LWMA;
   else if(name == "PRICE_CLOSE")    value = PRICE_CLOSE;
   else if(name == "PRICE_OPEN")     value = PRICE_OPEN;
   else if(name == "PRICE_HIGH")     value = PRICE_HIGH;
   else if(name == "PRICE_LOW")      value = PRICE_LOW;
   else if(name == "PRICE_MEDIAN")   value = PRICE_MEDIAN;
   else if(name == "PRICE_TYPICAL")  value = PRICE_TYPICAL;
   else if(name == "PRICE_WEIGHTED") value = PRICE_WEIGHTED;
   else if(name == "VOLUME_TICK")    value = VOLUME_TICK;
   else if(name == "VOLUME_REAL")    value = VOLUME_REAL;
   else
      return false;
   return true;
  }

bool NNFXBuiltinType(const string name, ENUM_INDICATOR &type)
  {
   if(name == "MA")            type = IND_MA;
   else if(name == "RVI")      type = IND_RVI;
   else if(name == "MACD")     type = IND_MACD;
   else if(name == "VOLUMES")  type = IND_VOLUMES;
   else if(name == "MOMENTUM") type = IND_MOMENTUM;
   else
      return false;
   return true;
  }

class CNNFXSlot
  {
private:
   CNNFXProfile      m_p;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_handle;
   int               m_bufs[];
   string            m_error;

public:
                     CNNFXSlot(void) : m_tf(PERIOD_CURRENT), m_handle(INVALID_HANDLE) {}
                    ~CNNFXSlot(void) { Release(); }

   void              Release(void)
     {
      if(m_handle != INVALID_HANDLE)
         IndicatorRelease(m_handle);
      m_handle = INVALID_HANDLE;
     }

   string            Error(void) const   { return m_error; }
   string            Name(void) const    { return m_p.name; }
   string            SlotName(void) const { return m_p.slot; }
   string            Signal(void) const  { return m_p.signal; }
   int               Handle(void) const  { return m_handle; }
   int               BufferCount(void) const { return ArraySize(m_bufs); }
   int               BufferAt(const int k) const { return (k >= 0 && k < ArraySize(m_bufs)) ? m_bufs[k] : -1; }

   // Load a profile file and create the indicator. Returns false with Error() on failure.
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf, const string profile_path,
                          const bool common)
     {
      Release();
      m_symbol = symbol;
      m_tf = tf;
      m_error = "";
      if(!m_p.Load(profile_path, common))
        {
         m_error = "profile " + profile_path + ": " + m_p.error;
         return false;
        }
      m_p.Buffers(m_bufs);

      MqlParam params[];
      int n = 0;
      ENUM_INDICATOR type = IND_CUSTOM;
      if(m_p.source == "custom")
        {
         // IND_CUSTOM: the first parameter must be TYPE_STRING with the indicator's name (MQL5 docs).
         ArrayResize(params, 1);
         params[0].type = TYPE_STRING;
         params[0].string_value = m_p.indicator;
         n = 1;
        }
      else if(!NNFXBuiltinType(m_p.indicator, type))
        {
         m_error = "unknown builtin " + m_p.indicator;
         return false;
        }
      for(int k = 0; k < m_p.InputCount(); k++)
        {
         ArrayResize(params, n + 1);
         string t = m_p.input_types[k];
         string v = m_p.input_values[k];
         if(t == "int")
           {
            params[n].type = TYPE_INT;
            params[n].integer_value = StringToInteger(v);
           }
         else if(t == "double")
           {
            params[n].type = TYPE_DOUBLE;
            params[n].double_value = StringToDouble(v);
           }
         else if(t == "bool")
           {
            params[n].type = TYPE_BOOL;
            params[n].integer_value = (v == "true") ? 1 : 0;
           }
         else if(t == "string")
           {
            params[n].type = TYPE_STRING;
            params[n].string_value = v;
           }
         else
           {
            long ev = 0;
            if(!NNFXEnumValue(v, ev))
              {
               m_error = "unknown enum " + v;
               return false;
              }
            params[n].type = TYPE_INT;
            params[n].integer_value = ev;
           }
         n++;
        }
      ResetLastError();
      m_handle = IndicatorCreate(m_symbol, m_tf, type, n, params);
      if(m_handle == INVALID_HANDLE)
        {
         m_error = StringFormat("IndicatorCreate failed for %s (error %d)", m_p.name, GetLastError());
         return false;
        }
      return true;
     }

   // Has the indicator calculated, and is this candle past the warm-up?
   bool              Ready(const int shift) const
     {
      if(m_handle == INVALID_HANDLE || shift < 1)
         return false;
      int calculated = BarsCalculated(m_handle);
      int total = Bars(m_symbol, m_tf);
      if(calculated <= 0 || total <= 0)
         return false;
      int index_from_oldest = total - 1 - shift;
      return index_from_oldest >= m_p.warmup;
     }

   // One raw value of one buffer at one closed candle. EMPTY_VALUE if it can't be read.
   double            Value(const int buffer, const int shift) const
     {
      double v[];
      if(m_handle == INVALID_HANDLE || shift < 1)
         return EMPTY_VALUE;
      if(CopyBuffer(m_handle, buffer, shift, 1, v) != 1)
         return EMPTY_VALUE;
      return v[0];
     }

   // Raw values of the profile's buffers (profiles.py buffers() order).
   int               Values(const int shift, double &out[]) const
     {
      int n = ArraySize(m_bufs);
      ArrayResize(out, n);
      for(int k = 0; k < n; k++)
         out[k] = Value(m_bufs[k], shift);
      return n;
     }

   // Direction for BASELINE / C1 / C2 / EXIT. 0 when not ready or values are bad.
   int               Direction(const int shift, const double close) const
     {
      if(!Ready(shift))
         return 0;
      double v[];
      Values(shift, v);
      if(m_p.signal == "price_line")
         return NNFXPriceLineDir(close, v[0]);
      if(m_p.signal == "two_line")
         return NNFXTwoLineDir(v[0], v[1]);
      if(m_p.signal == "centre_line")
         return NNFXCentreLineDir(v[0], m_p.centre);
      return 0;
     }

   // Reference level used by the volume rule (for logs and the export check):
   // average of the previous vol_period readings, the level, or the other line.
   double            VolumeReference(const int shift) const
     {
      if(m_p.vol_rule == "level")
         return m_p.vol_level;
      if(m_p.vol_rule == "cross")
         return Value(m_p.buf_other, shift);
      double hist[];
      if(!VolumeHistory(shift, hist))
         return EMPTY_VALUE;
      double sum = 0.0;
      for(int k = 0; k < ArraySize(hist); k++)
         sum += hist[k];
      return sum / ArraySize(hist);
     }

   // Volume pass / fail. False when not ready or values are bad.
   bool              VolumePasses(const int shift) const
     {
      if(m_p.signal != "volume" || !Ready(shift))
         return false;
      double value = Value(m_p.buf_main, shift);
      if(m_p.vol_rule == "level")
         return NNFXVolumeLevel(value, m_p.vol_level);
      if(m_p.vol_rule == "cross")
         return NNFXVolumeCross(value, Value(m_p.buf_other, shift));
      double hist[];
      if(!VolumeHistory(shift, hist))
         return false;
      return NNFXVolumeAverage(value, m_p.vol_mult, hist);
     }

private:
   // The previous vol_period readings of the SAME buffer (the old harness averaged buffer 0
   // whatever the profile said; this reads buf_main).
   bool              VolumeHistory(const int shift, double &hist[]) const
     {
      int n = m_p.vol_period;
      if(n < 1)
         return false;
      ArrayResize(hist, n);
      for(int k = 0; k < n; k++)
        {
         hist[k] = Value(m_p.buf_main, shift + 1 + k);
         if(NNFXIsBad(hist[k]))
            return false;
        }
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
