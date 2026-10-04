//+------------------------------------------------------------------+
//| BarBuilder.mqh - build the rules core's input for one candle     |
//|                                                                  |
//| Owns the five slots (baseline, C1, C2, exit, volume) and the     |
//| fixed ATR for ONE pair on ONE timeframe, and fills an NNFXBar    |
//| (RulesCore.mqh) for a closed candle. Also fills an NNFXRaw with  |
//| the raw values, for the export check and the decision log.       |
//|                                                                  |
//| ATR is fixed engine machinery (rulebook M1: ATR(14)), never a    |
//| profile.                                                         |
//|                                                                  |
//| Status: Phase 5b version compiled 2026-10-04 (build 6238, 0      |
//| errors, 0 warnings; run_phase5_checks run 20261004_113357).      |
//+------------------------------------------------------------------+
#ifndef NNFX_BARBUILDER_MQH
#define NNFX_BARBUILDER_MQH

#include "RulesCore.mqh"
#include "Slot.mqh"

#define NNFX_SLOT_BASE 0
#define NNFX_SLOT_C1   1
#define NNFX_SLOT_C2   2
#define NNFX_SLOT_EX   3
#define NNFX_SLOT_VOL  4
#define NNFX_SLOTS     5

struct NNFXRaw
  {
   datetime          time;
   double            v[NNFX_SLOTS][2];   // raw values per slot (second is EMPTY_VALUE when unused)
   double            vol_ref;            // volume rule's reference (average / level / other line)
   bool              ok;                 // every value present and past warm-up
   string            why;                // what was missing when ok is false
  };

class CNNFXBarBuilder
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   CNNFXSlot         m_slots[NNFX_SLOTS];
   int               m_atr;
   int               m_atr_period;
   string            m_error;

public:
                     CNNFXBarBuilder(void) : m_tf(PERIOD_CURRENT), m_atr(INVALID_HANDLE), m_atr_period(14) {}
                    ~CNNFXBarBuilder(void) { if(m_atr != INVALID_HANDLE) IndicatorRelease(m_atr); }

   string            Error(void) const { return m_error; }
   string            PairSymbol(void) const { return m_symbol; }

   // profile_files: baseline, C1, C2, exit, volume (file names inside NNFX\profiles\).
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf, const string &profile_files[],
                          const bool common, const int atr_period = 14)
     {
      m_symbol = symbol;
      m_tf = tf;
      m_atr_period = atr_period;
      m_error = "";
      if(ArraySize(profile_files) != NNFX_SLOTS)
        {
         m_error = "need exactly 5 profiles: baseline, C1, C2, exit, volume";
         return false;
        }
      string expect[NNFX_SLOTS] = {"BASELINE", "C1", "C2", "EXIT", "VOLUME"};
      for(int k = 0; k < NNFX_SLOTS; k++)
        {
         if(!m_slots[k].Init(symbol, tf, NNFX_PROFILE_DIR + profile_files[k], common))
           {
            m_error = m_slots[k].Error();
            return false;
           }
         if(m_slots[k].SlotName() != expect[k])
           {
            m_error = StringFormat("%s is a %s profile, expected %s", profile_files[k],
                                   m_slots[k].SlotName(), expect[k]);
            return false;
           }
        }
      if(m_atr != INVALID_HANDLE)
         IndicatorRelease(m_atr);
      m_atr = iATR(symbol, tf, atr_period);
      if(m_atr == INVALID_HANDLE)
        {
         m_error = StringFormat("iATR failed (error %d)", GetLastError());
         return false;
        }
      return true;
     }

   string            SlotProfileName(const int k) const { return m_slots[k].Name(); }

   // True once every indicator (five slots + ATR) has calculated all available candles.
   bool              AllCalculated(void) const
     {
      int total = Bars(m_symbol, m_tf);
      if(total <= 0 || m_atr == INVALID_HANDLE || BarsCalculated(m_atr) < total)
         return false;
      for(int k = 0; k < NNFX_SLOTS; k++)
         if(m_slots[k].Handle() == INVALID_HANDLE || BarsCalculated(m_slots[k].Handle()) < total)
            return false;
      return true;
     }

   double            Atr(const int shift) const
     {
      double v[];
      if(m_atr == INVALID_HANDLE || shift < 1 || CopyBuffer(m_atr, 0, shift, 1, v) != 1)
         return EMPTY_VALUE;
      return v[0];
     }

   // Raw values for one closed candle.
   void              Raw(const int shift, NNFXRaw &raw) const
     {
      raw.time = iTime(m_symbol, m_tf, shift);
      raw.ok = true;
      raw.why = "";
      for(int k = 0; k < NNFX_SLOTS; k++)
        {
         double vals[];
         int n = m_slots[k].Values(shift, vals);
         raw.v[k][0] = (n > 0) ? vals[0] : EMPTY_VALUE;
         raw.v[k][1] = (n > 1) ? vals[1] : EMPTY_VALUE;
         if(!m_slots[k].Ready(shift))
           {
            raw.ok = false;
            raw.why += (raw.why == "" ? "" : ";") + m_slots[k].SlotName() + ":warmup";
            continue;
           }
         for(int j = 0; j < n; j++)
            if(NNFXIsBad(vals[j]))
              {
               raw.ok = false;
               raw.why += (raw.why == "" ? "" : ";") + m_slots[k].SlotName() + ":bad";
               break;
              }
        }
      raw.vol_ref = m_slots[NNFX_SLOT_VOL].VolumeReference(shift);
      if(NNFXIsBad(Atr(shift)))
        {
         raw.ok = false;
         raw.why += (raw.why == "" ? "" : ";") + "ATR:bad";
        }
     }

   // Fill the rules core's input for one closed candle. Returns false (with why) when
   // the candle can't be used: the core is never fed a candle with missing values.
   bool              Build(const int shift, NNFXBar &bar, NNFXRaw &raw) const
     {
      Raw(shift, raw);
      bar.t = (long)raw.time;
      bar.o = iOpen(m_symbol, m_tf, shift);
      bar.h = iHigh(m_symbol, m_tf, shift);
      bar.l = iLow(m_symbol, m_tf, shift);
      bar.c = iClose(m_symbol, m_tf, shift);
      bar.atr = Atr(shift);
      bar.base = raw.v[NNFX_SLOT_BASE][0];
      bar.c1 = m_slots[NNFX_SLOT_C1].Direction(shift, bar.c);
      bar.c2 = m_slots[NNFX_SLOT_C2].Direction(shift, bar.c);
      bar.ex = m_slots[NNFX_SLOT_EX].Direction(shift, bar.c);
      bar.vol = m_slots[NNFX_SLOT_VOL].VolumePasses(shift);
      bar.block = "";   // the guard (Phase 6) fills this
      bar.news = false; // the news module (Phase 6) fills this
      if(bar.o <= 0 || bar.h <= 0 || bar.l <= 0 || bar.c <= 0)
        {
         raw.ok = false;
         raw.why += (raw.why == "" ? "" : ";") + "price:missing";
        }
      return raw.ok;
     }
  };

#endif
//+------------------------------------------------------------------+
