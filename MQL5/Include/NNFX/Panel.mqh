//+------------------------------------------------------------------+
//| Panel.mqh - chart buttons for one instance (Phase 6d)            |
//|                                                                  |
//| SPEC controls: "Instance switch | One timeframe | Setting +      |
//| chart button"; "Close-all | One instance's trades | Chart button |
//| with a confirm step; never automatic"; S-6 / D6d-3: the drawdown |
//| pause is reset by hand only (a button with a confirm step).      |
//|                                                                  |
//| The panel only TELLS the EA what the owner asked for; it never   |
//| trades. The EA does the action and logs it:                      |
//|   NNFX_PANEL_INSTANCE  toggle this instance's switch (stored in  |
//|                        the global variable from NNFXInstanceGv)  |
//|   NNFX_PANEL_CLOSEALL  confirmed close-all: this instance only   |
//|   NNFX_PANEL_DDRESET   confirmed: sets NNFX_DD_RESET = 1; the    |
//|                        guard resets and logs it at the next      |
//|                        candle (NNFXDrawdownResetRequested)       |
//| Confirm step: MessageBox (Yes/No). A test EA may also drive the  |
//| same three actions with custom chart events, auto-confirmed;     |
//| that path exists only when NNFX_TEST_BUILD is defined.           |
//| No trading calls.                                                |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
#ifndef NNFX_PANEL_MQH
#define NNFX_PANEL_MQH

#include <NNFX\Guard.mqh>

#define NNFX_PANEL_NONE      0
#define NNFX_PANEL_INSTANCE  1
#define NNFX_PANEL_CLOSEALL  2
#define NNFX_PANEL_DDRESET   3
#define NNFX_PANEL_TEST_EVENT_BASE 7100   // custom chart events 7101..7103 (test build only)

// This instance's switch: a global variable per symbol and magic. Missing = the instance setting (an input).
string NNFXInstanceGv(const string sym, const long magic) { return StringFormat("NNFX_INST_%s_%I64d", sym, magic); }

bool NNFXInstanceOn(const string sym, const long magic, const bool setting)
  {
   string gv = NNFXInstanceGv(sym, magic);
   return GlobalVariableCheck(gv) ? GlobalVariableGet(gv) != 0.0 : setting;
  }

class CNNFXPanel
  {
private:
   string            m_prefix;
   long              m_chart;
   string            m_sym;
   long              m_magic;
   bool              m_setting;

   void              Button(const string name, const string text, const int y, const color bg)
     {
      string id = m_prefix + name;
      if(ObjectFind(m_chart, id) < 0)
         ObjectCreate(m_chart, id, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(m_chart, id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart, id, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(m_chart, id, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart, id, OBJPROP_XSIZE, 170);
      ObjectSetInteger(m_chart, id, OBJPROP_YSIZE, 24);
      ObjectSetInteger(m_chart, id, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(m_chart, id, OBJPROP_SELECTABLE, false);
      ObjectSetString(m_chart, id, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chart, id, OBJPROP_STATE, false);
     }

   bool              Confirm(const string question, const bool autoYes)
     {
      if(autoYes)
         return true;
      return MessageBox(question, "NNFX " + m_sym, MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2) == IDYES;
     }

   int               Act(const int action, const bool autoYes)
     {
      if(action == NNFX_PANEL_INSTANCE)
        {
         bool on = !NNFXInstanceOn(m_sym, m_magic, m_setting);
         GlobalVariableSet(NNFXInstanceGv(m_sym, m_magic), on ? 1.0 : 0.0);
         Draw();
         return action;
        }
      if(action == NNFX_PANEL_CLOSEALL)
         return Confirm(StringFormat("Close ALL trades of this instance (%s, magic %I64d) now?", m_sym, m_magic), autoYes)
                ? action : NNFX_PANEL_NONE;
      if(action == NNFX_PANEL_DDRESET)
        {
         if(!Confirm("Reset the 10% drawdown pause (all instances)? New entries resume.", autoYes))
            return NNFX_PANEL_NONE;
         GlobalVariableSet(NNFX_GV_DD_RESET, 1.0);
         return action;
        }
      return NNFX_PANEL_NONE;
     }

public:
   void              Init(const long chart, const string sym, const long magic, const bool instanceSetting)
     {
      m_chart = chart;
      m_sym = sym;
      m_magic = magic;
      m_setting = instanceSetting;
      m_prefix = StringFormat("NNFX_PANEL_%I64d_", magic);
      Draw();
     }

   void              Draw(void)
     {
      bool on = NNFXInstanceOn(m_sym, m_magic, m_setting);
      Button("instance", on ? "Instance: ON (click = off)" : "Instance: OFF (click = on)", 30, on ? clrPaleGreen : clrLightSalmon);
      Button("closeall", "Close all (asks first)", 58, clrLightGray);
      Button("ddreset", "Reset drawdown pause", 86, clrLightGray);
      ChartRedraw(m_chart);
     }

   void              Remove(void) { ObjectsDeleteAll(m_chart, m_prefix); }

   // Returns the action the owner asked for (NNFX_PANEL_*), after the confirm step where one applies
   int               OnEvent(const int id, const long lparam, const double dparam, const string sparam)
     {
      if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, m_prefix) == 0)
        {
         ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);
         string name = StringSubstr(sparam, StringLen(m_prefix));
         if(name == "instance")
            return Act(NNFX_PANEL_INSTANCE, false);
         if(name == "closeall")
            return Act(NNFX_PANEL_CLOSEALL, false);
         if(name == "ddreset")
            return Act(NNFX_PANEL_DDRESET, false);
        }
#ifdef NNFX_TEST_BUILD
      // TEST BUILD ONLY: the same actions from custom chart events, auto-confirmed (no dialog can be clicked by a test)
      int a = id - CHARTEVENT_CUSTOM - NNFX_PANEL_TEST_EVENT_BASE;
      if(id >= CHARTEVENT_CUSTOM && a >= NNFX_PANEL_INSTANCE && a <= NNFX_PANEL_DDRESET && lparam == m_magic)
         return Act(a, true);
#endif
      return NNFX_PANEL_NONE;
     }
  };

#endif
