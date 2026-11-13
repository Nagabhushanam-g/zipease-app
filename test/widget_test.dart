import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_guard.dart';

void main() {
  test('initial archive safeguards have a fixed 1 GiB bound', () {
    expect(ArchiveGuard.maxExpandedBytes, 1073741824);
    expect(ArchiveGuard.maxEntries, 10000);
  });
}
