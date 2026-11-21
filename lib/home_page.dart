import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'agents.dart';
import 'archive.dart';
import 'excel_export.dart';
import 'gemini_client.dart';
import 'main.dart' show Brand;
import 'models.dart';
import 'settings.dart';

enum StepState { idle, running, done, warning, failed, waiting, skipped }

class FlowStep {
  FlowStep(this.title, this.agent, this.icon);
  final String title;
  final String agent;
  final IconData icon;
  StepState state = StepState.idle;
  String summary = '';
}

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
  String _query = '';
  InvoiceCase? _case;
  bool _busy = false;
  String? _error;

  bool get _hasKey => Settings.apiKey.isNotEmpty;
  Agents get _agents => Agents(GeminiClient(apiKey: Settings.apiKey, model: Settings.model));

  void _log_(String actor, String msg, {LogLevel level = LogLevel.info, String? detail}) =>
      setState(() => _log.insert(0, LogEntry(actor, msg, level: level, detail: detail)));

  void _set(int i, StepState s, [String summary = '']) => setState(() {
        _steps[i].state = s;
        _steps[i].summary = summary;
      });

  static String _mime(String name) => switch (name.split('.').last.toLowerCase()) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'txt' => 'text/plain',
        _ => 'application/octet-stream',
      };

  static String _money(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)} €';

  // ------------------------------------------------------------------ flow

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt'],
    );
    if (files.isEmpty) return;
    final f = files.first;
    await _run(UploadedDoc(f.name, _mime(f.name), await f.readAsBytes()));
  }

  Future<void> _run(UploadedDoc doc) async {
    final c = InvoiceCase(doc.name, mimeType: doc.mimeType, bytes: doc.bytes);
    setState(() {
      _case = c;
      _busy = true;
      _error = null;
      for (final s in _steps) {
        s.state = StepState.idle;
        s.summary = '';
      }
    });
    _log_('System', 'Invoice received: ${doc.name} (${(doc.bytes.length / 1024).toStringAsFixed(0)} KB)');
    var i = 0;
    try {
      // 1 · Extract
      _set(i, StepState.running, 'Reading the document…');
      final inv = await _agents.extract(doc);
      c.invoice = inv;
      _set(i, StepState.done, '${inv.supplierName ?? 'Unknown supplier'} · ${_money(inv.gross)}');
      _log_('Extractor', 'Extracted ${inv.supplierName ?? '?'}, invoice ${inv.invoiceNumber ?? '?'}, ${_money(inv.gross)}',
          detail: inv.reasoning);

      // 2 · Check
      i = 1;
      _set(i, StepState.running, 'Checking §14 UStG, VAT and hidden instructions…');
      final chk = await _agents.check(inv);
      c.check = chk;
      final n = chk.issues.length;
      switch (chk.status) {
        case CheckStatus.ok:
          _set(i, StepState.done, 'Compliant – no issues');
          _log_('Checker', 'Compliant', detail: chk.reasoning);
        case CheckStatus.warning:
          _set(i, StepState.warning, '$n issue${n == 1 ? '' : 's'} found');
          _log_('Checker', '$n issue(s): ${chk.issues.map((e) => e.code).join(', ')}',
              level: LogLevel.warn, detail: chk.reasoning);
        case CheckStatus.blocked:
          _set(i, StepState.failed, 'Blocked – manipulation detected');
          _log_('Checker', 'BLOCKED: hidden instructions in the invoice', level: LogLevel.block,
              detail: chk.injectionEvidence.join('\n'));
      }

      // 3 · Approve
      i = 2;
      _set(i, StepState.running, 'Approver agent is reviewing…');
      final rec = await _agents.recommend(inv, chk);
      c.recommendation = rec;
      _log_('Approver', 'Recommends: ${rec.decision.replaceAll('_', ' ')}', detail: rec.reasoning);

      if (chk.status == CheckStatus.blocked) {
        await _decide(c, approved: false, by: 'guard');
      } else if (Settings.autoApprove && rec.decision == 'approve') {
        await _decide(c, approved: true, by: 'approver agent');
      } else if (Settings.autoApprove && rec.decision == 'reject') {
        await _decide(c, approved: false, by: 'approver agent');
      } else {
        _set(i, StepState.waiting, 'Your decision is needed');
        _log_('System', 'Waiting for human approval – nothing written yet', level: LogLevel.human);
      }
    } on GeminiException catch (e) {
      _fail(i, e.message);
    } catch (e) {
      _fail(i, 'Unexpected error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _fail(int i, String msg) {
    _set(i, StepState.failed, 'Failed');
    setState(() => _error = msg);
    _log_('System', msg, level: LogLevel.block);
  }

  Future<void> _decide(InvoiceCase c, {required bool approved, required String by}) async {
    setState(() {
      c.decision = approved ? 'approved' : 'rejected';
      c.decidedBy = by;
      c.decidedAt = DateTime.now();
    });
    if (!approved) {
      _set(2, StepState.failed, 'Rejected by $by');
      _set(3, StepState.skipped, 'Nothing exported');
      _log_(by == 'human' ? 'Human' : 'System', 'Rejected by $by – nothing written', level: LogLevel.block);
      return;
    }
    _set(2, StepState.done, 'Approved by $by');
    _log_(by == 'human' ? 'Human' : 'Approver', 'Approved by $by', level: LogLevel.human);

    setState(() => _busy = true);
    try {
      _set(3, StepState.running, 'Mapping to SKR03 and writing Excel…');
      final b = await _agents.export(c.invoice!);
      c.booking = b;
      final copied = Archive.file(c, _archive);
      c.bytes = null;
      _set(3, StepState.done, '${b.account} ${b.accountName ?? ''} → filed under ${c.period}');
      _log_('Exporter', 'Booked ${b.account} an ${b.contraAccount} (BU ${b.taxCode ?? '-'}), filed under ${c.period}',
          level: LogLevel.human, detail: b.reasoning);
      if (!copied) {
        _log_('System', 'Browser storage full – booking filed, but the original file was not copied',
            level: LogLevel.warn);
      }
    } on GeminiException catch (e) {
      _fail(3, e.message);
    } catch (e) {
      _fail(3, 'Export failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 64),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(),
                const SizedBox(height: 40),
                _hasKey ? _uploadCard() : _ApiKeyCard(onSaved: () => setState(() {})),
                if (_case != null) ...[
                  const SizedBox(height: 28),
                  _flowCard(),
                ],
                if (_case?.invoice != null) ...[
                  const SizedBox(height: 28),
                  _detailsCard(),
                ],
                const SizedBox(height: 28),
                _archiveCard(),
                const SizedBox(height: 28),
                _AuditLog(log: _log),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.shield_outlined, color: Brand.purple, size: 44),
            const SizedBox(width: 10),
            Flexible(
              child: Text('BelegGuard',
                  style: GoogleFonts.bricolageGrotesque(
                      fontSize: 64, fontWeight: FontWeight.w600, color: Brand.ink, height: 1.0, letterSpacing: -1.5)),
            ),
          ]),
          const SizedBox(height: 12),
          const Text('AI agents check your invoices for legal compliance – and resist manipulation.',
              style: TextStyle(fontSize: 17, color: Brand.muted)),
        ]),
      ),
      IconButton(
        tooltip: 'Settings',
        onPressed: _openSettings,
        icon: const Icon(Icons.tune, color: Brand.purple),
      ),
    ]);
  }

  Widget _uploadCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(color: Brand.purpleSoft, shape: BoxShape.circle),
            child: const Icon(Icons.upload_file_rounded, size: 36, color: Brand.purple),
          ),
          const SizedBox(height: 18),
          Text('Drop in an invoice',
              style: GoogleFonts.bricolageGrotesque(fontSize: 26, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('PDF, JPG, PNG or WEBP', style: TextStyle(color: Brand.muted)),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_rounded),
            label: Text(_busy ? 'Agents at work…' : 'Choose invoice'),
          ),
        ]),
      ),
    );
  }

  Widget _flowCard() {
    final c = _case!;
    final waiting = _steps[2].state == StepState.waiting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.fileName, style: GoogleFonts.bricolageGrotesque(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 22),
          for (var i = 0; i < _steps.length; i++) _StepRow(step: _steps[i], last: i == _steps.length - 1),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: const TextStyle(color: Brand.red)),
            ),
          if (waiting) ...[
            const SizedBox(height: 8),
            _recommendationBox(c.recommendation!),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
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
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _recommendationBox(ApprovalRecommendation r) {
    final label = switch (r.decision) {
      'approve' => 'Approver agent recommends: approve',
      'reject' => 'Approver agent recommends: reject',
      _ => 'Approver agent recommends: human review',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Brand.purpleSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome, color: Brand.purple, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (r.reasoning.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.reasoning, style: const TextStyle(color: Brand.muted)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _detailsCard() {
    final c = _case!;
    final inv = c.invoice!;
    final chk = c.check;
    final b = c.booking;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Invoice data', style: GoogleFonts.bricolageGrotesque(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Wrap(runSpacing: 16, children: [
            _kv('Supplier', inv.supplierName),
            _kv('Invoice no.', inv.invoiceNumber),
            _kv('Date', inv.invoiceDate),
            _kv('VAT ID', inv.vatId ?? (inv.taxNumber != null ? 'St.-Nr. ${inv.taxNumber}' : null)),
            _kv('Net', _money(inv.net)),
            _kv('VAT', inv.vat == null ? null : '${_money(inv.vat)}${inv.vatRate != null ? ' · ${inv.vatRate!.round()} %' : ''}'),
            _kv('Gross', _money(inv.gross)),
            _kv('Delivery', inv.deliveryDate),
          ]),
          if (chk != null && chk.issues.isNotEmpty) ...[
            const Divider(height: 40, color: Brand.line),
            const Text('Findings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 10),
            for (final i in chk.issues)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                    i.severity == Severity.critical
                        ? Icons.gpp_bad_outlined
                        : i.severity == Severity.error
                            ? Icons.error_outline
                            : Icons.info_outline,
                    size: 20,
                    color: Brand.purple,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(i.message)),
                ]),
              ),
            if (chk.injectionEvidence.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Brand.cream, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Quoted, not followed:', style: TextStyle(fontWeight: FontWeight.w600, color: Brand.muted)),
                  const SizedBox(height: 6),
                  for (final e in chk.injectionEvidence.take(3))
                    Text('“$e”', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Brand.ink)),
                ]),
              ),
            ],
          ],
          if (b != null) ...[
            const Divider(height: 40, color: Brand.line),
            const Text('Booking (SKR03)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 14),
            Wrap(runSpacing: 16, children: [
              _kv('Account', '${b.account} ${b.accountName ?? ''}'),
              _kv('Contra account', '${b.contraAccount} ${b.contraAccountName ?? ''}'),
              _kv('Tax code', (b.taxCode ?? '').isEmpty ? '—' : b.taxCode),
              _kv('Booking text', b.bookingText),
            ]),
          ],
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ archive

  Widget _archiveCard() {
    final q = _query.trim().toLowerCase();
    final items = _archive.where((c) {
      if (q.isEmpty) return true;
      final i = c.invoice;
      return [c.fileName, i?.supplierName, i?.invoiceNumber, c.booking?.account, c.booking?.accountName, c.period]
          .any((v) => v != null && v.toLowerCase().contains(q));
    }).toList()
      ..sort((a, b) => (b.invoice?.invoiceDate ?? b.period).compareTo(a.invoice?.invoiceDate ?? a.period));

    final byMonth = <String, List<InvoiceCase>>{};
    for (final c in items) {
      byMonth.putIfAbsent(c.period, () => []).add(c);
    }
    final total = items.fold<double>(0, (sum, c) => sum + (c.invoice?.gross ?? 0));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.inventory_2_outlined, color: Brand.purple),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Receipt archive',
                  style: GoogleFonts.bricolageGrotesque(fontSize: 22, fontWeight: FontWeight.w600)),
            ),
            if (_archive.isNotEmpty)
              TextButton.icon(
                onPressed: () => ExcelExport.download(items, _log.reversed.toList()),
                icon: const Icon(Icons.download_rounded, color: Brand.purple),
                label: const Text('Excel', style: TextStyle(color: Brand.ink)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
              _archive.isEmpty
                  ? 'Approved receipts are copied and filed here, sorted by month.'
                  : '${items.length} receipt${items.length == 1 ? '' : 's'} · ${_money(total)} gross',
              style: const TextStyle(color: Brand.muted)),
          if (_archive.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                  hintText: 'Search supplier, invoice no., account, month…', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ],
          for (final entry in byMonth.entries) ...[
            const SizedBox(height: 20),
            Row(children: [
              const Icon(Icons.folder_outlined, size: 18, color: Brand.orangeDark),
              const SizedBox(width: 6),
              Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.orangeDark)),
              const SizedBox(width: 8),
              Text(
                  '${entry.value.length} · ${_money(entry.value.fold<double>(0, (s, c) => s + (c.invoice?.gross ?? 0)))}',
                  style: const TextStyle(color: Brand.muted)),
            ]),
            const Divider(color: Brand.line),
            for (final c in entry.value) _archiveRow(c),
          ],
        ]),
      ),
    );
  }

  Widget _archiveRow(InvoiceCase c) {
    final i = c.invoice;
    final b = c.booking;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i?.supplierName ?? c.fileName, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
                [i?.invoiceDate, i?.invoiceNumber, if (b?.account != null) '${b!.account} ${b.accountName ?? ''}']
                    .whereType<String>()
                    .join(' · '),
                style: const TextStyle(color: Brand.muted, fontSize: 13)),
          ]),
        ),
        Text(_money(i?.gross), style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(
          tooltip: c.hasOriginal ? 'Download original' : 'Original not stored (browser storage full)',
          onPressed: c.hasOriginal ? () => Archive.downloadOriginal(c) : null,
          icon: const Icon(Icons.file_download_outlined, color: Brand.purple),
        ),
        IconButton(
          tooltip: 'Remove from archive',
          onPressed: () {
            setState(() => Archive.remove(c, _archive));
            _log_('Human', 'Removed ${c.fileName} from the archive', level: LogLevel.human);
          },
          icon: const Icon(Icons.delete_outline, color: Brand.muted),
        ),
      ]),
    );
  }

  Widget _kv(String k, String? v) => SizedBox(
        width: 230,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k.toUpperCase(),
                style: const TextStyle(fontSize: 11, letterSpacing: 0.8, color: Brand.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(v ?? 'missing',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: v == null ? Brand.red : Brand.ink)),
          ]),
        ),
      );

  Future<void> _openSettings() async {
    await showDialog<void>(context: context, builder: (_) => const _SettingsDialog());
    setState(() {});
  }
}

// --------------------------------------------------------------- step row

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.last});
  final FlowStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, badge) = switch (step.state) {
      StepState.idle => (Brand.cream, Brand.muted, null),
      StepState.running => (Brand.purpleSoft, Brand.purple, null),
      StepState.done => (Brand.purpleSoft, Brand.purple, Icons.check_circle),
      StepState.warning => (Brand.orangeSoft, Brand.orangeDark, Icons.warning_rounded),
      StepState.waiting => (Brand.orangeSoft, Brand.orangeDark, Icons.hourglass_top_rounded),
      StepState.failed => (const Color(0xFFFEE2E2), Brand.red, Icons.cancel),
      StepState.skipped => (Brand.cream, Brand.muted, Icons.remove_circle_outline),
    };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: step.state == StepState.running
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Brand.purple))
                  : Icon(step.icon, color: step.state == StepState.idle ? Brand.muted : Brand.purple),
            ),
            if (badge != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(badge, size: 18, color: fg),
                ),
              ),
          ]),
          if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 6), color: Brand.line)),
        ]),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: last ? 4 : 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(step.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(width: 8),
                Text(step.agent, style: const TextStyle(color: Brand.muted, fontSize: 13)),
              ]),
              const SizedBox(height: 3),
              Text(step.summary.isEmpty ? 'Waiting' : step.summary,
                  style: TextStyle(color: step.state == StepState.idle ? Brand.muted : fg)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------- audit log

class _AuditLog extends StatelessWidget {
  const _AuditLog({required this.log});
  final List<LogEntry> log;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
          leading: const Icon(Icons.receipt_long_outlined, color: Brand.purple),
          iconColor: Brand.purple,
          collapsedIconColor: Brand.purple,
          title: Text('Audit log', style: GoogleFonts.bricolageGrotesque(fontSize: 20, fontWeight: FontWeight.w600)),
          subtitle: Text('${log.length} events · newest first', style: const TextStyle(color: Brand.muted)),
          children: [
            if (log.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('No events yet.')),
            for (final e in log) _row(e),
          ],
        ),
      ),
    );
  }

  Widget _row(LogEntry e) {
    final dot = switch (e.level) {
      LogLevel.block => Brand.red,
      LogLevel.warn => Brand.orange,
      LogLevel.human => Brand.green,
      _ => Brand.purple,
    };
    final row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 64,
        child: Text(e.at.toIso8601String().substring(11, 19),
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Brand.muted)),
      ),
      SizedBox(width: 84, child: Text(e.actor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      Expanded(child: Text(e.message, style: const TextStyle(fontSize: 13))),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: e.detail == null || e.detail!.isEmpty
          ? row
          : Tooltip(
              message: e.detail!,
              waitDuration: const Duration(milliseconds: 300),
              child: row,
            ),
    );
  }
}

// --------------------------------------------------------------- API key

class _ApiKeyCard extends StatefulWidget {
  const _ApiKeyCard({required this.onSaved});
  final VoidCallback onSaved;
  @override
  State<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends State<_ApiKeyCard> {
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.key_rounded, color: Brand.purple),
            const SizedBox(width: 10),
            Text('Connect Gemini', style: GoogleFonts.bricolageGrotesque(fontSize: 22, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          const Text(
              'Paste a Gemini API key from aistudio.google.com/apikey. It stays in this browser and is only sent to Google.',
              style: TextStyle(color: Brand.muted)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                obscureText: true,
                decoration: const InputDecoration(hintText: 'Gemini API key'),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ]),
        ]),
      ),
    );
  }

  void _save() {
    if (_ctrl.text.trim().isEmpty) return;
    Settings.apiKey = _ctrl.text;
    widget.onSaved();
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _model = TextEditingController(text: Settings.model);
  bool _auto = Settings.autoApprove;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Settings', style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Gemini model', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(controller: _model),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: Brand.orange,
            title: const Text('Let the Approver agent decide'),
            subtitle: const Text('Clear cases are approved or rejected automatically. Unclear ones still come to you.'),
            value: _auto,
            onChanged: (v) => setState(() => _auto = v),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Settings.apiKey = '';
              Navigator.pop(context);
            },
            icon: const Icon(Icons.key_off_rounded, color: Brand.purple),
            label: const Text('Remove API key', style: TextStyle(color: Brand.ink)),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Settings.model = _model.text.trim().isEmpty ? 'gemini-3.8-flash' : _model.text;
            Settings.autoApprove = _auto;
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
