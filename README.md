# BelegGuard

> "Qonto stores receipts. Our agents check them for legal compliance and resist manipulation."

Multi-agent invoice checker for German invoices, built for the DevFest hackathon.
Flutter Web + Google Gemini API.

## Flow

```
Invoice (PDF / image)
   │
   ▼
Extractor agent ── reads the document → structured JSON
   │
   ▼
Checker agent ──── §14 UStG mandatory details, VAT rate, sums, hidden prompt injection
   │                 + deterministic rules and injection guard (can only make it stricter)
   ▼
Approver agent ─── recommends approve / reject / human review
   │                 → you decide (default) or the agent decides clear cases (setting)
   ▼
Exporter agent ─── SKR03 account, contra account, DATEV tax code → Excel download
   │
   ▼
Audit log (on screen + "Audit-Log" sheet in the Excel file)
```

Each agent is a separate call to the Gemini API (`generativelanguage.googleapis.com`) with its
own fixed system instruction and JSON output. Default model: `gemini-2.5-flash`.

## Security

- The invoice is passed as quoted, untrusted data – never as instructions.
- Only the Extractor sees the original file. Approver and Exporter only get structured fields.
- A deterministic guard (`lib/guard.dart`) scans the text for injection patterns and invisible
  Unicode. If it fires, the invoice is **blocked** – no agent can approve it.
- The Approver agent can never approve an invoice that has open findings; those go to a human.
- Nothing is written until the invoice is approved.

## Run

1. Get a Gemini API key at https://aistudio.google.com/apikey
2. Start the app and paste the key when asked (stored only in your browser):

```bash
flutter run -d chrome
```

Or bake it in for a demo machine (never commit it):

```bash
flutter run -d chrome --dart-define=GEMINI_API_KEY=your-key
```

Settings (top right): Gemini model, and "Let the Approver agent decide".

Build for hosting:

```bash
flutter build web --no-tree-shake-icons
```

## Project layout

```
lib/
  main.dart           Theme (orange / purple, Bricolage Grotesque header)
  home_page.dart      Upload, 4-step flow, decision, invoice data, audit log
  agents.dart         Extractor, Checker, Approver, Exporter
  gemini_client.dart  Gemini REST client
  guard.dart          Injection guard + §14 UStG rules
  excel_export.dart   Excel export
  settings.dart       API key / model / auto-approve (localStorage)
  models.dart         Data models
docs/PLAN.md          Hackathon plan
```
