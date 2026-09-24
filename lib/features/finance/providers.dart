import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/finance.dart';
import '../../data/repositories/finance_repository.dart';
import '../reports/csv_download.dart';
import '../reports/providers.dart' show ReportFilter;

/// Today's figures and the export header of one resort, keyed by property
/// id so switching resort never shows another resort's money. Every finance
/// provider is `autoDispose`: opening the screen or a tab always queries
/// afresh.
final financeSummaryProvider = FutureProvider.autoDispose
    .family<FinanceSummary, String>(
      (ref, propertyId) => ref.watch(financeSourceProvider).summary(propertyId),
    );

final collectionsProvider = FutureProvider.autoDispose
    .family<List<CollectionRow>, ReportFilter>(
      (ref, f) => ref
          .watch(financeSourceProvider)
          .collections(f.from, f.to, f.propertyId),
    );

final ledgerProvider = FutureProvider.autoDispose
    .family<List<LedgerRow>, ReportFilter>(
      (ref, f) =>
          ref.watch(financeSourceProvider).ledger(f.from, f.to, f.propertyId),
    );

final settlementsProvider = FutureProvider.autoDispose
    .family<List<SettlementRow>, ReportFilter>(
      (ref, f) => ref
          .watch(financeSourceProvider)
          .settlements(f.from, f.to, f.propertyId),
    );

/// Call after anything that moves money (a checkout, a walk-in sale), so an
/// open Finance screen refetches every resort's figures.
void invalidateFinance(WidgetRef ref) {
  ref
    ..invalidate(financeSummaryProvider)
    ..invalidate(collectionsProvider)
    ..invalidate(ledgerProvider)
    ..invalidate(settlementsProvider);
}

/// Hands a CSV to the user; false where the platform cannot (see
/// `csv_download.dart`). A provider so widget tests can capture the file.
typedef CsvDownloader = bool Function(String filename, String csv);

final csvDownloaderProvider = Provider<CsvDownloader>((ref) => downloadCsv);
