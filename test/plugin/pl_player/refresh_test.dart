import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool fresh({bool openFailed = false, Duration? age}) =>
      PlPlayerController.shouldFetchFreshUrls(openFailed: openFailed, age: age);

  test('a failed open always fetches fresh URLs', () {
    expect(fresh(openFailed: true, age: Duration.zero), isTrue);
    expect(fresh(openFailed: true), isTrue);
  });

  test('a refresh reuses URLs while they are young', () {
    expect(fresh(age: const Duration(minutes: 5)), isFalse);
    expect(fresh(age: const Duration(minutes: 30)), isFalse);
    expect(fresh(), isFalse);
  });

  test('a refresh fetches fresh URLs once they may have expired', () {
    expect(fresh(age: const Duration(minutes: 31)), isTrue);
    expect(fresh(age: const Duration(hours: 3)), isTrue);
  });
}
