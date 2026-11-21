// The only page: upload → 4-step agent flow → decision → archive + audit log.
// It owns the state and the flow; all visuals live in ../components.

import 'dart:typed_data';

import 'package:belegguard_shared/models.dart';
import 'package:flutter/material.dart';

import '../components/archive_card.dart';
import '../components/audit_log.dart';
import '../components/invoice_details_card.dart';
import '../components/recommendation_box.dart';
import '../components/settings_dialog.dart';
import '../components/step_row.dart';
import '../components/upload_card.dart';
import '../services/api_client.dart';
import '../services/archive.dart';
import '../services/excel_export.dart';
import '../services/settings.dart';
import '../theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _steps = [
    FlowStep('Extract', 'Extractor agent', Icons.document_scanner_outlined),
    FlowStep('Check', 'Checker agent', Icons.policy_outlined),
    FlowStep('Approve', 'Approver agent + you', Icons.how_to_reg_outlined),
    FlowStep('Export', 'Exporter agent', Icons.table_view_outlined),
  ];
  final List<LogEntry> _log = [];
  final List<InvoiceCase> _archive = Archive.load();
  InvoiceCase? _case;
  bool _busy = false;
  String? _error;

  ApiClient get _api => ApiClient(Settings.backendUrl);

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    final model = await _api.health();
    if (!mounted) return;
    model == null
        ? _addLog(
            'System',
            'Backend not reachable at ${Settings.backendUrl} – start it with: cd backend && dart run bin/server.dart',
            level: LogLevel.block,
          )
        : _addLog('System', 'Connected to backend (model $model)');
  }

  void _addLog(String actor, String msg, {LogLevel level = LogLevel.info, String? detail}) =>
      setState(() => _log.insert(0, LogEntry(actor, msg, level: level, detail: detail)));

  void _set(int i, FlowState s, [String summary = '']) => setState(() {
    _steps[i].state = s;
    _steps[i].summary = summary;
  });

  // ------------------------------------------------------------------ flow

  Future<void> _run(String name, String mime, Uint8List bytes) async {
    final c = InvoiceCase(name, mimeType: mime, bytes: bytes);
    setState(() {
      _case = c;
      _busy = true;
      _error = null;
      for (final s in _steps) {
        s.state = FlowState.idle;
        s.summary = '';
      }
    });
    _addLog('System', 'Invoice received: $name (${(bytes.length / 1024).toStringAsFixed(0)} KB)');
    final sw = Stopwatch()..start();
    String took() {
      final t = '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
      sw.reset();
      return t;
    }

    var i = 0;
    try {
      // 1 · Extract
      _set(i, FlowState.running, 'Reading the document…');
      final (id, inv) = await _api.extract(name, mime, bytes);
      c.serverId = id;
      c.invoice = inv;
      _set(i, FlowState.done, '${inv.supplierName ?? 'Unknown supplier'} · ${money(inv.gross)}');
      _addLog(
        'Extractor',
        'Extracted ${inv.supplierName ?? '?'}, invoice ${inv.invoiceNumber ?? '?'}, ${money(inv.gross)} (${took()})',
        detail: inv.reasoning,
      );

      // 2 · Check
      i = 1;
      _set(i, FlowState.running, 'Checking §14 UStG, VAT and hidden instructions…');
      final chk = await _api.check(id);
      c.check = chk;
      final n = chk.issues.length;
      switch (chk.status) {
        case CheckStatus.ok:
          _set(i, FlowState.done, 'Compliant – no issues');
          _addLog('Checker', 'Compliant (${took()})', detail: chk.reasoning);
        case CheckStatus.warning:
          _set(i, FlowState.warning, '$n issue${n == 1 ? '' : 's'} found');
          _addLog(
            'Checker',
            '$n issue(s): ${chk.issues.map((e) => e.code).join(', ')} (${took()})',
            level: LogLevel.warn,
            detail: chk.reasoning,
          );
        case CheckStatus.blocked:
          _set(i, FlowState.failed, 'Blocked – manipulation detected');
          _addLog(
            'Checker',
            'BLOCKED: hidden instructions in the invoice (${took()})',
            level: LogLevel.block,
            detail: chk.injectionEvidence.join('\n'),
          );
      }

      // 3 · Approve
      i = 2;
      _set(i, FlowState.running, 'Approver agent is reviewing…');
      final rec = await _api.recommend(id);
      c.recommendation = rec;
      _addLog('Approver', 'Recommends: ${rec.decision.replaceAll('_', ' ')} (${took()})', detail: rec.reasoning);

      if (chk.status == CheckStatus.blocked) {
        await _decide(c, approved: false, by: 'guard');
      } else if (Settings.autoApprove && rec.decision == 'approve') {
        await _decide(c, approved: true, by: 'approver agent');
      } else if (Settings.autoApprove && rec.decision == 'reject') {
        await _decide(c, approved: false, by: 'approver agent');
      } else {
        _set(i, FlowState.waiting, 'Your decision is needed');
        _addLog('System', 'Waiting for human approval – nothing written yet', level: LogLevel.human);
      }
    } on ApiException catch (e) {
      _fail(i, e.message);
    } catch (e) {
      _fail(i, 'Unexpected error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _fail(int i, String msg) {
    _set(i, FlowState.failed, 'Failed');
    setState(() => _error = msg);
    _addLog('System', msg, level: LogLevel.block);
  }

  Future<void> _decide(InvoiceCase c, {required bool approved, required String by}) async {
    setState(() {
      c.decision = approved ? 'approved' : 'rejected';
      c.decidedBy = by;
      c.decidedAt = DateTime.now();
    });
    if (!approved) {
      _set(2, FlowState.failed, 'Rejected by $by');
      _set(3, FlowState.skipped, 'Nothing exported');
      _addLog(by == 'human' ? 'Human' : 'System', 'Rejected by $by – nothing written', level: LogLevel.block);
      return;
    }
    _set(2, FlowState.done, 'Approved by $by');
    _addLog(by == 'human' ? 'Human' : 'Approver', 'Approved by $by', level: LogLevel.human);

    setState(() => _busy = true);
    try {
      _set(3, FlowState.running, 'Mapping to SKR03 and filing…');
      final b = await _api.export(c.serverId!, approvedBy: by);
      c.booking = b;
      final copied = await Archive.file(c, _archive);
      c.bytes = null;
      _set(3, FlowState.done, '${b.account} ${b.accountName ?? ''} → filed under ${c.period}');
      _addLog(
        'Exporter',
        'Booked ${b.account} an ${b.contraAccount} (BU ${b.taxCode ?? '-'}), filed under ${c.period}',
        level: LogLevel.human,
        detail: b.reasoning,
      );
      if (!copied) {
        _addLog(
          'System',
          'Could not store the original file (IndexedDB) – booking filed without it',
          level: LogLevel.warn,
        );
      }
    } on ApiException catch (e) {
      _fail(3, e.message);
    } catch (e) {
      _fail(3, 'Export failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _remove(InvoiceCase c) async {
    await Archive.remove(c, _archive);
    _addLog('Human', 'Removed ${c.fileName} from the archive', level: LogLevel.human);
  }

  Future<void> _openSettings() async {
    await showDialog<void>(context: context, builder: (_) => const SettingsDialog());
    setState(() {});
    _checkBackend();
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final c = _case;
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 40),
                  UploadCard(busy: _busy, onFile: _run),
                  if (c != null) ...[const SizedBox(height: 28), _flowCard(c)],
                  if (c?.invoice != null) ...[const SizedBox(height: 28), InvoiceDetailsCard(invoiceCase: c!)],
                  const SizedBox(height: 28),
                  ArchiveCard(
                    archive: _archive,
                    onExcel: (shown) => ExcelExport.download(shown, _log.reversed.toList()),
                    onRemove: _remove,
                  ),
                  const SizedBox(height: 28),
                  AuditLog(log: _log),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: Brand.purple, size: 44),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'BelegGuard',
                    style: headline(64).copyWith(color: Brand.ink, height: 1.0, letterSpacing: -1.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'AI agents check your invoices for legal compliance – and resist manipulation.',
              style: TextStyle(fontSize: 17, color: Brand.muted),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Settings',
        onPressed: _openSettings,
        icon: const Icon(Icons.tune, color: Brand.purple),
      ),
    ],
  );

  Widget _flowCard(InvoiceCase c) {
    final waiting = _steps[2].state == FlowState.waiting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.fileName, style: headline(22)),
            const SizedBox(height: 22),
            for (var i = 0; i < _steps.length; i++) StepRow(step: _steps[i], last: i == _steps.length - 1),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: const TextStyle(color: Brand.red)),
              ),
            if (waiting) ...[
              const SizedBox(height: 8),
              RecommendationBox(recommendation: c.recommendation!),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => _decide(c, approved: true, by: 'human'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve & export'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decide(c, approved: false, by: 'human'),
                    icon: const Icon(Icons.close_rounded, color: Brand.purple),
                    label: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
