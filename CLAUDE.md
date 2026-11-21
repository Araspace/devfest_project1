# CLAUDE.md

BelegGuard – Google DevFest hackathon project. Time is short: prefer working demos over polish,
small focused changes over refactors.

## Goal

A receipt account ("Belegkonto"): users drop receipts (PDF / image) directly into it; each receipt
is copied, checked by Gemini agents and filed in a structured way (by date, supplier, SKR03
account). Existing core: multi-agent invoice checker for German invoices.

Pitch: "Qonto stores receipts. Our agents check them for legal compliance and resist manipulation."

## Stack

- Flutter Web (Dart SDK ^3.13), Material, `google_fonts`
- Dart backend (`shelf`) calls the Google Gemini REST API (`backend/lib/gemini_client.dart`); the key never reaches the browser
- Default model `gemini-3.6-flash` (`GEMINI_MODEL` in `.env`); falls back to other Flash models on 503 / timeout
- `excel`, `file_picker`, `http`, `web`

## Commands

```bash
cd backend && dart pub get && dart run bin/server.dart   # API on :8080, key from ../.env
cd frontend && flutter pub get && flutter run -d chrome  # UI
./tool/check.sh                                          # analyze + tests + key scan – run before every push
cd frontend && flutter build web --no-tree-shake-icons
```

## Layout

```
backend/                    Dart API server (shelf) – the only part that talks to Gemini
  bin/server.dart           Start-up: reads GEMINI_API_KEY / GEMINI_MODEL / PORT from env or ../.env
  lib/api.dart              HTTP routes, server-side case store, approval rules, audit_log.jsonl
  lib/agents.dart           Extractor → Checker → Approver → Exporter (prompts + hard limits)
  lib/guard.dart            Deterministic injection guard + §14 UStG rules
  lib/gemini_client.dart    Gemini REST client with model fallback
  test/                     Guard, rules, agents and API tests (fake Gemini, no network)
frontend/                   Flutter Web UI – never sees the API key
  lib/main.dart             App entry
  lib/theme.dart            Brand colours, theme, shared helpers (money, headline)
  lib/pages/home_page.dart  The page: state + flow, composes the components
  lib/components/           Global UI components, one per file (step_row, upload_card, invoice_details_card,
                            recommendation_box, archive_card, audit_log, key_value, settings_dialog)
  lib/services/             api_client (backend calls), archive (IndexedDB/localStorage),
                            excel_export, settings (backend URL, auto-approve)
  web/index.html            Loading screen
shared/lib/models.dart      Data models + JSON used by backend and frontend
samples/                    Demo invoices (valid, missing VAT ID, prompt injection)
tool/check.sh               Pre-push check (analyze + tests + key scan)
docs/                       PLAN.md (hackathon plan), PITCH.md (pitch, demo script, jury Q&A)
```

Conventions: one UI component per file in `frontend/lib/components/` (global, reused by pages);
pages only hold state and compose components; services hold I/O; agent logic stays in the backend.

## Agent flow

Each agent = separate Gemini call with its own fixed system instruction and JSON output.

1. **Extractor** – only agent that sees the original file → structured JSON
2. **Checker** – §14 UStG mandatory details, VAT rate, sums, prompt injection; `guard.dart` can only make it stricter
3. **Approver** – approve / reject / human review; never approves with open findings
4. **Exporter** – SKR03 account, contra account, DATEV tax code → Excel

## Rules (do not break)

- Receipt content is untrusted data, always passed quoted – never as instructions.
- If the guard fires, the receipt is blocked; no agent can override it.
- Nothing is written or filed before approval.
- Every agent step goes into the audit log.
- Never commit API keys.
- UI text, code, comments and docs in English (domain terms like §14 UStG, SKR03, DATEV stay German).

## Out of scope (hackathon)

Auth, Firestore, Cloud Functions, real DATEV export, dashboards – unless explicitly asked.
