import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/features/home/presentation/screens/nearby_experiments_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('locallink/wifi_direct_transport');
  final calls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NearbyExperiments.instance.resetForTest();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('5.8 strict mode', () {
    test('off by default, saved, and sent to the phone side', () async {
      final x = NearbyExperiments.instance;
      await x.load();
      expect(x.strictLinkCheck, isFalse);
      expect(calls.last.method, 'setStrictLinkCheck');
      expect(calls.last.arguments, {'on': false});

      await x.setStrictLinkCheck(true);
      expect(calls.last.arguments, {'on': true});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(NearbyExperiments.strictLinkCheckKey), isTrue);

      x.resetForTest();
      calls.clear();
      await x.load();
      expect(x.strictLinkCheck, isTrue);
      // The saved value is pushed again on start.
      expect(calls.single.arguments, {'on': true});
    });

    testWidgets('turning it on asks first; Cancel keeps it off',
        (tester) async {
      final x = NearbyExperiments.instance;
      await tester.pumpWidget(
          MaterialApp(home: NearbyExperimentsScreen(experiments: x)));
      await tester.scrollUntilVisible(
          find.byKey(const Key('nearby_strict_link_check')), 200);
      expect(find.text('Only checked contacts (strict mode)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nearby_strict_link_check')));
      await tester.pumpAndSettle();
      expect(find.text('Turn on strict mode?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(x.strictLinkCheck, isFalse);

      await tester.tap(find.byKey(const Key('nearby_strict_link_check')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Turn on'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(x.strictLinkCheck, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
