# MQL5

Mirrors MT5's own `MQL5` folder, so each file is copied to the same place inside the
terminal's data folder (`File > Open Data Folder` in MT5) and compiled in MetaEditor.

| Folder | Will hold | Phase |
| --- | --- | --- |
| `Experts/NNFX` | The EA itself (`NNFX_EA.mq5`), one file that runs as the 30M, 1H or 4H instance | 6 |
| `Include/NNFX` | The modules (see that folder's README) | 4-6 |
| `Scripts/NNFX` | Support scripts: environment check now; calendar export and data export later | 2+ |
| `Presets` | One settings file per timeframe (`.set`), created once the EA's settings exist | 6 |

Compiled files (`.ex5`) are not stored in the repo; they are built from source on the owner's PC.
