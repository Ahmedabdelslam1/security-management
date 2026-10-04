// حالة التطبيق العامة — بيانات bootstrap + الجلسة
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'models.dart';

class App extends ChangeNotifier {
  static final App I = App._();
  App._();

  BootData? data;
  bool loading = false;

  AppUser? get user => data?.user;
  bool get ready => data != null;

  List<Worker> get workers => data?.workers ?? [];
  List<AttRec> get att => data?.att ?? [];
  List<String> get locs => data?.locs ?? [];

  Worker worker(String id) => workers.firstWhere((w) => w.id == id, orElse: () => Worker(id: id, name: '؟', card: '', phone: '', wage: 0, hours: 8, lastSet: '', hasCard: false, hasPhoto: false));

  Future<void> bootstrap({bool silent = false}) async {
    if (!silent) _setLoading(true);
    try {
      final j = await Api.auth('bootstrap');
      data = BootData.fromJson(j as Map);
      notifyListeners();
    } finally {
      if (!silent) _setLoading(false);
    }
  }

  Future<void> logout() async {
    try { await Api.auth('logout'); } catch (_) {}
    await Api.clear();
    data = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    loading = v;
    notifyListeners();
  }

  void toast() => notifyListeners(); // لإعادة رسم بعد تعديلات محلية
}
