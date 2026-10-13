import 'package:PiliPlus/services/thread_ripper/host_book.dart';
import 'package:PiliPlus/services/thread_ripper/range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var now = 1;
  late HostBook book;

  setUp(() {
    now = 1;
    book = HostBook(clock: () => now);
  });

  test(
    'speeds are per file: a host fast on one file is unmeasured on the next',
    () {
      book
        ..recordRate('a', 'file1', 400 * 1024, 100) // 4 KB/ms
        ..recordTtfb('a', 'file1', 50);

      expect(book.isMeasured('a', 'file1'), isTrue);
      expect(book.isMeasured('a', 'file2'), isFalse);
      // On a new file both hosts start from the same typical speed
      expect(
        book.estimate('a', 'file2', 1024 * 1024),
        book.estimate('b', 'file2', 1024 * 1024),
      );
      // ...which still comes from what was seen elsewhere, not a blind prior
      expect(book.typicalRate('file2'), closeTo(4096, 1));
    },
  );

  test('one odd sample does not swing a host', () {
    for (final ms in [100, 100, 100, 100]) {
      book.recordRate('a', 'f', 100 * 1024, ms); // 1 KB/ms
    }
    book.recordRate('a', 'f', 100 * 1024, 1); // a burst from a buffer
    expect(book.speedOf('a', 'f').rate, closeTo(1024, 1));
  });

  test('a connection idle for long costs another first byte', () {
    book
      ..recordTtfb('a', 'f', 200)
      ..recordRate('a', 'f', 100 * 1024, 100)
      ..noteEnd('a');
    final warm = book.speedOf('a', 'f').ttfb;
    now += HostBook.warmMs + 1;
    expect(book.speedOf('a', 'f').ttfb, warm * 2);
  });

  test(
    'failures while nothing arrives for long are the network, not the host',
    () {
      book
        ..noteStart()
        ..recordBytes('a', 1024);
      now += 3001;
      expect(book.recordFailure('b', MediaOutcome.network), isFalse);
      expect(book.isCoolingDown('b'), isFalse);

      book.recordBytes('a', 1024);
      expect(book.recordFailure('b', MediaOutcome.network), isTrue);
      expect(book.isCoolingDown('b'), isTrue);
    },
  );

  test('several hosts failing together is the network, and none is blamed', () {
    book
      ..noteStart()
      ..recordBytes('x', 1024);
    expect(book.recordFailure('a', MediaOutcome.network), isTrue);
    expect(book.recordFailure('b', MediaOutcome.truncated), isTrue);
    expect(book.isCoolingDown('a'), isTrue);
    // The third makes it clear: everyone is forgiven
    expect(book.recordFailure('c', MediaOutcome.network), isFalse);
    expect(book.isCoolingDown('a'), isFalse);
    expect(book.isCoolingDown('b'), isFalse);
    expect(book.isCoolingDown('c'), isFalse);
  });

  test(
    'a failed connection to a host that delivers elsewhere is that connection',
    () {
      book
        ..noteStart()
        ..recordBytes('a', 1024);
      now += 500;
      expect(book.recordFailure('a', MediaOutcome.truncated), isTrue);
      expect(book.isCoolingDown('a'), isFalse);
      expect(book['a'].failures, 0);
    },
  );

  test('a refusal always counts, network or not', () {
    book.noteStart();
    now += 5000;
    expect(book.recordFailure('a', MediaOutcome.refused), isTrue);
    expect(book.isCoolingDown('a'), isTrue);
  });

  test('probes are budgeted per file', () {
    for (var i = 0; i < HostBook.maxProbesPerFile; i++) {
      expect(book.mayProbe('f'), isTrue);
      book.noteProbe('f');
    }
    expect(book.mayProbe('f'), isFalse);
    expect(book.mayProbe('g'), isTrue);
  });
}
