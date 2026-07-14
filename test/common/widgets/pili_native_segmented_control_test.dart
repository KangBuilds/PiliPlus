import 'package:PiliPlus/common/widgets/pili_native_segmented_control.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('passes labels and selected index as creation parameters', () {
    expect(
      piliNativeSegmentedControlCreationParams(
        labels: const ['推荐', '热门', '分区'],
        selectedIndex: 1,
      ),
      <String, Object>{
        'labels': const ['推荐', '热门', '分区'],
        'selectedIndex': 1,
      },
    );
  });

  test('forwards taps and deduplicates selected-index updates', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methodChannel = MethodChannel('pili_native_segmented_control_7');
    final outgoingCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      outgoingCalls.add(call);
      return null;
    });

    final tappedIndices = <int>[];
    final channel = PiliNativeSegmentedControlChannel(
      onTap: tappedIndices.add,
      binaryMessenger: messenger,
    )..attach(7, 0);

    await channel.handleMethodCall(
      const MethodCall('valueChanged', <String, int>{'index': 1}),
    );
    expect(tappedIndices, <int>[1]);

    await channel.setSelectedIndex(1);
    expect(outgoingCalls, isEmpty);

    await channel.setSelectedIndex(2);
    await channel.setSelectedIndex(2);
    expect(outgoingCalls, hasLength(1));
    expect(outgoingCalls.single.method, 'setSelectedIndex');
    expect(outgoingCalls.single.arguments, <String, int>{'index': 2});

    channel.dispose();
    messenger.setMockMethodCallHandler(methodChannel, null);
  });
}
