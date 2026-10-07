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

  String? _rev;
  /// مزامنة خفيفة: تسأل السيرفر عن رقم التعديل فقط، وتسحب البيانات كاملة إذا تغيّر
  Future<void> syncIfChanged() async {
    final v = (await Api.auth('rev')).toString();
    if (_rev == v) return;
    _rev = v;
    await bootstrap(silent: true);
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

  // تحديث قائمة المستخدمين بعد أي تعديل إداري (السيرفر يرجع القائمة الجديدة)
  void updateUsers(List<AppUser> us) {
    if (data != null) {
      data = BootData(user: data!.user, workers: data!.workers, att: data!.att, locs: data!.locs, users: us);
      notifyListeners();
    }
  }

  void toast() => notifyListeners(); // لإعادة رسم بعد تعديلات محلية
}
