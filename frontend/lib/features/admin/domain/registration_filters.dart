import '../data/registrations_api.dart';

/// The three lists in the Registrations tab.
enum RegistrationView {
  registered('Registered'),
  cancelled('Cancelled'),
  checkIns('Check-ins');

  const RegistrationView(this.label);
  final String label;
}

/// Columns the tables can be sorted by.
enum RegistrationSort { name, batch, registeredAt, cancelledAt }

/// Search, batch and branch filters for the registration lists.
class RegistrationFilters {
  const RegistrationFilters({this.query = '', this.batchYear, this.branch});

  final String query;
  final int? batchYear;
  final String? branch;

  bool get isEmpty => query.trim().isEmpty && batchYear == null && branch == null;

  /// Matches name, email, phone or registration number (case-insensitive).
  bool matchesText(AdminRegistration r) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final field in [r.fullname, r.email, r.phone, r.registrationNumber]) {
      if (field != null && field.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  bool matches(AdminRegistration r) {
    if (!matchesText(r)) return false;
    if (batchYear != null && r.batchYear != batchYear) return false;
    if (branch != null && r.branch != branch) return false;
    return true;
  }

  List<AdminRegistration> apply(Iterable<AdminRegistration> rows) =>
      rows.where(matches).toList();
}

/// Sorts [rows] by [by]; rows with no value for the column go last.
List<AdminRegistration> sortRegistrations(
  List<AdminRegistration> rows,
  RegistrationSort by, {
  required bool ascending,
}) {
  int compareNullable(Comparable<dynamic>? a, Comparable<dynamic>? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return ascending ? a.compareTo(b) : b.compareTo(a);
  }

  final sorted = [...rows];
  sorted.sort((a, b) {
    final int result;
    switch (by) {
      case RegistrationSort.name:
        result = compareNullable(
          a.displayName.toLowerCase(),
          b.displayName.toLowerCase(),
        );
      case RegistrationSort.batch:
        result = compareNullable(a.batchYear, b.batchYear);
      case RegistrationSort.registeredAt:
        result = compareNullable(a.registeredAt, b.registeredAt);
      case RegistrationSort.cancelledAt:
        result = compareNullable(a.cancelledAt, b.cancelledAt);
    }
    // Stable tie-break so equal rows don't jump around between rebuilds.
    return result != 0 ? result : a.registrationId.compareTo(b.registrationId);
  });
  return sorted;
}

/// Batch years present in [rows], newest first.
List<int> batchYearsIn(Iterable<AdminRegistration> rows) {
  final years = rows.map((r) => r.batchYear).whereType<int>().toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  return years;
}

/// Branches present in [rows], A–Z.
List<String> branchesIn(Iterable<AdminRegistration> rows) {
  final branches = rows.map((r) => r.branch).whereType<String>().toSet().toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return branches;
}

/// Plain words for the confirmation-email status the backend stores.
String confirmationEmailLabel(String? raw) {
  final status = raw?.trim() ?? '';
  switch (status) {
    case 'sent':
      return 'Sent';
    case 'failed':
      return 'Failed';
    case 'pending':
    case 'queued':
      return 'Pending';
    case 'skipped':
      return 'Not sent';
    case '':
      return '—';
    default:
      return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}
