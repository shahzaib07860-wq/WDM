import '../lib/util/queue_window_policy.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 12),
      end = DateTime.utc(2026, 1, 1, 13);
  void expect(bool value, String message) {
    if (!value) throw StateError(message);
  }

  expect(
    !queueWindowOpen(start.subtract(Duration(seconds: 1)), start, end),
    'Future queue must wait',
  );
  expect(queueWindowOpen(start, start, end), 'Start is inclusive');
  expect(!queueWindowOpen(end, start, end), 'End is exclusive');
  expect(queueWindowOpen(start, null, null), 'Immediate queue');
  expect(
    !queueWindowOpen(end, null, end),
    'Immediate queue still respects end',
  );
  expect(
    queueAvailableSlots(1, 0) == 1 && queueAvailableSlots(3, 0) == 3,
    'Each queue uses its own limit',
  );
  expect(queueAvailableSlots(1, 2) == 0, 'No negative slots');
  print('PASS: 7 queue policy checks');
}
