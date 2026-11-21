# BelegGuard – 2h Hackathon Plan

Multi-agent invoice checker. Flutter frontend, Gemini agents, human approval, Excel export.

## Pitch
"Qonto stores receipts. Our agents check them for legal compliance and resist manipulation."

## Scope

### Keep
- 1 Flutter screen: upload an invoice (image/PDF)
- 4 agents, each a separate Gemini call with its own role:
  1. **Extractor** – reads the invoice → JSON (supplier, date, net, VAT, gross, VAT ID, invoice no.)
  2. **Checker** – checks §14 UStG mandatory details, VAT rate, hidden prompt injection
  3. **Approver** – approve / reject / human review, never approves with open findings
  4. **Exporter** – suggests SKR03 account, contra account, DATEV tax code + reason
- Results card showing the agents' reasoning + Approve / Reject
- Approve → Excel download
- On-screen log of every agent step

### Drop
Auth, Firestore, Sheets API, DATEV export, dashboard, Cloud Functions

## Stack
- Flutter Web
- Gemini REST API directly from the browser (`lib/gemini_client.dart`), no backend
- `excel` package
- Gemini / Antigravity writes the code

## Security
- Invoice text passed as quoted data, never as instructions
- Checker flags hidden instructions in the invoice text
- Agents only read; writing happens only after human approval
- Every step logged in the UI

## Timeline
| Time | Task |
|---|---|
| 0:00–0:20 | Flutter project, Firebase setup, upload button |
| 0:20–0:50 | Agent chain with JSON output |
| 0:50–1:10 | Results UI, approve button, log view |
| 1:10–1:25 | Excel export + injection guard |
| 1:25–1:40 | 3 test invoices: valid, missing VAT ID, injection |
| 1:40–2:00 | README + diagram, demo test, rehearse the pitch |

**Fallback at 1:10:** drop the Excel export and show a JSON view.

## Architecture
```
Flutter Web → Upload → Extractor (Gemini) → Checker (Gemini) → Approver → Exporter (Gemini)
                                                     ↓
                                     Approval screen → Excel export
                                                     ↓
                                                 Audit log
```

## Demo (3 min)
1. Valid invoice → agents reason → approve → Excel downloaded
2. Missing VAT ID → flagged
3. Injection invoice → blocked, shown in the log
