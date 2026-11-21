# BelegGuard

> "Qonto stores receipts. Our agents check them for legal compliance and resist manipulation."

Multi-agent invoice checker for German invoices, built for the DevFest hackathon.
Flutter Web frontend, three Gemini agents, human approval, Excel export.

## How it works

```
Flutter Web → Upload → Extractor (Gemini) → Checker (Gemini + rules + guard) → Booker (Gemini)
                                                        ↓
                                        Approval screen (human) → Excel export
                                                        ↓
                                                    Audit log
```

| Agent | Job | Output |
|---|---|---|
| **Extractor** | Reads the invoice (PDF / image / text) | supplier, date, net, VAT, gross, VAT ID, invoice no., full raw text, suspicious text |
| **Checker** | §14 Abs. 4 UStG mandatory details, VAT rate (0/7/19 %), arithmetic, hidden prompt injection | status `ok` / `warning` / `blocked`, issues, reasoning |
| **Booker** | Suggests SKR03 account, contra account, DATEV tax code | booking + reasoning + confidence |

Each agent is a separate Gemini call (`firebase_ai`, Gemini Developer API) with its own fixed system instruction and JSON output.

## Security

- Invoice content is passed as quoted data inside `<untrusted_invoice_text>` – never as instructions. Attempts to close that tag from inside the document are removed.
- A deterministic guard (`lib/guard.dart`) scans the raw text for injection patterns and invisible Unicode. It can only make the result stricter: if it fires, the invoice is **blocked**, no matter what the LLM says.
- §14 UStG checks also run as deterministic rules next to the LLM Checker.
- Agents only read and suggest. The Excel file is written only after a human clicks **Approve**. Blocked invoices cannot be approved and are never sent to the Booker.
- Every step is logged on screen and exported to the `Audit-Log` sheet.

## Run

Offline demo (no Firebase needed – heuristic stand-in agents, same UI and flow):

```bash
flutter run -d chrome
```

With Gemini:

1. Create a Firebase project, add a Web app, and enable **Firebase AI Logic** with the Gemini Developer API.
2. Pass the web config at build time (nothing is committed):

```bash
flutter run -d chrome \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=GEMINI_MODEL=gemini-2.5-flash
```

The toggle in the top-right switches between Gemini and the offline demo agents.

## Demo (3 min)

Use the sample chips in the app (`assets/samples/`):

1. **Valid invoice** → agents reason → approve → Excel downloaded (`Buchungen` + `Audit-Log` sheets)
2. **Missing VAT ID** → flagged (§14 Abs. 4 Nr. 2 UStG)
3. **Prompt injection** → blocked, evidence quoted in the results card and the log

## Tests

```bash
flutter test
```

Runs the full pipeline (offline agents) on the three sample invoices.

## Project layout

```
lib/
  main.dart          Firebase init from --dart-define, app shell
  home_page.dart     Upload, results card, approve/reject, audit log
  agents.dart        Extractor, Checker, Booker + pipeline (Gemini)
  demo_agents.dart   Offline stand-ins with the same JSON contract
  guard.dart         Injection guard + §14 UStG rules
  excel_export.dart  Excel export after approval
  models.dart        Data models
assets/samples/      3 test invoices
docs/PLAN.md         Hackathon plan
```
