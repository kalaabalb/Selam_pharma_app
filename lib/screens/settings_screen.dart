// Appearance selection uses RadioGroup (introduced in Flutter 3.32+).
// Removing deprecated parameter warnings by using the new API directly.
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/local_auth.dart';
import '../services/notification_service.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/ui_helpers.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Local state for toggles (no persistence in this minimal scaffold)
  bool _notificationsEnabled = true;
  bool _badgeEnabled = true;
  bool _biometricEnabled = false;
  bool _trashNotificationsEnabled = true;

  Box? _settingsBox;

  /// Export all available reports to a CSV file in application documents.
  Future<void> _exportAllData() async {
    try {
      final prov = Provider.of<PharmacyProvider>(context, listen: false);
      final reports = prov.reports;
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'export_all_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
      final file = File('${directory.path}/$fileName');

      final csv = StringBuffer();
      csv.writeln('Date,Medicine,Quantity,Total Gain');
      for (final r in reports) {
        csv.writeln(
          '${DateFormat('yyyy-MM-dd HH:mm').format(r.dateTime)},${r.medicineName},${r.soldQty},${r.totalGain}',
        );
      }
      await file.writeAsString(csv.toString());
      if (mounted) {
        showAppSnackBar(context, 'Data exported to ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Export failed: $e', error: true);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      _settingsBox = Hive.box('settings');
      // load persisted values (use defaults when missing)
      _notificationsEnabled =
          _settingsBox?.get('notifications_enabled', defaultValue: true) ??
          true;
      _badgeEnabled =
          _settingsBox?.get('show_badges', defaultValue: true) ?? true;
      _biometricEnabled =
          _settingsBox?.get('biometric_enabled', defaultValue: false) ?? false;
      _trashNotificationsEnabled =
          _settingsBox?.get(
            'trash_notifications_enabled',
            defaultValue: true,
          ) ??
          true;
    } catch (_) {
      // if Hive fails for any reason, fall back to defaults
      _notificationsEnabled = true;
      _badgeEnabled = true;
      _biometricEnabled = false;
      _trashNotificationsEnabled = true;
    }

    // make sure NotificationService respects the current setting even if
    // this screen isn't shown right away.  We don't await here because
    // initState can't be async; any failures are silently ignored.
    NotificationService.instance
        .setNotificationsEnabled(_notificationsEnabled)
        .then((_) {
          if (_notificationsEnabled && _trashNotificationsEnabled) {
            _rescheduleTrashNotifications();
          }
        })
        .catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // reschedule trash notifications if enabled
    if (_trashNotificationsEnabled) {
      _rescheduleTrashNotifications();
    }
  }

  Future<void> _rescheduleTrashNotifications() async {
    // nothing to do if either master notifications or trash-specific setting
    // are disabled; this method may be called in a few places so guard up
    // front to avoid unnecessary work.
    if (!(_notificationsEnabled && _trashNotificationsEnabled)) return;
    try {
      final prov = Provider.of<PharmacyProvider>(context, listen: false);
      for (final med in prov.trashedMedicines) {
        final deletedAt = med.deletedAtMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(med.deletedAtMillis!)
            : DateTime.now();
        final expireAt = deletedAt.add(Duration(days: prov.trashRetentionDays));
        final twoDays = expireAt.subtract(const Duration(days: 2));
        final oneDay = expireAt.subtract(const Duration(days: 1));
        final finalAt = expireAt;
        // immediate informative alert in case this item was trashed while
        // notifications were disabled; users should at least see the moved
        // message when they turn the feature back on.
        await NotificationService.instance.showImmediate(
          id: med.id.hashCode & 0x7fffffff,
          title: 'Moved to Trash',
          body:
              '${med.name} is in Trash. It will be deleted in ${prov.trashRetentionDays} days.',
          payload: 'trash:${med.id}',
        );
        await NotificationService.instance.schedule(
          notifId: med.id,
          offset: 0,
          title: 'Expiring soon',
          body: '${med.name} will be permanently deleted in 2 days.',
          at: twoDays,
          payload: 'trash:${med.id}',
        );
        await NotificationService.instance.schedule(
          notifId: med.id,
          offset: 1,
          title: 'Expiring soon',
          body: '${med.name} will be permanently deleted in 1 day.',
          at: oneDay,
          payload: 'trash:${med.id}',
        );
        await NotificationService.instance.schedule(
          notifId: med.id,
          offset: 2,
          title: 'Deleted',
          body: '${med.name} has been permanently deleted from Trash.',
          at: finalAt,
          payload: 'trash:${med.id}',
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // smaller text styles for compact layout
    final headerStyle = GoogleFonts.montserrat(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    final titleStyle = GoogleFonts.montserrat(fontSize: 12);
    final subtitleStyle = GoogleFonts.montserrat(fontSize: 10);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          children: [
            const SizedBox(height: 8),

            // Appearance
            Text('Appearance', style: headerStyle),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Only allow explicit Light or Dark selection (no System option)
                  Builder(
                    builder: (context) {
                      final themeProvider = context.watch<ThemeProvider>();
                      final groupValue = themeProvider.isDarkMode
                          ? 'dark'
                          : 'light';
                      return RadioGroup<String>(
                        groupValue: groupValue,
                        onChanged: (v) {
                          if (v == null) return;
                          context.read<ThemeProvider>().setDark(v == 'dark');
                        },
                        child: Column(
                          children: [
                            RadioListTile<String>(
                              value: 'light',
                              title: Text('Light', style: titleStyle),
                            ),
                            RadioListTile<String>(
                              value: 'dark',
                              title: Text('Dark', style: titleStyle),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Notifications
            Text('Notifications', style: headerStyle),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _notificationsEnabled,
                    onChanged: (v) async {
                      setState(() => _notificationsEnabled = v);
                      try {
                        await NotificationService.instance
                            .setNotificationsEnabled(v);
                      } catch (_) {}
                    },
                    title: Text('Enable notifications', style: titleStyle),
                    subtitle: Text(
                      'Show notifications and badges',
                      style: subtitleStyle,
                    ),
                  ),
                  SwitchListTile(
                    value: _badgeEnabled,
                    onChanged: (v) async {
                      setState(() => _badgeEnabled = v);
                      try {
                        await _settingsBox?.put('show_badges', v);
                      } catch (_) {}
                    },
                    title: Text('Show badges', style: titleStyle),
                  ),
                  SwitchListTile(
                    value: _trashNotificationsEnabled,
                    onChanged: (v) async {
                      setState(() => _trashNotificationsEnabled = v);
                      // persist
                      try {
                        _settingsBox?.put('trash_notifications_enabled', v);
                      } catch (_) {}
                      final prov = Provider.of<PharmacyProvider>(
                        context,
                        listen: false,
                      );
                      if (!v) {
                        // cancel any existing alerts when the user disables the
                        // feature; the global toggle is irrelevant here since
                        // NotificationService.cancelAll() would have already
                        // removed them when notifications were turned off.
                        for (final med in prov.trashedMedicines) {
                          await NotificationService.instance.cancelFor(med.id);
                        }
                      } else {
                        // schedule reminders for all trashed medicines; the
                        // service will silently ignore them if the global
                        // master switch is off.
                        if (_notificationsEnabled) {
                          _rescheduleTrashNotifications();
                        }
                      }
                    },
                    title: Text(
                      'Trash expiry notifications',
                      style: titleStyle,
                    ),
                    subtitle: Text(
                      'Notify when trashed items are about to be permanently deleted',
                      style: subtitleStyle,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Account / Security
            Text('Privacy & Security', style: headerStyle),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _biometricEnabled,
                    onChanged: (v) async {
                      setState(() => _biometricEnabled = v);
                      try {
                        await _settingsBox?.put('biometric_enabled', v);
                      } catch (_) {}
                    },
                    title: Text('Use biometric unlock', style: titleStyle),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Data & Storage
            Text('Data & Storage', style: headerStyle),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text('Export data', style: titleStyle),
                    subtitle: Text('Export CSV / JSON', style: subtitleStyle),
                    onTap: () async {
                      await _exportAllData();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text('Clear cache', style: titleStyle),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Clear cache?', style: headerStyle),
                          content: Text(
                            'This will remove temporary data, including any saved login accounts used for offline or biometric authentication. Continue?',
                            style: titleStyle,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: TextButton.styleFrom(
                                textStyle: titleStyle,
                              ),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: TextButton.styleFrom(
                                textStyle: titleStyle,
                              ),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      );
                      if (!mounted || ok != true) return;
                      try {
                        // Clear chat cache
                        final chatBox = Hive.box('chat');
                        await chatBox.clear();
                        // Clear local auth accounts
                        await LocalAuth.clearAll();
                        showAppSnackBar(context, 'Cache cleared');
                      } catch (e) {
                        showAppSnackBar(
                          context,
                          'Failed to clear cache: $e',
                          error: true,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Account actions
            Text('Account', style: headerStyle),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout_outlined),
                    title: Text('Logout', style: titleStyle),
                    subtitle: Text(
                      'Sign out of this account',
                      style: subtitleStyle,
                    ),
                    onTap: () async {
                      try {
                        await AuthService().signOut();
                        if (!mounted) return;
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/login', (route) => false);
                      } catch (e) {
                        if (!mounted) return;
                        showAppSnackBar(
                          context,
                          'Sign out failed: $e',
                          error: true,
                        );
                      }
                    },
                  ),

                  ListTile(
                    leading: const Icon(Icons.person_remove_outlined),
                    title: Text('Delete account', style: titleStyle),
                    subtitle: Text(
                      'Permanently delete account and data',
                      style: subtitleStyle,
                    ),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Delete account?', style: headerStyle),
                          content: Text(
                            'This will permanently delete your account and associated cloud data. This cannot be undone. Continue?',
                            style: titleStyle,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: TextButton.styleFrom(
                                textStyle: titleStyle,
                              ),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: TextButton.styleFrom(
                                textStyle: titleStyle,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;

                      // show progress
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) =>
                            const Center(child: CircularProgressIndicator()),
                      );

                      try {
                        await AuthService().deleteAccount();
                        // also clear any cached local credentials since the
                        // account is gone
                        try {
                          await LocalAuth.clearAll();
                        } catch (_) {}
                        if (!mounted) return;
                        Navigator.of(context).pop(); // pop progress
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/login', (route) => false);
                      } on Exception catch (e) {
                        if (!mounted) return;
                        Navigator.of(context).pop(); // pop progress
                        final msg = e.toString();
                        showAppSnackBar(
                          context,
                          'Delete failed: $msg',
                          error: true,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

            // About
            Text('About', style: headerStyle),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text('About this app', style: titleStyle),
                    subtitle: Text('Version 1.0.0', style: subtitleStyle),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
