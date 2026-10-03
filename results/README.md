# Results register

Every test run is recorded here, including failed and invalid ones (`docs/SPEC.md`,
Check 4). Nothing is deleted.

Each run gets one row in `REGISTER.md` (created with the first run) with: run ID, date,
EA version (git commit), timeframe, pairs, dates, price model, costs, settings changed
from default, validity checks V1-V14 (pass / fail / not applicable), and the result in R.

Large raw tester output goes in `results/raw/` (not stored in git); summaries stay here.
