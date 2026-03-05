import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shmed/screens/login_screen.dart';

void main() {
  Directory? tempDir;

  setUpAll(() async {
    // initialize Hive in an isolated temporary directory so parallel
    // test runs (or previous runs) don't leave a locked file behind.
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir!.path);
  });

  tearDownAll(() async {
    // close and delete any opened boxes and remove the temp directory
    await Hive.close();
    if (tempDir != null && await tempDir!.exists()) {
      await tempDir!.delete(recursive: true);
    }
  });

  setUp(() async {
    // ensure boxes are clean before each test
    final settings = await Hive.openBox('settings');
    await settings.clear();
    final accounts = await Hive.openBox('accounts');
    await accounts.clear();
  });

  tearDown(() async {
    // close boxes after each test
    await Hive.box('settings').close();
    await Hive.box('accounts').close();
  });

  testWidgets('biometric icon hidden when no stored account', (
    WidgetTester tester,
  ) async {
    final settings = await Hive.openBox('settings');
    await settings.put('biometric_enabled', true);

    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fingerprint), findsNothing);
  });

  testWidgets('biometric button appears when account exists', (
    WidgetTester tester,
  ) async {
    final settings = await Hive.openBox('settings');
    await settings.put('biometric_enabled', true);
    final accounts = await Hive.openBox('accounts');
    await accounts.put('foo@example.com', {'email': 'foo@example.com'});

    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
  });
}
