/// One column of a [ReportPdf] table.
class ReportPdfColumn {
  const ReportPdfColumn(this.header, {this.numeric = false, this.flex = 1});

  final String header;

  /// Right-aligned when true.
  final bool numeric;

  /// Relative width.
  final double flex;
}

/// A tabular report ready to lay out: already formatted strings, one per
/// cell. Built by lib/features/finance/finance_pdf.dart, rendered by
/// lib/core/pdf/report_pdf_renderer.dart.
class ReportPdf {
  const ReportPdf({
    required this.title,
    required this.resortName,
    required this.gstinLabel,
    required this.periodLabel,
    required this.fileName,
    required this.columns,
    required this.rows,
    this.totals,
    this.notes = const [],
    this.emptyMessage = 'Nothing to report in this period.',
  });

  final String title;
  final String resortName;

  /// `GSTIN 29ABCDE1234F1Z5` or `GSTIN not set`.
  final String gstinLabel;

  /// `1 Aug 2026 – 31 Aug 2026`.
  final String periodLabel;
  final String fileName;
  final List<ReportPdfColumn> columns;

  /// Every row has exactly `columns.length` cells.
  final List<List<String>> rows;

  /// A bold last row, or none.
  final List<String>? totals;

  /// Lines printed under the table.
  final List<String> notes;

  /// Printed instead of the table when [rows] is empty.
  final String emptyMessage;
}
