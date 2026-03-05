import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/medicine.dart';
import '../services/notification_service.dart';
import '../models/report.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';

class PharmacyProvider extends ChangeNotifier {
  Box<Medicine>? _medicineBox;
  Box<Medicine>? _trashBox;
  Box<Report>? _reportTrashBox;
  Box<Report>? _reportBox;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot>? _reportsFireSub;

  List<Medicine> _medicines = [];
  List<Report> _reports = [];
  bool _initialized = false;
  // Default threshold under which a medicine should be considered for reorder.
  int reorderThreshold = 10;

  List<Medicine> get medicines => _medicines;
  List<Report> get reports => _reports;

  /// Initialize boxes and listen for auth changes to open per-user boxes.
  Future<void> initBoxes() async {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      // Handle auth changes; run async but don't block the listener caller.
      _openBoxesForUid(user?.uid).catchError((e) {
        debugPrint('PharmacyProvider: open boxes on auth change failed: $e');
      });
    });

    // Open boxes for current user in background to avoid blocking UI creation.
    _openBoxesForUid(FirebaseAuth.instance.currentUser?.uid)
        .then((_) {
          _initialized = true;
          notifyListeners();
        })
        .catchError((e) {
          debugPrint('PharmacyProvider: open boxes failed: $e');
        });
  }

  Future<void> loadData() async {
    // called only when boxes are opened or a full refresh is required
    _medicines = _medicineBox?.values.toList() ?? [];
    _reports = _reportBox?.values.toList() ?? [];
    // after loading local data, attempt to pull any remote reports
    // (this may call loadData again if new items are appended).
    await _syncReportsFromFirestore();
    notifyListeners();
  }

  Future<void> addMedicine(Medicine medicine) async {
    await _medicineBox?.put(medicine.id, medicine);
    // keep in-memory list up to date without a full reload
    _medicines.add(medicine);
    notifyListeners();
  }

  Future<void> updateMedicine(Medicine medicine) async {
    final index = _medicines.indexWhere((m) => m.id == medicine.id);
    if (index != -1) {
      final oldMedicine = _medicines[index];
      if (oldMedicine.name != medicine.name) {
        // Update medicine name in all reports locally and remotely if possible
        for (final report in _reports) {
          if (report.medicineName == oldMedicine.name) {
            report.medicineName = medicine.name;
            await report.save();
            // propagate change to firestore if we know the remote document id
            if (report.remoteId != null && report.remoteId!.isNotEmpty) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                try {
                  await FirestoreService.update(
                    'users/$uid/reports/${report.remoteId}',
                    {'medicineName': medicine.name},
                  );
                } catch (_) {}
              }
            }
          }
        }
      }
      await medicine.save();
      // update in-memory list directly
      _medicines[index] = medicine;
      notifyListeners();
    }
  }

  Future<void> deleteMedicine(Medicine medicine) async {
    // Soft-delete: move medicine to trash box instead of permanent delete.
    if (_trashBox == null || !(_trashBox?.isOpen ?? false)) {
      final boxName = _medicineBox?.name != null
          ? '${_medicineBox!.name}_trash'
          : 'medicines_trash';
      _trashBox = await Hive.openBox<Medicine>(boxName);
    }

    // Move associated reports to a per-user reports trash box so they can
    // be restored together with the medicine.
    if (_reportTrashBox == null || !(_reportTrashBox?.isOpen ?? false)) {
      final boxName = _reportBox?.name != null
          ? '${_reportBox!.name}_trash'
          : 'reports_trash';
      _reportTrashBox = await Hive.openBox<Report>(boxName);
    }
    final reportsToMove = _reports
        .where((report) => report.medicineName == medicine.name)
        .toList();
    for (final report in reportsToMove) {
      try {
        final clone = Report(
          medicineName: report.medicineName,
          soldQty: report.soldQty,
          sellPrice: report.sellPrice,
          totalGain: report.totalGain,
          dateTime: report.dateTime,
          isRead: report.isRead,
          remoteId: report.remoteId,
        );
        await _reportTrashBox?.add(clone);
        await report.delete();
      } catch (_) {}
    }

    // Mark deletion time and move a cloned medicine to trash
    int? deletedAtMillis;
    try {
      deletedAtMillis = DateTime.now().millisecondsSinceEpoch;
      final clone = Medicine(
        id: medicine.id,
        name: medicine.name,
        totalQty: medicine.totalQty,
        buyPrice: medicine.buyPrice,
        sellPrice: medicine.sellPrice,
        imageBytes: medicine.imageBytes,
        soldQty: medicine.soldQty,
        category: medicine.category,
        barcode: medicine.barcode,
        imageUrl: medicine.imageUrl,
        cloudinaryPublicId: medicine.cloudinaryPublicId,
        lastModifiedMillis: medicine.lastModifiedMillis,
        deletedAtMillis: deletedAtMillis,
      );
      await _trashBox?.put(clone.id, clone);
    } catch (_) {}
    await medicine.delete();
    // remove from the in-memory list and notify listeners
    _medicines.removeWhere((m) => m.id == medicine.id);
    notifyListeners();
    // always ask the notification service to create trash-related alerts;
    // it will internally check both the global and trash-specific flags and
    // ignore the request if notifications are disabled.
    try {
      if (deletedAtMillis != null) {
        final deletedAt = DateTime.fromMillisecondsSinceEpoch(deletedAtMillis);
        final expireAt = deletedAt.add(Duration(days: trashRetentionDays));
        final twoDays = expireAt.subtract(const Duration(days: 2));
        final oneDay = expireAt.subtract(const Duration(days: 1));
        final finalAt = expireAt;
        await NotificationService.instance.showImmediate(
          id: medicine.id.hashCode & 0x7fffffff,
          title: 'Moved to Trash',
          body:
              '${medicine.name} moved to Trash. It will be deleted in $trashRetentionDays days.',
          payload: 'trash:${medicine.id}',
        );
        await NotificationService.instance.schedule(
          notifId: medicine.id,
          offset: 0,
          title: 'Expiring soon',
          body: '${medicine.name} will be permanently deleted in 2 days.',
          at: twoDays,
          payload: 'trash:${medicine.id}',
        );
        await NotificationService.instance.schedule(
          notifId: medicine.id,
          offset: 1,
          title: 'Expiring soon',
          body: '${medicine.name} will be permanently deleted in 1 day.',
          at: oneDay,
          payload: 'trash:${medicine.id}',
        );
        await NotificationService.instance.schedule(
          notifId: medicine.id,
          offset: 2,
          title: 'Deleted',
          body: '${medicine.name} has been permanently deleted from Trash.',
          at: finalAt,
          payload: 'trash:${medicine.id}',
        );
      }
    } catch (_) {}
  }

  /// Returns list of medicines currently in trash.
  List<Medicine> get trashedMedicines => _trashBox?.values.toList() ?? [];

  Future<int> restoreMedicineFromTrash(String id) async {
    if (_trashBox == null || !(_trashBox?.isOpen ?? false)) return 0;
    final med = _trashBox?.get(id);
    if (med == null) return 0;
    // create a fresh copy for the main medicines box
    final restored = Medicine(
      id: med.id,
      name: med.name,
      totalQty: med.totalQty,
      buyPrice: med.buyPrice,
      sellPrice: med.sellPrice,
      imageBytes: med.imageBytes,
      soldQty: med.soldQty,
      category: med.category,
      barcode: med.barcode,
      imageUrl: med.imageUrl,
      cloudinaryPublicId: med.cloudinaryPublicId,
      lastModifiedMillis: med.lastModifiedMillis,
      deletedAtMillis: null,
    );
    await _medicineBox?.put(restored.id, restored);
    await _trashBox?.delete(id);
    await loadData();
    // cancel any scheduled notifications for this medicine
    try {
      await NotificationService.instance.cancelFor(id);
    } catch (_) {}

    // Restore associated reports from the per-user reports trash box.
    try {
      if (_reportTrashBox == null || !(_reportTrashBox?.isOpen ?? false)) {
        final boxName = _reportBox?.name != null
            ? '${_reportBox!.name}_trash'
            : 'reports_trash';
        _reportTrashBox = await Hive.openBox<Report>(boxName);
      }
      final toRestore = _reportTrashBox!.values
          .where((r) => r.medicineName == restored.name)
          .toList();
      final restoredCount = toRestore.length;
      for (final r in toRestore) {
        final clone = Report(
          medicineName: r.medicineName,
          soldQty: r.soldQty,
          sellPrice: r.sellPrice,
          totalGain: r.totalGain,
          dateTime: r.dateTime,
          isRead: r.isRead,
          remoteId: r.remoteId,
        );
        await _reportBox?.add(clone);
        await r.delete();
      }
      await loadData();
      return restoredCount;
    } catch (_) {}
    return 0;
  }

  Future<void> permanentlyDeleteFromTrash(String id) async {
    if (_trashBox == null || !(_trashBox?.isOpen ?? false)) return;
    final med = _trashBox?.get(id);
    if (med == null) return;
    // If the medicine had uploaded image/cloudinary id, callers may want to delete it.
    await _trashBox?.delete(id);
    await loadData();
    // cancel scheduled notifications for permanently deleted item
    try {
      await NotificationService.instance.cancelFor(id);
    } catch (_) {}
  }

  /// Set up a realtime listener on the Firestore reports collection so that
  /// any remote additions, modifications or deletions are reflected locally.
  Future<void> _attachReportsListener(String? uid) async {
    // cancel existing subscription if any
    await _reportsFireSub?.cancel();
    _reportsFireSub = null;
    if (uid == null) return;

    final coll = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reports');
    _reportsFireSub = coll.snapshots().listen(
      (snap) async {
        bool changed = false;
        for (final change in snap.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;
          final remoteId = change.doc.id;
          switch (change.type) {
            case DocumentChangeType.added:
              if (!_reports.any((r) => r.remoteId == remoteId)) {
                final report = Report(
                  medicineName: data['medicineName'] as String? ?? '',
                  soldQty: (data['soldQty'] as num?)?.toInt() ?? 0,
                  sellPrice: (data['sellPrice'] as num?)?.toInt() ?? 0,
                  totalGain: (data['totalGain'] as num?)?.toInt() ?? 0,
                  dateTime: (data['dateTime'] is Timestamp)
                      ? (data['dateTime'] as Timestamp).toDate()
                      : DateTime.tryParse(data['dateTime']?.toString() ?? '') ??
                            DateTime.now(),
                  isRead: data['isRead'] as bool? ?? false,
                  remoteId: remoteId,
                );
                await _reportBox?.add(report);
                changed = true;
              }
              break;
            case DocumentChangeType.modified:
              Report? existing;
              try {
                existing = _reports.firstWhere((r) => r.remoteId == remoteId);
              } catch (_) {
                existing = null;
              }
              if (existing != null) {
                existing.medicineName =
                    data['medicineName'] as String? ?? existing.medicineName;
                existing.soldQty =
                    (data['soldQty'] as num?)?.toInt() ?? existing.soldQty;
                existing.sellPrice =
                    (data['sellPrice'] as num?)?.toInt() ?? existing.sellPrice;
                existing.totalGain =
                    (data['totalGain'] as num?)?.toInt() ?? existing.totalGain;
                existing.dateTime = (data['dateTime'] is Timestamp)
                    ? (data['dateTime'] as Timestamp).toDate()
                    : existing.dateTime;
                existing.isRead = data['isRead'] as bool? ?? existing.isRead;
                await existing.save();
                changed = true;
              }
              break;
            case DocumentChangeType.removed:
              Report? existing2;
              try {
                existing2 = _reports.firstWhere((r) => r.remoteId == remoteId);
              } catch (_) {
                existing2 = null;
              }
              if (existing2 != null) {
                await existing2.delete();
                changed = true;
              }
              break;
          }
        }
        if (changed) {
          await loadData();
        }
      },
      onError: (e) {
        debugPrint('PharmacyProvider: reports listener error: $e');
      },
    );
  }

  /// Number of days items are kept in trash before permanent deletion.
  int get trashRetentionDays => 7;

  /// Returns days left before permanent deletion for a trashed medicine.
  int daysLeftInTrash(Medicine med) {
    final deleted = med.deletedAtMillis;
    if (deleted == null) return trashRetentionDays;
    final deletedAt = DateTime.fromMillisecondsSinceEpoch(deleted);
    final expireAt = deletedAt.add(Duration(days: trashRetentionDays));
    final diff = expireAt.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Count of trashed items that will expire within given days (default 2 days).
  int trashedExpiringWithin({int days = 2}) {
    final now = DateTime.now();
    if (_trashBox == null || !(_trashBox?.isOpen ?? false)) return 0;
    return _trashBox!.values.where((med) {
      final deleted = med.deletedAtMillis;
      if (deleted == null) return false;
      final deletedAt = DateTime.fromMillisecondsSinceEpoch(deleted);
      final expireAt = deletedAt.add(Duration(days: trashRetentionDays));
      final diff = expireAt.difference(now).inDays;
      return diff <= days;
    }).length;
  }

  Future<void> _cleanupTrash() async {
    if (_trashBox == null || !(_trashBox?.isOpen ?? false)) return;
    final now = DateTime.now();
    final toRemove = <String>[];
    for (final med in _trashBox!.values) {
      final deleted = med.deletedAtMillis;
      if (deleted == null) continue;
      final deletedAt = DateTime.fromMillisecondsSinceEpoch(deleted);
      if (now.difference(deletedAt).inDays >= trashRetentionDays) {
        toRemove.add(med.id);
      }
    }
    for (final id in toRemove) {
      await _trashBox?.delete(id);
    }
    if (toRemove.isNotEmpty) await loadData();
  }

  /// Fetch reports that exist in Firestore but not yet in the local Hive box.
  ///
  /// This is called whenever we open the boxes for a user or explicitly when
  /// loading data. It will append any missing reports to the Hive box (with
  /// their remoteId recorded) so that subsequent local queries return a
  /// combined view. If new items are added the provider will notify listeners
  /// again so the UI can refresh.
  Future<void> _syncReportsFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final coll = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reports');
      final snap = await coll.get();
      bool addedAny = false;
      for (final doc in snap.docs) {
        final data = doc.data();
        final remoteId = doc.id;
        // skip if we already have this report by remoteId
        if (_reports.any((r) => r.remoteId == remoteId)) continue;
        final report = Report(
          medicineName: data['medicineName'] as String? ?? '',
          soldQty: (data['soldQty'] as num?)?.toInt() ?? 0,
          sellPrice: (data['sellPrice'] as num?)?.toInt() ?? 0,
          totalGain: (data['totalGain'] as num?)?.toInt() ?? 0,
          dateTime: (data['dateTime'] is Timestamp)
              ? (data['dateTime'] as Timestamp).toDate()
              : DateTime.tryParse(data['dateTime']?.toString() ?? '') ??
                    DateTime.now(),
          isRead: data['isRead'] as bool? ?? false,
          remoteId: remoteId,
        );
        await _reportBox?.add(report);
        addedAny = true;
      }
      if (addedAny) {
        await loadData();
      }
    } catch (e) {
      debugPrint('PharmacyProvider: _syncReportsFromFirestore failed: $e');
    }
  }

  /// Push a single report to Firestore and update its remoteId when the
  /// document has been created. Failures are logged but do not crash the app.
  Future<void> _syncReportToFirestore(Report report) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final map = {
        'medicineName': report.medicineName,
        'soldQty': report.soldQty,
        'sellPrice': report.sellPrice,
        'totalGain': report.totalGain,
        'dateTime': report.dateTime,
        'isRead': report.isRead ?? false,
      };
      final ref = await FirestoreService.add('users/$uid/reports', map);
      report.remoteId = ref.id;
      await report.save();
    } catch (e) {
      debugPrint('PharmacyProvider: failed to sync report to firestore: $e');
    }
  }

  Future<void> addReport(Report report) async {
    if (!_initialized) {
      await initBoxes();
    }
    await _reportBox?.add(report);
    // try to push new report to Firestore in background
    unawaited(_syncReportToFirestore(report));
    await loadData();
  }

  Future<void> clearNewReportsNotification() async {
    for (final report in _reports) {
      if (!(report.isRead ?? false)) {
        report.isRead = true;
        await report.save();
      }
    }
    await loadData();
  }

  Future<void> removeReport(Report report) async {
    // delete locally first
    await report.delete();
    // also delete from firestore if we know the remote id
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && report.remoteId != null && report.remoteId!.isNotEmpty) {
      try {
        await FirestoreService.delete('users/$uid/reports/${report.remoteId}');
      } catch (e) {
        debugPrint('PharmacyProvider: failed to delete remote report: $e');
      }
    }
    await loadData();
  }

  /// Remove all reports associated with [medicineName].
  Future<void> removeReportsForMedicine(String medicineName) async {
    final toRemove = _reports
        .where((r) => r.medicineName == medicineName)
        .toList();
    for (final r in toRemove) {
      try {
        // delete local copy
        await r.delete();
        // if we have a remoteId also remove from Firestore
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && r.remoteId != null && r.remoteId!.isNotEmpty) {
          try {
            await FirestoreService.delete('users/$uid/reports/${r.remoteId}');
          } catch (_) {}
        }
      } catch (_) {}
    }
    await loadData();
  }

  Future<void> _openBoxesForUid(String? uid) async {
    final medsName = uid == null ? 'medicines_guest' : 'medicines_$uid';
    final reportsName = uid == null ? 'reports_guest' : 'reports_$uid';

    try {
      // close existing boxes if different
      if (_medicineBox != null && _medicineBox!.isOpen) {
        await _medicineBox!.close();
      }
      if (_reportBox != null && _reportBox!.isOpen) {
        await _reportBox!.close();
      }
    } catch (e) {
      debugPrint('PharmacyProvider: error closing boxes: $e');
    }

    // cancel previous firestore listener before opening new boxes
    _reportsFireSub?.cancel();

    _medicineBox = await Hive.openBox<Medicine>(medsName);
    _reportBox = await Hive.openBox<Report>(reportsName);
    // open a per-user trash box for soft-deleted medicines
    final trashName = uid == null
        ? 'medicines_trash_guest'
        : 'medicines_trash_$uid';
    _trashBox = await Hive.openBox<Medicine>(trashName);
    await _cleanupTrash();
    await loadData();
    // attempt to pull any remote reports and merge into local storage
    await _syncReportsFromFirestore();
    // start listening to remote report changes for this user
    await _attachReportsListener(uid);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _reportsFireSub?.cancel();
    try {
      _medicineBox?.close();
      _reportBox?.close();
      _trashBox?.close();
    } catch (_) {}
    super.dispose();
  }

  List<Medicine> getOutOfStockMedicines() {
    return _medicines.where((medicine) => medicine.remainingQty == 0).toList();
  }

  int get outOfStockCount =>
      _medicines.where((medicine) => medicine.remainingQty == 0).length;

  int get newReportsCount => _reports.where((r) => !(r.isRead ?? false)).length;

  List<Medicine> searchMedicines(String query) {
    if (query.isEmpty) return _medicines;
    return _medicines
        .where(
          (medicine) =>
              medicine.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }

  Medicine? findMedicineByBarcode(String barcode) {
    try {
      return _medicines.firstWhere((medicine) => medicine.barcode == barcode);
    } catch (e) {
      return null;
    }
  }

  /// utility that returns all medicine names mentioned in [text].
  ///
  /// The check is case‑insensitive and looks for the medicine name as a
  /// substring; callers may want to guard against false positives if they
  /// have very short names.
  List<String> extractMedicineNames(String text) {
    final lower = text.toLowerCase();
    final found = <String>{};
    for (final med in _medicines) {
      final nameLower = med.name.toLowerCase();
      if (lower.contains(nameLower)) {
        found.add(med.name);
      }
    }
    return found.toList();
  }

  /// Returns the most recent sale datetime for [medicineName], or null.
  DateTime? lastSaleFor(String medicineName) {
    final reportsFor = _reports.where((r) => r.medicineName == medicineName);
    if (reportsFor.isEmpty) return null;
    reportsFor.toList().sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return reportsFor.first.dateTime;
  }

  /// Heuristic: should reorder when remainingQty <= threshold.
  bool shouldReorder(String medicineName, {int? threshold}) {
    threshold ??= reorderThreshold;
    try {
      final med = _medicines.firstWhere((m) => m.name == medicineName);
      return med.remainingQty <= threshold;
    } catch (_) {
      return false;
    }
  }

  // simple Levenshtein distance for fuzzy suggestions
  int _levenshtein(String a, String b) {
    final la = a.length;
    final lb = b.length;
    if (la == 0) return lb;
    if (lb == 0) return la;
    final v = List.generate(la + 1, (_) => List<int>.filled(lb + 1, 0));
    for (var i = 0; i <= la; i++) {
      v[i][0] = i;
    }
    for (var j = 0; j <= lb; j++) {
      v[0][j] = j;
    }
    for (var i = 1; i <= la; i++) {
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        v[i][j] = [
          v[i - 1][j] + 1,
          v[i][j - 1] + 1,
          v[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return v[la][lb];
  }

  /// Suggest closest medicine names for an unknown query token.
  List<String> suggestClosestNames(String token, {int max = 5}) {
    final lower = token.toLowerCase();
    final scores = <String, int>{};
    for (final m in _medicines) {
      final name = m.name;
      final dist = _levenshtein(lower, name.toLowerCase());
      scores[name] = dist;
    }
    final sorted = scores.keys.toList()
      ..sort((a, b) => scores[a]!.compareTo(scores[b]!));
    return sorted.take(max).toList();
  }

  int soldQtyFor(String medicineName, {DateTime? from, DateTime? to}) {
    var reportsForMed = _reports.where((r) => r.medicineName == medicineName);
    if (from != null) {
      reportsForMed = reportsForMed.where((r) => !r.dateTime.isBefore(from));
    }
    if (to != null) {
      reportsForMed = reportsForMed.where((r) => r.dateTime.isBefore(to));
    }
    return reportsForMed.fold(0, (acc, r) => acc + r.soldQty);
  }

  int profitFor(String medicineName, {DateTime? from, DateTime? to}) {
    var reportsForMed = _reports.where((r) => r.medicineName == medicineName);
    if (from != null) {
      reportsForMed = reportsForMed.where((r) => !r.dateTime.isBefore(from));
    }
    if (to != null) {
      reportsForMed = reportsForMed.where((r) => r.dateTime.isBefore(to));
    }
    return reportsForMed.fold(0, (acc, r) => acc + r.totalGain);
  }

  DateTimeRange? _extractDateRangeFromQuery(String query) {
    final lower = query.toLowerCase();
    final now = DateTime.now();
    if (lower.contains('today')) {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      return DateTimeRange(start: start, end: end);
    } else if (lower.contains('yesterday')) {
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));
      final end = start.add(const Duration(days: 1));
      return DateTimeRange(start: start, end: end);
    }
    // this week / last week
    if (lower.contains('this week')) {
      final start = DateTime.now().subtract(Duration(days: now.weekday - 1));
      final s = DateTime(start.year, start.month, start.day);
      final e = s.add(const Duration(days: 7));
      return DateTimeRange(start: s, end: e);
    }
    if (lower.contains('last week')) {
      final start = DateTime.now().subtract(
        Duration(days: now.weekday - 1 + 7),
      );
      final s = DateTime(start.year, start.month, start.day);
      final e = s.add(const Duration(days: 7));
      return DateTimeRange(start: s, end: e);
    }
    // this month / last month
    if (lower.contains('this month')) {
      final s = DateTime(now.year, now.month, 1);
      final e = DateTime(now.year, now.month + 1, 1);
      return DateTimeRange(start: s, end: e);
    }
    if (lower.contains('last month')) {
      final ym = DateTime(now.year, now.month - 1, 1);
      final s = DateTime(ym.year, ym.month, 1);
      final e = DateTime(ym.year, ym.month + 1, 1);
      return DateTimeRange(start: s, end: e);
    }
    return null;
  }

  String _formatRange(DateTimeRange range) {
    if (range.duration == const Duration(days: 1)) {
      final day = range.start;
      return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    }
    return '${range.start} - ${range.end}';
  }

  /// Builds a simple text summary for one or more medicine names.  The
  /// optional [query] is used to detect time‑related words such as
  /// "today"/"yesterday" and include corresponding sold/profit figures.
  String statusTextFor(List<String> names, {String? query}) {
    final buf = StringBuffer();
    final range = query != null ? _extractDateRangeFromQuery(query) : null;
    for (var name in names) {
      final med = _medicines.firstWhere((m) => m.name == name);
      buf.writeln(
        'Medicine: ${med.name}${med.barcode != null ? ' (barcode: ${med.barcode})' : ''}',
      );
      buf.writeln('Remaining: ${med.remainingQty}');

      final totalSold = soldQtyFor(name);
      buf.writeln('Total sold (all time): $totalSold');
      if (range != null) {
        final soldRange = soldQtyFor(name, from: range.start, to: range.end);
        buf.writeln('Sold ${_formatRange(range)}: $soldRange');
      }

      final profit = profitFor(name, from: range?.start, to: range?.end);
      buf.writeln(
        'Profit${range == null ? ' (all time)' : ' ${_formatRange(range)}'}: \$$profit',
      );

      final lastSale = lastSaleFor(name);
      buf.writeln(
        'Last sold: ${lastSale != null ? lastSale.toIso8601String() : 'Never'}',
      );

      // expiry not stored in model; report unknown when absent
      buf.writeln('Expiry: Unknown');

      final reorder = shouldReorder(name) ? 'Yes' : 'No';
      buf.writeln('Reorder recommended: $reorder');
      buf.writeln('');
    }
    return buf.toString();
  }

  /// Central entry point used by the chat screen.  It tries to detect a
  /// barcode or medicine name(s) in [input] and returns a textual answer
  /// containing quantities, sales and profit.  If no known medicine is
  /// mentioned the method returns a helpful fallback message.
  Future<String> chatReply(String input) async {
    if (!_initialized) await initBoxes();
    final cleaned = input.trim();
    if (cleaned.isEmpty) return '';

    // barcode check (exact match)
    final barcodeMed = findMedicineByBarcode(cleaned);
    if (barcodeMed != null) {
      return statusTextFor([barcodeMed.name]);
    }

    final names = extractMedicineNames(input);
    if (names.isNotEmpty) {
      return statusTextFor(names, query: input);
    }

    // If nothing matched, provide sensible suggestions based on fuzzy
    // matching of the whole input or its tokens.
    final tokens = cleaned
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final suggestions = <String>{};
    if (tokens.isNotEmpty) {
      for (final t in tokens) {
        final s = suggestClosestNames(t, max: 3);
        suggestions.addAll(s);
      }
    } else {
      suggestions.addAll(suggestClosestNames(cleaned, max: 5));
    }

    if (suggestions.isNotEmpty) {
      final list = suggestions.take(5).join(', ');
      return 'No matches for "$cleaned". Did you mean: $list?';
    }

    return 'Sorry, I could not find any medicine mentioned in your message. Please enter a valid medicine name or scan its barcode.';
  }

  /// Build a safe prompt and get AI recommendation, validating results.
  Future<String> recommendFromSymptoms(String symptoms) async {
    if (!_initialized) await initBoxes();

    // Build a constrained prompt listing available medicines and safety rules.
    final medicineList = _medicines.map((m) => m.name).toList();
    final buffer = StringBuffer();
    buffer.writeln('You are a pharmacy assistant.');
    buffer.writeln('Available medicines: ${medicineList.join(", ")}');
    buffer.writeln('Rules:');
    buffer.writeln('- Recommend only from the Available medicines list.');
    buffer.writeln('- Do not diagnose conditions.');
    buffer.writeln('- Do not give child dosages.');
    buffer.writeln(
      '- If symptoms are severe (chest pain, difficulty breathing, fainting), advise to seek emergency care.',
    );
    buffer.writeln('User symptoms: $symptoms');

    final ai = AIService();
    final resp = await ai.getAIRecommendation(buffer.toString());

    final lower = resp.toLowerCase();
    // If AI advises seeing a doctor / emergency, allow that through.
    if (lower.contains('doctor') ||
        lower.contains('emergency') ||
        lower.contains('seek medical') ||
        lower.contains('call 911') ||
        lower.contains('urgent')) {
      return resp;
    }

    // Validate that at least one recommended medicine exists in Hive.
    final knownNames = _medicines.map((m) => m.name.toLowerCase()).toList();
    final mentionedKnown = knownNames
        .where((name) => lower.contains(name))
        .toList();

    if (mentionedKnown.isEmpty) {
      return 'I’m not confident recommending a medicine. Please consult a pharmacist or doctor.';
    }

    return resp;
  }
}
