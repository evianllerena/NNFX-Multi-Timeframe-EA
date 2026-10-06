//+------------------------------------------------------------------+
//| NNFX_TemplateProbe.mq5                                           |
//| Phase 6d test tool: saves its own chart as a template so the     |
//| format of an attached EA (path, inputs) in a .tpl can be read,   |
//| then removes itself. Used to build the second chart of the demo  |
//| master-switch test. Places NO orders and has no trading code.    |
//| Writes MQL5\Profiles\Templates\<InpName>.tpl and a line in       |
//| MQL5\Files\NNFX_TemplateProbe.txt.                               |
//| Status: compiled 2026-10-06 (build 6241, 0 errors, 0 warnings);  |
//| used by tools/run_demo_master_test.ps1.                          |
//+------------------------------------------------------------------+
#property strict

input string InpName  = "nnfx_template_probe";   // template name
input int    InpDummy = 26990;                    // an input, to see how inputs are stored
input string InpText  = "probe text";             // a string input

int OnInit()
  {
   EventSetTimer(2);
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   EventKillTimer();
   bool ok = ChartSaveTemplate(0, InpName);
   int err = GetLastError();
   int h = FileOpen("NNFX_TemplateProbe.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
     {
      FileWriteString(h, StringFormat("ChartSaveTemplate(%s): %s, error %d; data path %s\r\n", InpName,
                                      ok ? "true" : "false", err, TerminalInfoString(TERMINAL_DATA_PATH)));
      FileClose(h);
     }
   ExpertRemove();
  }

void OnTick() {}
//+------------------------------------------------------------------+
