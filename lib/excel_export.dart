// Excel export – only ever called after a human pressed "Approve".

import 'package:excel/excel.dart';

import 'models.dart';

class ExcelExport {
  static String _ts(DateTime d) => d.toIso8601String().substring(0, 19).replaceFirst('T', ' ');

  /// Builds the workbook and triggers a browser download. Returns the file name.
  static String download(List<PipelineResult> approved, List<LogEntry> log) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    excel.rename(defaultSheet, 'Buchungen');
    final s = excel['Buchungen'];

    final header = [
      'Belegdatum', 'Rechnungsnr.', 'Lieferant', 'USt-IdNr.', 'Netto', 'USt-Satz %', 'USt', 'Brutto',
      'Konto (Soll)', 'Kontoname', 'Gegenkonto (Haben)', 'BU-Schlüssel', 'Buchungstext',
      'Prüfstatus', 'Hinweise', 'Freigegeben am', 'Datei',
    ];
    s.appendRow(header.map((h) => TextCellValue(h)).toList());

    CellValue? num(double? v) => v == null ? null : DoubleCellValue(v);
    CellValue? txt(String? v) => v == null ? null : TextCellValue(v);

    for (final r in approved) {
      final i = r.invoice;
      final b = r.booking;
      s.appendRow([
        txt(i.invoiceDate),
        txt(i.invoiceNumber),
        txt(i.supplierName),
        txt(i.vatId),
        num(i.net),
        num(i.vatRate),
        num(i.vat),
        num(i.gross),
        txt(b?.account),
        txt(b?.accountName),
        txt(b?.contraAccount),
        txt(b?.taxCode),
        txt(b?.bookingText),
        TextCellValue(r.check.status.name.toUpperCase()),
        TextCellValue(r.check.issues.map((e) => e.code).join(', ')),
        txt(r.decidedAt == null ? null : _ts(r.decidedAt!)),
        TextCellValue(r.fileName),
      ]);
    }

    final a = excel['Audit-Log'];
    a.appendRow([TextCellValue('Zeit'), TextCellValue('Akteur'), TextCellValue('Ereignis')]);
    for (final e in log) {
      a.appendRow([TextCellValue(_ts(e.at)), TextCellValue(e.actor), TextCellValue(e.message)]);
    }

    final name = 'BelegGuard_${DateTime.now().toIso8601String().substring(0, 10)}.xlsx';
    excel.save(fileName: name); // on web this triggers the download
    return name;
  }
}
