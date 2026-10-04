//+------------------------------------------------------------------+
//| Signals.mqh - turn raw indicator values into directions          |
//| Mirrors tests/python/nnfx_ref/signals.py function for function.  |
//| Directions: +1 long, -1 short, 0 none.                           |
//| Bad values never become signals: NaN, infinity and EMPTY_VALUE   |
//| all read as 0 (or "fail" for volume).                            |
//|                                                                  |
//| Status: NOT YET COMPILED.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_SIGNALS_MQH
#define NNFX_SIGNALS_MQH

// signals.py is_bad(): NaN, +/-infinity (MathIsValidNumber false) or EMPTY_VALUE (= DBL_MAX)
bool NNFXIsBad(const double v)
  {
   if(!MathIsValidNumber(v))
      return true;
   return (v >= EMPTY_VALUE || v <= -EMPTY_VALUE);
  }

// signals.py price_line_dir(): baseline. Long when the close is above the line.
int NNFXPriceLineDir(const double close, const double line)
  {
   if(NNFXIsBad(close) || NNFXIsBad(line))
      return 0;
   if(close > line)
      return 1;
   if(close < line)
      return -1;
   return 0;
  }

// signals.py two_line_dir(): long when fast is above slow.
int NNFXTwoLineDir(const double fast, const double slow)
  {
   if(NNFXIsBad(fast) || NNFXIsBad(slow))
      return 0;
   if(fast > slow)
      return 1;
   if(fast < slow)
      return -1;
   return 0;
  }

// signals.py centre_line_dir(). The centre comes from the profile, which refuses to
// load without one, so it is never defaulted to 0 here.
int NNFXCentreLineDir(const double value, const double centre)
  {
   if(NNFXIsBad(value))
      return 0;
   if(value > centre)
      return 1;
   if(value < centre)
      return -1;
   return 0;
  }

// signals.py volume_pass(rule="level")
bool NNFXVolumeLevel(const double value, const double level)
  {
   if(NNFXIsBad(value))
      return false;
   return value > level;
  }

// signals.py volume_pass(rule="average"): value >= mult x average of history.
// history = the previous N readings; any bad reading (or none) fails.
bool NNFXVolumeAverage(const double value, const double mult, const double &history[])
  {
   int n = ArraySize(history);
   if(NNFXIsBad(value) || n == 0)
      return false;
   double sum = 0.0;
   for(int k = 0; k < n; k++)
     {
      if(NNFXIsBad(history[k]))
         return false;
      sum += history[k];
     }
   return value >= mult * (sum / n);
  }

// signals.py volume_pass(rule="cross"): value above another line.
bool NNFXVolumeCross(const double value, const double other)
  {
   if(NNFXIsBad(value) || NNFXIsBad(other))
      return false;
   return value > other;
  }

#endif
//+------------------------------------------------------------------+
