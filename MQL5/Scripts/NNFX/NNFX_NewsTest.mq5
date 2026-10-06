//+------------------------------------------------------------------+
//| NNFX_NewsTest.mq5                                                |
//| Phase 6e check: News.mqh gives the same answers as the Python    |
//| answer key (nnfx_ref/news.py) on the shared, hand-worked cases   |
//|   MQL5\Files\NNFX\news\news_cases.txt                            |
//| with the owner-approved list MQL5\Files\NNFX\news\news_events.txt|
//| (copy of profiles/news_events.txt, D6e-1): event matching (incl. |
//| a new Fed chair / ECB president caught by the role pattern only),|
//| N1 and N2 blocks, the X5 first-close flag.                       |
//| Places NO orders. Writes MQL5\Files\NNFX_NewsTest.txt            |
//| Status: not yet compiled.                                        |
//+------------------------------------------------------------------+
// Inputs keep their defaults when run automatically (no input dialog, so unattended runs never wait for a click).
#property strict

#include <NNFX\News.mqh>

input string InpCases = "NNFX\\news\\news_cases.txt";    // cases (MQL5\Files)
input string InpList  = "NNFX\\news\\news_events.txt";   // approved event list (MQL5\Files)

int g_report = INVALID_HANDLE;
int g_pass = 0, g_fail = 0;

void Out(const string line)
  {
   Print(line);
   if(g_report != INVALID_HANDLE)
      FileWriteString(g_report, line + "\r\n");
  }

void Check(const string kind, const string id, const bool ok, const string detail)
  {
   if(ok)
      g_pass++;
   else
     {
      g_fail++;
      Out("FAIL " + kind + " " + id + ": " + detail);
     }
  }

void OnStart()
  {
   g_report = FileOpen("NNFX_NewsTest.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   Out("NNFX_NewsTest, terminal build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)));
   string listLines[], caseLines[];
   NNFXNewsEntry entries[];
   bool okList = NNFXNewsReadLines(InpList, listLines, false);
   int ne = okList ? NNFXNewsParseList(listLines, entries) : 0;
   bool approved = false;
   for(int i = 0; i < ArraySize(listLines); i++)
      if(StringFind(listLines[i], "STATUS: APPROVED by the owner 2026-10-06 (D6e-1)") >= 0)
         approved = true;
   Check("LIST", "approved_21_entries", okList && ne == 21 && approved,
         StringFormat("read %s, %d entries, approved line %s", okList ? "ok" : "FAILED", ne, approved ? "found" : "missing"));
   if(!NNFXNewsReadLines(InpCases, caseLines, false))
     {
      Out("cannot open " + InpCases);
      g_fail++;
     }
   // first pass: events and blackouts
   NNFXNewsEvent ev[];
   string boText = "";
   for(int i = 0; i < ArraySize(caseLines); i++)
     {
      string p[];
      if(StringGetCharacter(caseLines[i], 0) == '#' || StringSplit(caseLines[i], '|', p) < 2)
         continue;
      if(p[0] == "EV")
        {
         int k = ArraySize(ev);
         ArrayResize(ev, k + 1);
         ev[k].time = StringToTime(p[1]);
         ev[k].cur = p[2];
         ev[k].id = p[3];
         ev[k].name = p[4];
         ev[k].vp = "";
        }
      else if(p[0] == "BLACKOUT")
         boText += (boText == "" ? "" : ";") + p[1];
     }
   NNFXBlackout bo[];
   NNFXParseBlackouts(boText, bo);
   // second pass: the cases
   for(int i = 0; i < ArraySize(caseLines); i++)
     {
      string p[];
      if(StringGetCharacter(caseLines[i], 0) == '#' || StringSplit(caseLines[i], '|', p) < 2)
         continue;
      if(p[0] == "MATCH")
        {
         int m = NNFXNewsMatch(entries, p[2], p[3], p[4]);
         string got = (m < 0) ? "-" : entries[m].vp;
         Check("MATCH", p[1], got == p[5], "expected " + p[5] + " got " + got);
         if(p[1] == "new_fed_chair" || p[1] == "new_ecb_president")
           {
            // the owner's request: the id is NOT in the list, the role pattern alone must catch it
            bool idListed = false;
            for(int k = 0; k < ArraySize(entries); k++)
               if(StringFind(entries[k].ids, "," + p[3] + ",") >= 0)
                  idListed = true;
            Check("PATTERN_ONLY", p[1], !idListed && m >= 0, StringFormat("id listed %s, matched %s", idListed ? "yes" : "no", m >= 0 ? "yes" : "no"));
           }
        }
      else if(p[0] == "N1")
        {
         string why;
         NNFXNewsBlocked(p[2], StringToTime(p[3]), ev, bo, why);
         if(why == "")
            why = "-";
         Check("N1", p[1], why == p[4], "expected " + p[4] + " got " + why);
        }
      else if(p[0] == "X5")
        {
         datetime prev = (p[3] == "-") ? 0 : StringToTime(p[3]);
         int got = NNFXNewsFirstClose(p[2], StringToTime(p[4]), prev, ev) ? 1 : 0;
         Check("X5", p[1], got == (int)StringToInteger(p[5]), StringFormat("expected %s got %d", p[5], got));
        }
     }
   Out(StringFormat("RESULT: %d passed, %d failed, %d total", g_pass, g_fail, g_pass + g_fail));
   if(g_report != INVALID_HANDLE)
      FileClose(g_report);
  }
//+------------------------------------------------------------------+
