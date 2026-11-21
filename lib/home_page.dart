import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agents.dart';
import 'excel_export.dart';
import 'models.dart';

const _samples = <(String, String, IconData)>[
  ('Valid invoice', 'assets/samples/01_valid_buerobedarf.txt', Icons.check_circle_outline),
  ('Missing VAT ID', 'assets/samples/02_missing_vat_id.txt', Icons.report_gmailerrorred),
  ('Prompt injection', 'assets/samples/03_prompt_injection.txt', Icons.gpp_bad_outlined),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.liveAvailable, required this.modelName, this.initError});
  final bool liveAvailable;
  final String modelName;
  final String? initError;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late bool _live = widget.liveAvailable;
  bool _busy = false;
  PipelineResult? _result;
  final List<PipelineResult> _approved = [];
  final List<LogEntry> _log = [];
  final _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _addLog(LogEntry('System',
        widget.liveAvailable ? 'Firebase connected. Gemini agents ready.' : 'No Firebase config – running offline demo agents.'));
    if (widget.initError != null) _addLog(LogEntry('System', widget.initError!, level: LogLevel.warn));
  }

  void _addLog(LogEntry e) {
    setState(() => _log.add(e));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(_logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  static String _mime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'txt' || 'md' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt'],
    );
    if (files.isEmpty) return;
    final f = files.first;
    await _process(UploadedDoc(f.name, _mime(f.name), await f.readAsBytes()));
  }

  Future<void> _loadSample(String path) async {
    final data = await rootBundle.loadString(path);
    await _process(UploadedDoc(path.split('/').last, 'text/plain', utf8.encode(data)));
  }

  Future<void> _process(UploadedDoc doc) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final agents = Agents(live: _live, modelName: widget.modelName);
      final r = await agents.run(doc, _addLog);
      setState(() => _result = r);
    } catch (e) {
      _addLog(LogEntry('System', 'Pipeline error: $e', level: LogLevel.block));
    } finally {
      setState(() => _busy = false);
    }
  }

  void _approve() {
    final r = _result!;
    setState(() {
      r.decision = 'approved';
      r.decidedAt = DateTime.now();
      _approved.add(r);
    });
    _addLog(LogEntry('Human', 'APPROVED ${r.fileName} – booking ${r.booking?.account} an ${r.booking?.contraAccount}',
        level: LogLevel.human));
    final name = ExcelExport.download(_approved, _log);
    _addLog(LogEntry('System', 'Excel written after approval: $name (${_approved.length} booking(s))', level: LogLevel.human));
  }

  void _reject() {
    final r = _result!;
    setState(() {
      r.decision = 'rejected';
      r.decidedAt = DateTime.now();
    });
    _addLog(LogEntry('Human', 'REJECTED ${r.fileName}. Nothing written.', level: LogLevel.human));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BelegGuard', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Agents check receipts for §14 UStG compliance – and resist manipulation.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          Tooltip(
            message: widget.liveAvailable ? 'Use Gemini via Firebase AI Logic' : 'Start with --dart-define Firebase config to enable',
            child: Row(children: [
              Text(_live ? 'Gemini live' : 'Offline demo', style: TextStyle(color: cs.onSurfaceVariant)),
              Switch(value: _live, onChanged: widget.liveAvailable && !_busy ? (v) => setState(() => _live = v) : null),
            ]),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 1000;
        final main = ListView(padding: const EdgeInsets.all(16), children: [
          _uploadCard(),
          if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator()),
          if (_result != null) _ResultCard(result: _result!, onApprove: _approve, onReject: _reject),
          if (!wide) SizedBox(height: 420, child: _LogPanel(log: _log, controller: _logScroll)),
        ]);
        if (!wide) return main;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: main),
          SizedBox(
            width: 440,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              child: _LogPanel(log: _log, controller: _logScroll),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _uploadCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('1. Upload an invoice', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('PDF, image or text. Extractor → Checker → Booker run one after another; you decide at the end.'),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload invoice'),
            ),
            const Text('or try a sample:'),
            for (final (label, path, icon) in _samples)
              ActionChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                onPressed: _busy ? null : () => _loadSample(path),
              ),
          ]),
          if (_approved.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => ExcelExport.download(_approved, _log),
              icon: const Icon(Icons.download),
              label: Text('Download Excel again (${_approved.length} approved)'),
            ),
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Result card

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onApprove, required this.onReject});
  final PipelineResult result;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final inv = result.invoice;
    final chk = result.check;
    final b = result.booking;
    final blocked = chk.status == CheckStatus.blocked;
    final (statusColor, statusLabel, statusIcon) = switch (chk.status) {
      CheckStatus.ok => (Colors.green.shade700, 'Compliant', Icons.verified),
      CheckStatus.warning => (Colors.orange.shade800, 'Needs attention', Icons.warning_amber),
      CheckStatus.blocked => (cs.error, 'Blocked – manipulation detected', Icons.gpp_bad),
    };
    String money(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)} €';

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('2. Agent results · ${result.fileName}', style: t.titleMedium)),
            Chip(
              avatar: Icon(statusIcon, color: statusColor, size: 18),
              label: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
              side: BorderSide(color: statusColor),
            ),
          ]),
          const Divider(height: 28),
          _AgentSection(
            title: 'Extractor',
            icon: Icons.document_scanner_outlined,
            reasoning: inv.reasoning,
            child: Wrap(spacing: 24, runSpacing: 8, children: [
              _kv('Supplier', inv.supplierName),
              _kv('VAT ID', inv.vatId ?? (inv.taxNumber != null ? 'St.-Nr. ${inv.taxNumber}' : null)),
              _kv('Invoice no.', inv.invoiceNumber),
              _kv('Date', inv.invoiceDate),
              _kv('Delivery', inv.deliveryDate),
              _kv('Net', money(inv.net)),
              _kv('VAT', '${money(inv.vat)}${inv.vatRate != null ? ' (${inv.vatRate!.round()} %)' : ''}'),
              _kv('Gross', money(inv.gross)),
              _kv('Description', inv.description),
            ]),
          ),
          _AgentSection(
            title: 'Checker',
            icon: Icons.rule,
            reasoning: chk.reasoning,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (chk.issues.isEmpty) const Text('No issues found.'),
              for (final i in chk.issues)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    switch (i.severity) {
                      Severity.critical => Icons.gpp_bad,
                      Severity.error => Icons.error_outline,
                      Severity.warning => Icons.warning_amber,
                      Severity.info => Icons.info_outline,
                    },
                    color: i.severity.index >= Severity.error.index ? cs.error : Colors.orange.shade800,
                  ),
                  title: Text(i.message),
                  subtitle: Text('${i.code} · via ${i.source}'),
                ),
              if (chk.injectionEvidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hidden instructions found (quoted, not followed):',
                        style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600)),
                    for (final e in chk.injectionEvidence)
                      Text('“$e”', style: TextStyle(color: cs.onErrorContainer, fontFamily: 'monospace', fontSize: 12)),
                  ]),
                ),
              ],
            ]),
          ),
          _AgentSection(
            title: 'Booker',
            icon: Icons.account_balance_outlined,
            reasoning: b?.reasoning ?? '',
            child: b == null
                ? const Text('Skipped – blocked invoices are never booked.')
                : Wrap(spacing: 24, runSpacing: 8, children: [
                    _kv('Account (SKR03)', '${b.account} ${b.accountName ?? ''}'),
                    _kv('Contra account', '${b.contraAccount} ${b.contraAccountName ?? ''}'),
                    _kv('Tax code (BU)', b.taxCode?.isEmpty ?? true ? '—' : b.taxCode),
                    _kv('Booking text', b.bookingText),
                    _kv('Confidence', b.confidence == null ? null : '${(b.confidence! * 100).round()} %'),
                  ]),
          ),
          const Divider(height: 28),
          Text('3. Human decision', style: t.titleMedium),
          const SizedBox(height: 8),
          if (result.decision == 'pending')
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Tooltip(
                message: blocked ? 'Blocked invoices cannot be approved' : 'Writes the booking to Excel',
                child: FilledButton.icon(
                  onPressed: blocked ? null : onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('Approve & export Excel'),
                ),
              ),
              OutlinedButton.icon(onPressed: onReject, icon: const Icon(Icons.close), label: const Text('Reject')),
              if (chk.status == CheckStatus.warning)
                Text('Check the issues above before approving.', style: TextStyle(color: Colors.orange.shade800)),
            ])
          else
            Row(children: [
              Icon(result.decision == 'approved' ? Icons.check_circle : Icons.cancel,
                  color: result.decision == 'approved' ? Colors.green.shade700 : cs.error),
              const SizedBox(width: 8),
              Text(result.decision == 'approved' ? 'Approved – Excel downloaded.' : 'Rejected – nothing written.',
                  style: t.bodyLarge),
            ]),
        ]),
      ),
    );
  }

  Widget _kv(String k, String? v) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 320),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(v ?? '— missing —', style: TextStyle(fontWeight: FontWeight.w600, color: v == null ? Colors.red : null)),
        ]),
      );
}

class _AgentSection extends StatelessWidget {
  const _AgentSection({required this.title, required this.icon, required this.child, required this.reasoning});
  final String title;
  final IconData icon;
  final Widget child;
  final String reasoning;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 8),
          Text('$title agent', style: Theme.of(context).textTheme.titleSmall),
        ]),
        const SizedBox(height: 10),
        child,
        if (reasoning.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.psychology_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(reasoning, style: TextStyle(color: cs.onSurfaceVariant))),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------------ Log panel

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.log, required this.controller});
  final List<LogEntry> log;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Icon(Icons.receipt_long, color: cs.primary),
            const SizedBox(width: 8),
            Text('Audit log', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('${log.length} events', style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.all(12),
            itemCount: log.length,
            itemBuilder: (context, i) {
              final e = log[i];
              final color = switch (e.level) {
                LogLevel.block => cs.error,
                LogLevel.warn => Colors.orange.shade800,
                LogLevel.human => Colors.green.shade700,
                LogLevel.agent => cs.primary,
                LogLevel.info => cs.onSurfaceVariant,
              };
              final time = e.at.toIso8601String().substring(11, 19);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text.rich(
                  TextSpan(style: const TextStyle(fontFamily: 'monospace', fontSize: 12), children: [
                    TextSpan(text: '$time ', style: TextStyle(color: cs.onSurfaceVariant)),
                    TextSpan(text: '[${e.actor}] ', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    TextSpan(text: e.message),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
