import '../brand/brand_logo.dart';
import '../foundation/status.dart';

/// Presentation data for one conversation, including its live state.
class HistoryRow {
  const HistoryRow({required this.id, required this.title, required this.brand, required this.when, this.status});

  final String id, title, when;
  final Brand brand;
  final UiStatus? status;

  bool get working => status == UiStatus.working;

  @override
  bool operator ==(Object other) =>
      other is HistoryRow &&
      (id, title, brand, when, status) == (other.id, other.title, other.brand, other.when, other.status);

  @override
  int get hashCode => Object.hash(id, title, brand, when, status);
}
