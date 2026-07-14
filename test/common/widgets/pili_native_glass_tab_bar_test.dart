import 'package:PiliPlus/common/widgets/pili_native_glass_tab_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configures the three requested tab items in order', () {
    final params = piliNativeGlassTabBarCreationParams(
      selectedIndex: 1,
      labels: const ['Home', 'Dynamics', 'Mine'],
      searchLabel: 'Search',
    );

    expect(params['selectedIndex'], 1);
    expect(params['searchLabel'], 'Search');
    expect(params['items'], const <Map<String, String>>[
      <String, String>{
        'label': 'Home',
        'symbol': 'home',
        'selectedSymbol': 'home.fill',
      },
      <String, String>{
        'label': 'Dynamics',
        'symbol': 'square.stack',
        'selectedSymbol': 'square.stack.fill',
      },
      <String, String>{
        'label': 'Mine',
        'symbol': 'person.crop.circle',
        'selectedSymbol': 'person.crop.circle.fill',
      },
    ]);
  });

  test('gates the native path to iOS', () {
    expect(
      supportsPiliNativeGlassTabBar(
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      supportsPiliNativeGlassTabBar(
        platform: TargetPlatform.iOS,
      ),
      isTrue,
    );
    expect(
      usesPiliNativeGlassTabBar(
        platform: TargetPlatform.iOS,
        isPortrait: true,
        isTablet: false,
        hasRequiredDestinations: true,
      ),
      isTrue,
    );
    expect(
      usesPiliNativeGlassTabBar(
        platform: TargetPlatform.iOS,
        isPortrait: false,
        isTablet: false,
        hasRequiredDestinations: true,
      ),
      isFalse,
    );
  });

  test(
    'forwards repeat taps and deduplicates selected-index updates',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const methodChannel = MethodChannel('pili_native_glass_tab_bar_7');
      final outgoingCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        outgoingCalls.add(call);
        return null;
      });

      final tappedIndices = <int>[];
      var searchTapCount = 0;
      final channel = PiliNativeGlassTabBarChannel(
        onTap: tappedIndices.add,
        onSearchTap: () => searchTapCount++,
        binaryMessenger: messenger,
      )..attach(7, 0);

      await channel.handleMethodCall(const MethodCall('searchTapped'));
      expect(searchTapCount, 1);
      expect(tappedIndices, isEmpty);

      await channel.setSelectedIndex(0);
      expect(outgoingCalls, isEmpty);

      for (var count = 0; count < 2; count++) {
        await channel.handleMethodCall(
          const MethodCall('valueChanged', <String, int>{'index': 1}),
        );
      }
      expect(tappedIndices, <int>[1, 1]);

      await channel.setSelectedIndex(1);
      expect(outgoingCalls, isEmpty);

      await channel.setSelectedIndex(2);
      await channel.setSelectedIndex(2);
      expect(outgoingCalls, hasLength(1));
      expect(outgoingCalls.single.method, 'setSelectedIndex');
      expect(outgoingCalls.single.arguments, <String, int>{'index': 2});

      channel.dispose();
      messenger.setMockMethodCallHandler(methodChannel, null);
    },
  );
}
