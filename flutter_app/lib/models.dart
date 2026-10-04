// موديلات البيانات — مطابقة لمخرجات Code.gs
class AppUser {
  final String name;
  final String username;
  final String role;
  final String status;
  final Map<String, dynamic> perms;
  AppUser({required this.name, required this.username, required this.role, required this.status, required this.perms});
  bool get isAdmin => role == 'admin';
  bool can(String p) => isAdmin || (perms[p] == 1 || perms[p] == true);
  factory AppUser.fromJson(Map j) => AppUser(
        name: j['name'] ?? '',
        username: j['username'] ?? '',
        role: j['role'] ?? '',
        status: j['status'] ?? '',
        perms: (j['perms'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

class Worker {
  final String id;
  final String name;
  final String card;
  final String phone;
  final double wage;
  final double hours;
  final String lastSet;
  final bool hasCard;
  final bool hasPhoto;
  Worker({required this.id, required this.name, required this.card, required this.phone, required this.wage, required this.hours, required this.lastSet, required this.hasCard, required this.hasPhoto});
  factory Worker.fromJson(Map j) => Worker(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        card: j['card'] ?? '',
        phone: j['phone'] ?? '',
        wage: (j['wage'] ?? 0).toDouble(),
        hours: (j['hours'] ?? 8).toDouble(),
        lastSet: j['lastSet'] ?? '',
        hasCard: j['hasCard'] == true,
        hasPhoto: j['hasPhoto'] == true,
      );
}

class AttRec {
  final String date;
  final String wid;
  final String name;
  String status;
  String loc;
  final double wage;
  double xh;
  String notes;
  final String settleId;
  final double paidAmt;
  AttRec({required this.date, required this.wid, required this.name, required this.status, required this.loc, required this.wage, required this.xh, required this.notes, this.settleId = '', this.paidAmt = 0});
  bool get counts => status != '--' && loc.trim().isNotEmpty;
  factory AttRec.fromJson(Map j) => AttRec(
        date: j['date'] ?? '',
        wid: j['wid'] ?? '',
        name: j['name'] ?? '',
        status: j['status'] ?? '--',
        loc: j['loc'] ?? '',
        wage: (j['wage'] ?? 0).toDouble(),
        xh: (j['xh'] ?? 0).toDouble(),
        notes: j['notes'] ?? '',
        settleId: j['settleId'] ?? '',
        paidAmt: (j['paidAmt'] ?? 0).toDouble(),
      );
  Map<String, dynamic> toRec() => {'wid': wid, 'status': status, 'loc': loc, 'xh': xh, 'notes': notes};
}

class BootData {
  final AppUser user;
  final List<Worker> workers;
  final List<AttRec> att;
  final List<String> locs;
  final List<AppUser> users;
  BootData({required this.user, required this.workers, required this.att, required this.locs, required this.users});
  factory BootData.fromJson(Map j) => BootData(
        user: AppUser.fromJson(j['user']),
        workers: ((j['workers'] ?? []) as List).map((w) => Worker.fromJson(w as Map)).toList(),
        att: ((j['att'] ?? []) as List).map((r) => AttRec.fromJson(r as Map)).toList(),
        locs: ((j['locs'] ?? []) as List).map((l) => l.toString()).toList(),
        users: ((j['users'] ?? []) as List).map((u) => AppUser.fromJson(u as Map)).toList(),
      );
}

const List<String> kStatuses = ['--', 'حضور', 'حضور + وقت اضافى', 'حضور + مبيت'];
const List<String> kExtraStatuses = ['حضور + وقت اضافى', 'حضور + مبيت'];

String fmtDate(String s) {
  if (s.isEmpty || s == '--') return '--';
  final p = s.split('-');
  if (p.length != 3) return s;
  return '${p[2]}/${p[1]}/${p[0]}';
}

double r2(double x) => (x * 100).round() / 100;

String otText(double h) {
  h = h.abs() < 0.005 ? 0 : h;
  if (h == 0) return '—';
  if (h == 1) return '1 ساعة';
  if (h == 2) return 'ساعتان';
  if (h >= 3 && h <= 10 && h % 1 == 0) return '${h.toInt()} ساعات';
  return '$h ساعة';
}
