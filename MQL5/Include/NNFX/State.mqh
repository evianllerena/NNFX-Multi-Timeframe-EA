//+------------------------------------------------------------------+
//| State.mqh - state file and restart rebuild (Phase 6c;            |
//| docs/PLAN_PHASE6.md sections 4 and 9). Port of                   |
//| tests/python/nnfx_ref/recovery.py; the rules are in its header.  |
//|                                                                  |
//|  state file  MQL5\Files\NNFX\state\<instance>.txt (OD-9 (a)):    |
//|              NNFXSTATE|1|<instance>, PROC|<last processed        |
//|              candle>, TRADE lines, CONT lines, CHECKSUM|<FNV-1a> |
//|              Written atomically: a .tmp file, then a rename.     |
//|  rebuild     broker first (positions + deal history); the state  |
//|              file only for the entry ATR, the runner cap and the |
//|              position map; trail and continuation replayed over  |
//|              closed candles. Every disagreement is noted.        |
//|                                                                  |
//| NO trading calls (tests/python/test_order_calls.py, S2).         |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_STATE_MQH
#define NNFX_STATE_MQH

#include "Orders.mqh"

#define NNFX_STATE_VERSION "1"

struct NNFXCont
  {
   string            sym;
   int               trend_dir;
   bool              armed;
   bool              c1_flipped;
   int               last_exit_dir;
   datetime          since;
  };

struct NNFXPosRec
  {
   ulong             pos;
   string            sym;
   long              magic;
   int               dir;
   double            volume, price, sl, tp;
   string            comment;
  };

struct NNFXDealRec
  {
   ulong             deal;
   datetime          time;
   ulong             pos;
   string            sym;
   long              magic;
   string            entry;    // IN or OUT
   int               dir;      // the position's direction
   double            volume, price;
   string            reason;   // EXPERT, SL, TP, CLIENT, OTHER
   string            comment;
  };

struct NNFXCandleRec
  {
   string            sym;
   datetime          time;     // open time
   double            close, atr;
   int               side, c1;
  };

//--- text helpers -------------------------------------------------
uint NNFXFnv1a32(const string text)
  {
   uchar b[];
   int n = StringToCharArray(text, b, 0, WHOLE_ARRAY, CP_ACP) - 1;   // without the terminating 0
   uint h = 0x811C9DC5;
   for(int i = 0; i < n; i++)
     {
      h ^= (uint)b[i];
      h *= 0x01000193;
     }
   return h;
  }

string NNFXNum(const double v)
  {
   return StringFormat("%.10g", v);
  }

string NNFXTime(const datetime t)
  {
   return TimeToString(t, TIME_DATE | TIME_MINUTES);
  }

string NNFXTradeLine(const NNFXTrade &t)
  {
   return StringFormat("TRADE|%s|%s|%d|%I64u|%I64u|%d|%d|%s|%s|%s|%s|%s|%s|%d|%d", t.id, t.sym, t.dir, t.pos1, t.pos2,
                       t.open1 ? 1 : 0, t.open2 ? 1 : 0, NNFXNum(t.lots), NNFXNum(t.entry1), NNFXNum(t.entry2),
                       NNFXNum(t.atr_entry), NNFXNum(t.cap_atr), NNFXNum(t.sl2), t.tp1_done ? 1 : 0, t.trail_active ? 1 : 0);
  }

string NNFXContLine(const NNFXCont &c)
  {
   return StringFormat("CONT|%s|%d|%d|%d|%d|%s", c.sym, c.trend_dir, c.armed ? 1 : 0, c.c1_flipped ? 1 : 0,
                       c.last_exit_dir, NNFXTime(c.since));
  }

void NNFXSortStrings(string &a[])
  {
   for(int i = 1; i < ArraySize(a); i++)
     {
      string k = a[i];
      int j = i - 1;
      while(j >= 0 && StringCompare(a[j], k) > 0)
        {
         a[j + 1] = a[j];
         j--;
        }
      a[j + 1] = k;
     }
  }

// Canonical lines: trades sorted by id, then continuation states sorted by symbol (same as recovery.serialize).
void NNFXSerialize(const NNFXTrade &trades[], const NNFXCont &conts[], string &lines[])
  {
   string ids[], syms[];
   ArrayResize(ids, ArraySize(trades));
   for(int i = 0; i < ArraySize(trades); i++)
      ids[i] = trades[i].id + "\t" + IntegerToString(i);
   NNFXSortStrings(ids);
   ArrayResize(syms, ArraySize(conts));
   for(int i = 0; i < ArraySize(conts); i++)
      syms[i] = conts[i].sym + "\t" + IntegerToString(i);
   NNFXSortStrings(syms);
   ArrayResize(lines, 0);
   for(int i = 0; i < ArraySize(ids); i++)
     {
      int k = (int)StringToInteger(StringSubstr(ids[i], StringFind(ids[i], "\t") + 1));
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = NNFXTradeLine(trades[k]);
     }
   for(int i = 0; i < ArraySize(syms); i++)
     {
      int k = (int)StringToInteger(StringSubstr(syms[i], StringFind(syms[i], "\t") + 1));
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = NNFXContLine(conts[k]);
     }
  }

string NNFXJoin(const string &lines[], const string sep)
  {
   string s = "";
   for(int i = 0; i < ArraySize(lines); i++)
      s += (i > 0 ? sep : "") + lines[i];
   return s;
  }

//--- state file ---------------------------------------------------
string NNFXStateText(const string instance, const NNFXTrade &trades[], const NNFXCont &conts[], const datetime processed)
  {
   string lines[];
   NNFXSerialize(trades, conts, lines);
   string text = "NNFXSTATE|" + NNFX_STATE_VERSION + "|" + instance + "\n" + "PROC|" + NNFXTime(processed) + "\n";
   for(int i = 0; i < ArraySize(lines); i++)
      text += lines[i] + "\n";
   return text + StringFormat("CHECKSUM|%08x\n", NNFXFnv1a32(text));
  }

bool NNFXParseTradeFields(const string &p[], const int at, NNFXTrade &t)
  {
   if(ArraySize(p) < at + 15)
      return false;
   t.id = p[at];
   t.sym = p[at + 1];
   t.dir = (int)StringToInteger(p[at + 2]);
   t.pos1 = (ulong)StringToInteger(p[at + 3]);
   t.pos2 = (ulong)StringToInteger(p[at + 4]);
   t.open1 = (p[at + 5] == "1");
   t.open2 = (p[at + 6] == "1");
   t.lots = StringToDouble(p[at + 7]);
   t.entry1 = StringToDouble(p[at + 8]);
   t.entry2 = StringToDouble(p[at + 9]);
   t.atr_entry = StringToDouble(p[at + 10]);
   t.cap_atr = StringToDouble(p[at + 11]);
   t.sl2 = StringToDouble(p[at + 12]);
   t.tp1_done = (p[at + 13] == "1");
   t.trail_active = (p[at + 14] == "1");
   return true;
  }

// lines: the file's lines without line ends. Returns "present" or "corrupt" (why says why).
string NNFXStateParse(const string &lines[], NNFXTrade &trades[], NNFXCont &conts[], datetime &processed, string &why)
  {
   ArrayResize(trades, 0);
   ArrayResize(conts, 0);
   processed = 0;
   why = "";
   int n = ArraySize(lines);
   while(n > 0 && lines[n - 1] == "")
      n--;
   if(n == 0 || StringFind(lines[n - 1], "CHECKSUM|") != 0)
     {
      why = "no checksum line";
      return "corrupt";
     }
   string body = "";
   for(int i = 0; i < n - 1; i++)
      body += lines[i] + "\n";
   string want = StringSubstr(lines[n - 1], 9);
   StringTrimRight(want);
   StringToLower(want);
   if(StringFormat("%08x", NNFXFnv1a32(body)) != want)
     {
      why = "checksum mismatch";
      return "corrupt";
     }
   string head[];
   if(StringSplit(lines[0], '|', head) < 2 || head[0] != "NNFXSTATE" || head[1] != NNFX_STATE_VERSION)
     {
      why = "wrong header or version";
      return "corrupt";
     }
   for(int i = 1; i < n - 1; i++)
     {
      string p[];
      int k = StringSplit(lines[i], '|', p);
      if(k == 2 && p[0] == "PROC")
         processed = StringToTime(p[1]);
      else if(k == 16 && p[0] == "TRADE")
        {
         int m = ArraySize(trades);
         ArrayResize(trades, m + 1);
         NNFXParseTradeFields(p, 1, trades[m]);
        }
      else if(k == 7 && p[0] == "CONT")
        {
         int m = ArraySize(conts);
         ArrayResize(conts, m + 1);
         conts[m].sym = p[1];
         conts[m].trend_dir = (int)StringToInteger(p[2]);
         conts[m].armed = (p[3] == "1");
         conts[m].c1_flipped = (p[4] == "1");
         conts[m].last_exit_dir = (int)StringToInteger(p[5]);
         conts[m].since = StringToTime(p[6]);
        }
      else
        {
         ArrayResize(trades, 0);
         ArrayResize(conts, 0);
         why = "unreadable line " + lines[i];
         return "corrupt";
        }
     }
   return "present";
  }

string NNFXStatePath(const string instance)
  {
   return "NNFX\\state\\" + instance + ".txt";
  }

// Atomic save: write <path>.tmp, then rename it over <path> (OD-9 (a): MQL5\Files, per terminal / per tester agent).
bool NNFXStateSave(const string instance, const string text)
  {
   string path = NNFXStatePath(instance);
   string tmp = path + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_BIN);
   if(h == INVALID_HANDLE)
      return false;
   uchar b[];
   int n = StringToCharArray(text, b, 0, WHOLE_ARRAY, CP_ACP) - 1;
   bool ok = (FileWriteArray(h, b, 0, n) == (uint)n);
   FileClose(h);
   if(!ok)
      return false;
   return FileMove(tmp, 0, path, FILE_REWRITE);
  }

// Reads the state file's lines. False if there is no file (status "absent").
bool NNFXStateReadLines(const string instance, string &lines[])
  {
   ArrayResize(lines, 0);
   string path = NNFXStatePath(instance);
   if(!FileIsExist(path))
      return false;
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(h))
     {
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = FileReadString(h);
      StringReplace(lines[n], "\r", "");
     }
   FileClose(h);
   return true;
  }

//--- continuation tracker (the same step as core.py and the rebuild) ---
void NNFXContStart(NNFXCont &c, const string sym, const int dir, const datetime entryTime, const int period)
  {
   c.sym = sym;
   c.trend_dir = dir;
   c.armed = true;
   c.c1_flipped = false;
   c.since = entryTime - entryTime % period;
  }

void NNFXContStep(NNFXCont &c, const int side, const int c1)
  {
   if(!c.armed || c.trend_dir == 0)
      return;
   if(side == -c.trend_dir)
      c.armed = false;
   if(c1 == -c.trend_dir)
      c.c1_flipped = true;
  }

//--- the pure rebuild ---------------------------------------------
int NNFXCommentKey(const string comment, string &id, int &half)
  {
   string p[];
   if(StringSplit(comment, ' ', p) != 3 || p[0] != "NNFX" || StringLen(p[2]) != 2 ||
      (p[2] != "h1" && p[2] != "h2") || p[1] == "")
      return 0;
   id = p[1];
   half = (p[2] == "h1") ? 1 : 2;
   return 1;
  }

int NNFXFindPos(const NNFXPosRec &pos[], const ulong id)
  {
   for(int i = 0; i < ArraySize(pos); i++)
      if(pos[i].pos == id)
         return i;
   return -1;
  }

void NNFXAddNote(string &notes, const string text)
  {
   notes += (notes == "" ? "" : "\n") + text;
  }

// Rebuilt open trades and continuation states (see recovery.rebuild). upto = open time of the last processed candle.
void NNFXRebuildPure(const NNFXPosRec &posAll[], const NNFXDealRec &dealsIn[], const string stateStatus,
                     const NNFXTrade &stateTrades[], const NNFXCandleRec &candlesIn[], const int period,
                     const long magic, const datetime upto, const bool ignoreComments,
                     NNFXTrade &out[], NNFXCont &conts[], string &notes)
  {
   ArrayResize(out, 0);
   ArrayResize(conts, 0);
   notes = "";
   NNFXAddNote(notes, "state file: " + stateStatus);
   bool stOk = (stateStatus == "present");

   // our deals, in (time, deal) order
   NNFXDealRec d[];
   int nd = 0;
   for(int i = 0; i < ArraySize(dealsIn); i++)
      if(dealsIn[i].magic == magic)
        {
         ArrayResize(d, nd + 1);
         d[nd++] = dealsIn[i];
        }
   for(int i = 1; i < nd; i++)
     {
      NNFXDealRec k = d[i];
      int j = i - 1;
      while(j >= 0 && (d[j].time > k.time || (d[j].time == k.time && d[j].deal > k.deal)))
        {
         d[j + 1] = d[j];
         j--;
        }
      d[j + 1] = k;
     }

   // keys for IN deals: comment, then state file, then fallback
   string keyId[];
   int keyHalf[];
   bool resolved[];
   ArrayResize(keyId, nd);
   ArrayResize(keyHalf, nd);
   ArrayResize(resolved, nd);
   for(int i = 0; i < nd; i++)
     {
      resolved[i] = false;
      keyId[i] = "";
      keyHalf[i] = 0;
      if(d[i].entry != "IN")
         continue;
      string sid = "";
      int shalf = 0;
      if(stOk)
         for(int s = 0; s < ArraySize(stateTrades); s++)
           {
            if(stateTrades[s].pos1 == d[i].pos)
              {
               sid = stateTrades[s].id;
               shalf = 1;
              }
            else if(stateTrades[s].pos2 != 0 && stateTrades[s].pos2 == d[i].pos)
              {
               sid = stateTrades[s].id;
               shalf = 2;
              }
           }
      string cid;
      int chalf;
      if(!ignoreComments && NNFXCommentKey(d[i].comment, cid, chalf) == 1)
        {
         keyId[i] = cid;
         keyHalf[i] = chalf;
         resolved[i] = true;
         if(sid != "" && (sid != cid || shalf != chalf))
            NNFXAddNote(notes, StringFormat("disagree position %I64u: comment %s h%d, state %s h%d; comment used",
                                            d[i].pos, cid, chalf, sid, shalf));
        }
      else if(sid != "")
        {
         keyId[i] = sid;
         keyHalf[i] = shalf;
         resolved[i] = true;
        }
     }
   // fallback groups: same symbol, second, direction and volume, in deal order
   for(int i = 0; i < nd; i++)
     {
      if(d[i].entry != "IN" || resolved[i])
         continue;
      string list = "";
      int count = 0;
      string firstId = "";
      for(int j = i; j < nd; j++)
        {
         if(d[j].entry != "IN" || resolved[j] || d[j].sym != d[i].sym || d[j].time != d[i].time || d[j].dir != d[i].dir ||
            MathAbs(d[j].volume - d[i].volume) > 1e-8)
            continue;
         if(count % 2 == 0)
           {
            firstId = "R" + IntegerToString((long)d[j].pos);
            keyHalf[j] = 1;
           }
         else
            keyHalf[j] = 2;
         keyId[j] = firstId;
         resolved[j] = true;
         list += (count > 0 ? "," : "") + IntegerToString((long)d[j].pos);
         count++;
        }
      NNFXAddNote(notes, "fallback pairing: " + list);
     }

   // our open positions
   NNFXPosRec pos[];
   int np = 0;
   for(int i = 0; i < ArraySize(posAll); i++)
      if(posAll[i].magic == magic)
        {
         ArrayResize(pos, np + 1);
         pos[np++] = posAll[i];
        }

   // trade ids in order of first appearance
   string ids[];
   for(int i = 0; i < nd; i++)
      if(d[i].entry == "IN")
        {
         bool seen = false;
         for(int k = 0; k < ArraySize(ids); k++)
            if(ids[k] == keyId[i])
               seen = true;
         if(!seen)
           {
            int n = ArraySize(ids);
            ArrayResize(ids, n + 1);
            ids[n] = keyId[i];
           }
        }

   // candles up to upto, by time
   NNFXCandleRec c[];
   int nc = 0;
   for(int i = 0; i < ArraySize(candlesIn); i++)
      if(candlesIn[i].time <= upto)
        {
         ArrayResize(c, nc + 1);
         c[nc++] = candlesIn[i];
        }
   for(int i = 1; i < nc; i++)
     {
      NNFXCandleRec k = c[i];
      int j = i - 1;
      while(j >= 0 && c[j].time > k.time)
        {
         c[j + 1] = c[j];
         j--;
        }
      c[j + 1] = k;
     }

   // per trade: (entry time, sym, dir, closed, last out) for the continuation step
   datetime tEntry[];
   string tSym[];
   int tDir[];
   bool tClosed[];
   datetime tLastOut[];
   int nt = ArraySize(ids);
   ArrayResize(tEntry, nt);
   ArrayResize(tSym, nt);
   ArrayResize(tDir, nt);
   ArrayResize(tClosed, nt);
   ArrayResize(tLastOut, nt);

   for(int k = 0; k < nt; k++)
     {
      int i1 = -1, i2 = -1;
      for(int i = 0; i < nd; i++)
         if(d[i].entry == "IN" && keyId[i] == ids[k])
           {
            if(keyHalf[i] == 1)
               i1 = i;
            else
               i2 = i;
           }
      int f = (i1 >= 0) ? i1 : i2;
      NNFXTrade t;
      t.id = ids[k];
      t.sym = d[f].sym;
      t.dir = d[f].dir;
      t.pos1 = 0;
      t.pos2 = 0;
      t.open1 = false;
      t.open2 = false;
      t.lots = 0;
      t.entry1 = 0;
      t.entry2 = 0;
      t.sl2 = 0;
      t.atr_entry = 0;
      t.cap_atr = -1;
      t.tp1_done = false;
      t.trail_active = false;
      if(i1 >= 0)
        {
         t.pos1 = d[i1].pos;
         t.entry1 = d[i1].price;
         t.lots = d[i1].volume;
         t.open1 = (NNFXFindPos(pos, t.pos1) >= 0);
        }
      if(i2 >= 0)
        {
         t.pos2 = d[i2].pos;
         t.entry2 = d[i2].price;
         if(t.lots == 0)
            t.lots = d[i2].volume;
         t.open2 = (NNFXFindPos(pos, t.pos2) >= 0);
        }
      // the last OUT deal of each half
      int o1 = -1, o2 = -1;
      for(int i = 0; i < nd; i++)
         if(d[i].entry == "OUT")
           {
            if(i1 >= 0 && d[i].pos == t.pos1)
               o1 = i;
            if(i2 >= 0 && d[i].pos == t.pos2)
               o2 = i;
           }
      t.tp1_done = (o1 >= 0 && d[o1].reason == "TP");
      bool closed = !t.open1 && !t.open2;
      datetime lastOut = 0;
      if(o1 >= 0)
         lastOut = MathMax(lastOut, d[o1].time);
      if(o2 >= 0)
         lastOut = MathMax(lastOut, d[o2].time);
      tEntry[k] = d[f].time;
      tSym[k] = t.sym;
      tDir[k] = t.dir;
      tClosed[k] = closed;
      tLastOut[k] = lastOut;
      if(closed)
         continue;
      if(t.open2)
         t.sl2 = pos[NNFXFindPos(pos, t.pos2)].sl;
      int st = -1;
      if(stOk)
         for(int s = 0; s < ArraySize(stateTrades); s++)
            if(stateTrades[s].id == t.id)
               st = s;
      if(st >= 0)
        {
         t.atr_entry = stateTrades[st].atr_entry;
         t.cap_atr = stateTrades[st].cap_atr;
         if(stateTrades[st].open1 != t.open1)
            NNFXAddNote(notes, StringFormat("disagree %s open1: state %d, broker %d; broker used", t.id, (int)stateTrades[st].open1, (int)t.open1));
         if(stateTrades[st].open2 != t.open2)
            NNFXAddNote(notes, StringFormat("disagree %s open2: state %d, broker %d; broker used", t.id, (int)stateTrades[st].open2, (int)t.open2));
         if(stateTrades[st].sl2 != t.sl2)
            NNFXAddNote(notes, StringFormat("disagree %s sl2: state %s, broker %s; broker used", t.id,
                                            NNFXNum(stateTrades[st].sl2), NNFXNum(t.sl2)));
         if(stateTrades[st].tp1_done != t.tp1_done)
            NNFXAddNote(notes, StringFormat("disagree %s tp1_done: state %d, broker %d; broker used", t.id,
                                            (int)stateTrades[st].tp1_done, (int)t.tp1_done));
        }
      else
        {
         int dec = -1;
         for(int i = 0; i < nc; i++)
            if(c[i].sym == t.sym && c[i].time + period <= tEntry[k])
               dec = i;
         if(dec >= 0)
            t.atr_entry = c[dec].atr;
         else
            NNFXAddNote(notes, t.id + ": no decision candle for the entry ATR");
         int p2 = t.open2 ? NNFXFindPos(pos, t.pos2) : -1;
         if(p2 >= 0 && pos[p2].tp != 0.0 && t.atr_entry > 0)
            t.cap_atr = NormalizeDouble(MathAbs(pos[p2].tp - t.entry2) / t.atr_entry, 2);
         else
            t.cap_atr = -1;
        }
      if(t.tp1_done && t.open2 && t.atr_entry > 0)
        {
         datetime start = d[o1].time - d[o1].time % period;
         for(int i = 0; i < nc; i++)
            if(c[i].sym == t.sym && c[i].time >= start && (c[i].close - t.entry2) * t.dir >= 2.0 * t.atr_entry - 1e-12)
              {
               t.trail_active = true;
               break;
              }
        }
      int n = ArraySize(out);
      ArrayResize(out, n + 1);
      out[n] = t;
     }

   // continuation per symbol, from the latest trade
   string syms[];
   for(int k = 0; k < nt; k++)
     {
      bool seen = false;
      for(int s = 0; s < ArraySize(syms); s++)
         if(syms[s] == tSym[k])
            seen = true;
      if(!seen)
        {
         int n = ArraySize(syms);
         ArrayResize(syms, n + 1);
         syms[n] = tSym[k];
        }
     }
   NNFXSortStrings(syms);
   for(int s = 0; s < ArraySize(syms); s++)
     {
      int last = -1, lastDone = -1;
      for(int k = 0; k < nt; k++)
        {
         if(tSym[k] != syms[s])
            continue;
         if(last < 0 || tEntry[k] > tEntry[last] || (tEntry[k] == tEntry[last] && tDir[k] > tDir[last]))
            last = k;
         if(tClosed[k] && (lastDone < 0 || tLastOut[k] > tLastOut[lastDone] ||
                           (tLastOut[k] == tLastOut[lastDone] && tEntry[k] > tEntry[lastDone])))
            lastDone = k;
        }
      NNFXCont cc;
      cc.last_exit_dir = 0;
      NNFXContStart(cc, syms[s], tDir[last], tEntry[last], period);
      for(int i = 0; i < nc; i++)
         if(c[i].sym == syms[s] && c[i].time >= cc.since)
            NNFXContStep(cc, c[i].side, c[i].c1);
      if(lastDone >= 0)
         cc.last_exit_dir = tDir[lastDone];
      int n = ArraySize(conts);
      ArrayResize(conts, n + 1);
      conts[n] = cc;
     }
  }

//--- reading the broker -------------------------------------------
string NNFXReasonName(const long r)
  {
   if(r == DEAL_REASON_SL)
      return "SL";
   if(r == DEAL_REASON_TP)
      return "TP";
   if(r == DEAL_REASON_EXPERT)
      return "EXPERT";
   if(r == DEAL_REASON_CLIENT)
      return "CLIENT";
   return "OTHER";
  }

// Every open position, and every deal of this magic since `from` (positions of all magics: the rebuild
// filters by magic, so another instance's or a manual position is never rebuilt).
bool NNFXGatherBroker(const long magic, const datetime from, NNFXPosRec &pos[], NNFXDealRec &deals[])
  {
   ArrayResize(pos, 0);
   ArrayResize(deals, 0);
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      int n = ArraySize(pos);
      ArrayResize(pos, n + 1);
      pos[n].pos = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      pos[n].sym = PositionGetString(POSITION_SYMBOL);
      pos[n].magic = PositionGetInteger(POSITION_MAGIC);
      pos[n].dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      pos[n].volume = PositionGetDouble(POSITION_VOLUME);
      pos[n].price = PositionGetDouble(POSITION_PRICE_OPEN);
      pos[n].sl = PositionGetDouble(POSITION_SL);
      pos[n].tp = PositionGetDouble(POSITION_TP);
      pos[n].comment = PositionGetString(POSITION_COMMENT);
     }
   if(!HistorySelect(from, TimeCurrent() + 86400))
      return false;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0 || HistoryDealGetInteger(t, DEAL_MAGIC) != magic)
         continue;
      long entry = HistoryDealGetInteger(t, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_OUT)
         continue;
      long type = HistoryDealGetInteger(t, DEAL_TYPE);
      int dealDir = (type == DEAL_TYPE_BUY) ? 1 : -1;
      int n = ArraySize(deals);
      ArrayResize(deals, n + 1);
      deals[n].deal = t;
      deals[n].time = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
      deals[n].pos = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
      deals[n].sym = HistoryDealGetString(t, DEAL_SYMBOL);
      deals[n].magic = magic;
      deals[n].entry = (entry == DEAL_ENTRY_IN) ? "IN" : "OUT";
      deals[n].dir = (entry == DEAL_ENTRY_IN) ? dealDir : -dealDir;   // the position's direction
      deals[n].volume = HistoryDealGetDouble(t, DEAL_VOLUME);
      deals[n].price = HistoryDealGetDouble(t, DEAL_PRICE);
      deals[n].reason = NNFXReasonName(HistoryDealGetInteger(t, DEAL_REASON));
      deals[n].comment = HistoryDealGetString(t, DEAL_COMMENT);
     }
   return true;
  }

#endif
