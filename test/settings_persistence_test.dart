import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'dart:io';

import 'package:shmed/services/notification_service.dart';
import 'package:shmed/services/auth_service.dart';

void main() {
  setUpAll(() async {
    // ensure a temporary directory for Hive during tests
    final dir = Directory.systemTemp.createTempSync('hive_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.box('settings').clear();
    await Hive.box('settings').close();
  });

  test('notifications and badge preferences persist', () async {
    final box = Hive.box('settings');
    expect(box.get('notifications_enabled', defaultValue: true), true);
    expect(box.get('show_badges', defaultValue: true), true);

    await box.put('notifications_enabled', false);
    await box.put('show_badges', false);

    expect(box.get('notifications_enabled'), false);
    expect(box.get('show_badges'), false);
  });

  test('NotificationService.setNotificationsEnabled updates box', () async {
    final box = Hive.box('settings');
    // start with true
    await box.put('notifications_enabled', true);
    expect(box.get('notifications_enabled'), true);

    await NotificationService.instance.setNotificationsEnabled(false);
    expect(box.get('notifications_enabled'), false);

    // turning back on
    await NotificationService.instance.setNotificationsEnabled(true);
    expect(box.get('notifications_enabled'), true);
  });

  test('trash payloads are disabled when trash setting is off', () async {
    final box = Hive.box('settings');
    // ensure global notifications are on so only trash toggle matters
    await box.put('notifications_enabled', true);
    await box.put('trash_notifications_enabled', false);

    expect(NotificationService.instance.areNotificationsAllowed(), true);
    expect(
      NotificationService.instance.areNotificationsAllowed(
        payload: 'trash:foo',
        isScheduled: true,
      ),
      false,
    );

    // turn trash back on
    await box.put('trash_notifications_enabled', true);
    expect(
      NotificationService.instance.areNotificationsAllowed(
        payload: 'trash:foo',
      ),
      true,
    );
  });

  test('applyDefaultSettingsIfMissing only adds missing entries', () async {
    final box = Hive.box('settings');

    // start with an empty box
    await box.clear();

    // empty -> all defaults populated
    await AuthService.applyDefaultSettingsIfMissing();
    expect(box.get('notifications_enabled'), true);
    expect(box.get('show_badges'), true);
    expect(box.get('trash_notifications_enabled'), true);
    expect(box.get('biometric_enabled'), false);

    // change a couple of values, call again; existing keys should not be
    // overwritten.
    await box.put('notifications_enabled', false);
    await box.put('biometric_enabled', true);
    await AuthService.applyDefaultSettingsIfMissing();
    expect(box.get('notifications_enabled'), false);
    expect(box.get('biometric_enabled'), true);
  });

  test('initializeSettingsForNewAccount overwrites prior values', () async {
    final box = Hive.box('settings');
    await box.clear();

    // simulate an earlier user who turned things off
    await box.put('notifications_enabled', false);
    await box.put('show_badges', false);
    await box.put('trash_notifications_enabled', false);
    await box.put('biometric_enabled', true);

    await AuthService.initializeSettingsForNewAccount();
    expect(box.get('notifications_enabled'), true);
    expect(box.get('show_badges'), true);
    expect(box.get('trash_notifications_enabled'), true);
    expect(box.get('biometric_enabled'), false);
  });
}
