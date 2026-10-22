// حالة التطبيق العامة — بيانات bootstrap + الجلسة
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'store.dart';
import 'api.dart';
import 'models.dart';

class App extends ChangeNotifier {
  static final App I = App._();
  App._();

  BootData? data;
  String attLoc = ''; // فلتر مكان الحضور عند الفتح من الرئيسية
  bool loading = false;

  String bootError = ''; // آخر خطأ في تحميل البيانات (للعرض بدل الدائرة الدائمة)
  int srvVer = 0; // إصدار سكربت Google (0 = غير معروف بعد، 4+ يدعم نصف يوم/ساعات)
  AppUser? get user => data?.user;
  bool get ready => data != null;

  List<Worker> get workers => data?.workers ?? [];
  List<AttRec> get att => data?.att ?? [];
  List<String> get locs => data?.locs ?? [];
  /// كل أماكن الحضور: المسجلة سابقًا + الثابتة للعاملين
  List<String> get allLocs => <String>{...locs, ...workers.map((w) => w.loc).where((l) => l.isNotEmpty)}.toList();

  /// اليوم داخل فترة تسوية تمت: مغلق لكل الأسماء
  List<List<String>> periodsFor(String date) => [
        for (final p in data?.periods ?? const <List<String>>[])
          if ((p[0].isEmpty ? '0000-00-00' : p[0]).compareTo(date) <= 0 && date.compareTo(p[1]) <= 0) p
      ];

  bool get _admin => data?.user.isAdmin ?? false;
  /// يوم داخل فترة تسوية (بتاريخ بداية): مغلق، والأدمن وحده يفتحها
  bool periodLocked(String date) => periodsFor(date).any((p) => p[3] == '1' && !(_admin && p[2] == '1'));

  /// الأدمن فتح تسوية تغطي هذا اليوم
  bool dayOpen(String date) => _admin && (periodsFor(date).any((p) => p[2] == '1') || (data?.openDays ?? const []).contains(date));

  /// بداية الفترة الافتراضية للتسوية والتقارير: اليوم التالي لآخر تسوية (وإلا أول الشهر)، بحد أقصى اليوم
  DateTime startDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var mx = '';
    for (final p in data?.periods ?? const <List<String>>[]) {
      if (p[1].isNotEmpty && p[1].compareTo(mx) > 0) mx = p[1];
    }
    if (mx.isEmpty) return DateTime(now.year, now.month, 1);
    final d = DateTime.tryParse(mx);
    if (d == null) return DateTime(now.year, now.month, 1);
    final n = DateTime(d.year, d.month, d.day).add(const Duration(days: 1));
    return n.isAfter(today) ? today : n;
  }

  bool dayHasSettled(String date) => periodsFor(date).isNotEmpty || att.any((r) => r.date == date && r.settleId.isNotEmpty);

  Worker worker(String id) => workers.firstWhere((w) => w.id == id, orElse: () => Worker(id: id, name: '؟', card: '', phone: '', wage: 0, hours: 8, lastSet: '', hasCard: false, hasPhoto: false));

  bool sessionExpired = false;
  static const _kCache = 'boot_cache_v1';

  /// تحميل آخر بيانات محفوظة فورًا (فتح سريع بدون انتظار السيرفر)
  Future<bool> loadCache() async {
    try {
      final s = await Store.getString(_kCache);
      if (s == null || s.isEmpty) return false;
      data = BootData.fromJson(jsonDecode(s) as Map);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCache() async {
    try { await Store.remove(_kCache); } catch (_) {}
  }

  void _saveCache(Object j) {
    Store.setString(_kCache, jsonEncode(j)).catchError((_) {});
  }

  /// هل السيرفر لا يدعم نصف يوم/ساعات والحفظ الجزئي؟ (PHP أو سكربت Google قديم)
  Future<bool> legacySrv() async {
    if (await Api.isPhp()) return true;
    if (srvVer == 0) {
      try {
        srvVer = int.tryParse('${await Api.auth('srvVer')}') ?? 0;
      } on ApiException catch (e) {
        if (e.message.contains('غير معروف')) srvVer = 1;
      } catch (_) {}
    }
    return srvVer > 0 && srvVer < 4;
  }

  Future<void> bootstrap({bool silent = false}) async {
    if (!silent) _setLoading(true);
    try {
      final j = await Api.auth('bootstrap');
      data = BootData.fromJson(j as Map);
      final rv = (j as Map)['rev'];
      if (rv != null) _rev = rv.toString(); // نفس الطلب يرجع رقم التعديل: لا سحب مكرر
      bootError = '';
      _saveCache(j);
      notifyListeners();
    } catch (e) {
      bootError = '$e';
      if (e is SessionExpired) sessionExpired = true;
      rethrow;
    } finally {
      if (!silent) _setLoading(false);
    }
  }

  String? _rev;
  /// مزامنة خفيفة: تسأل السيرفر عن رقم التعديل فقط، وتسحب البيانات كاملة إذا تغيّر
  Future<void> syncIfChanged() async {
    final v = (await Api.auth('rev')).toString();
    if (_rev == v) return;
    _rev = v;
    await bootstrap(silent: true);
  }

  /// الحضور الحي للمتابعة: المنصة (أندرويد) والشاشة المفتوحة الآن؛ opened=true يسجّل فتح الشاشة
  Future<void> presence(String page, {bool opened = false}) async {
    try {
      if (Api.myIp.isEmpty) Api.fetchIp();
      await Api.auth('presence', ['android', page, opened, Api.myIp]);
    } catch (_) {}
  }

  Future<void> logout() async {
    try { await Api.auth('logout').timeout(const Duration(seconds: 5)); } catch (_) {}
    await Api.clear();
    await clearCache();
    sessionExpired = false;
    bootError = '';
    data = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    loading = v;
    notifyListeners();
  }

  // تحديث قائمة المستخدمين بعد أي تعديل إداري (السيرفر يرجع القائمة الجديدة)
  void updateUsers(List<AppUser> us) {
    if (data != null) {
      data = BootData(user: data!.user, workers: data!.workers, att: data!.att, locs: data!.locs, users: us, periods: data!.periods, openDays: data!.openDays);
      notifyListeners();
    }
  }

  void toast() => notifyListeners(); // لإعادة رسم بعد تعديلات محلية
}
