// Chat Security — شات جماعي وخاص مع الحضور والاستلام والقراءة
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../state.dart';

String _mime(String n) {
  final e = n.toLowerCase().split('.').last;
  const m = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
    'pdf': 'application/pdf', 'txt': 'text/plain', 'csv': 'text/csv',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };
  return m[e] ?? 'application/octet-stream';
}

String _hm(num ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.hour)}:${t(d.minute)}';
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List users = [];
  List chats = [];
  String me = '';
  bool admin = false;
  Map wa = {};
  Map? cur;
  Timer? _t;
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    me = App.I.user?.username ?? '';
    _boot();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (cur == null) _boot(silent: true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _boot({bool silent = false}) async {
    try {
      final r = await Api.auth('chatBoot') as Map;
      if (!mounted) return;
      setState(() {
        users = r['users'] as List;
        chats = r['chats'] as List;
        admin = (r['me'] as Map)['admin'] == true;
        wa = (r['wa'] as Map?) ?? {};
        loading = false;
        err = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        loading = false;
        err = e.toString();
      });
    }
  }

  Map? _u(String n) {
    for (final u in users) {
      if (u['username'] == n) return u as Map;
    }
    return null;
  }

  String _title(Map c) {
    if (c['kind'] == 'private') {
      final o = (c['members'] as List).firstWhere((x) => x != me, orElse: () => '');
      return (_u(o)?['name'] ?? o).toString();
    }
    return (c['name'] ?? '').toString();
  }

  Future<void> _openPriv(String other) async {
    try {
      final c = await Api.auth('chatOpenPrivate', [other]) as Map;
      setState(() => cur = c);
    } catch (e) {
      _toast(e.toString());
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _phone() async {
    final c = TextEditingController(text: (_u(me)?['phone'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رقم واتساب الخاص بي'),
        content: TextField(controller: c, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '+20100...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Api.auth('setMyPhone', [c.text]);
        _boot();
      } catch (e) {
        _toast(e.toString());
      }
    }
  }

  Future<void> _newGroup() async {
    final name = TextEditingController();
    final sel = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, st) => AlertDialog(
          title: const Text('مجموعة جديدة'),
          content: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(hintText: 'اسم المجموعة')),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final u in users)
                    if (u['username'] != me)
                      CheckboxListTile(
                        dense: true,
                        value: sel.contains(u['username']),
                        title: Text(u['name'].toString()),
                        onChanged: (v) => st(() => v == true ? sel.add(u['username']) : sel.remove(u['username'])),
                      ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        final c = await Api.auth('chatNew', [name.text, sel.toList()]) as Map;
        await _boot();
        setState(() => cur = c);
      } catch (e) {
        _toast(e.toString());
      }
    }
  }

  Future<void> _wa(Map u) async {
    final p = (u['phone'] ?? '').toString().replaceAll(RegExp(r'[^\d]'), '');
    if (p.isEmpty) return _toast('لا يوجد رقم لهذا العضو');
    await launchUrl(Uri.parse('https://wa.me/$p'), mode: LaunchMode.externalApplication);
  }


  Future<void> _settings() async {
    final link = TextEditingController(text: (wa['link'] ?? '').toString());
    final nm = TextEditingController(text: (wa['name'] ?? 'Chat Security').toString());
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
            const Text('⚙️ إعدادات واتساب والأعضاء', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('أنشئ المجموعة أو القناة في واتساب ثم الصق رابط الدعوة ليظهر زر الانضمام للجميع.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            if (admin) ...[
              TextField(controller: nm, decoration: const InputDecoration(labelText: 'اسم المجموعة')),
              TextField(controller: link, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رابط الدعوة https://chat.whatsapp.com/...')),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    try {
                      final r = await Api.auth('chatWaSet', [link.text, nm.text]) as Map;
                      setState(() => wa = r);
                      _toast('تم الحفظ');
                    } catch (e) {
                      _toast(e.toString());
                    }
                  },
                  child: const Text('حفظ الرابط'),
                ),
              ),
            ],
            if ((wa['link'] ?? '').toString().isNotEmpty)
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.chat, color: Color(0xFF16A34A)),
                  label: const Text('انضمام في واتساب'),
                  onPressed: () => launchUrl(Uri.parse(wa['link'].toString()), mode: LaunchMode.externalApplication),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('إرسال الدعوة'),
                  onPressed: () => Share.share('انضم إلى ${wa['name'] ?? 'Chat Security'} على واتساب\n${wa['link']}'),
                ),
              ])
            else if (!admin)
              const Text('لم يضف المدير رابطًا بعد.'),
            const Divider(),
            const Text('👥 الأعضاء وأرقامهم', style: TextStyle(fontWeight: FontWeight.w900)),
            for (final u in users)
              _PhoneRow(
                u: u as Map,
                editable: admin,
                onSave: (v) async {
                  try {
                    final p = await Api.auth('chatSetPhone', [u['username'], v]);
                    u['phone'] = p;
                    _toast('تم حفظ الرقم');
                  } catch (e) {
                    _toast(e.toString());
                  }
                },
                onWa: () => _wa(u),
              ),
          ]),
        ),
      ),
    );
    if (mounted) setState(() {});
  }


  @override
  Widget build(BuildContext context) {
    if (cur != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (d, _) {
          if (!d) {
            setState(() => cur = null);
            _boot();
          }
        },
        child: _Room(
          key: ValueKey(cur!['id']),
          chat: cur!,
          title: _title(cur!),
          me: me,
          nameOf: (n) => (_u(n)?['name'] ?? n).toString(),
          users: users,
          admin: admin,
          onBack: () {
            setState(() => cur = null);
            _boot();
          },
        ),
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    if (err != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(err!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => _boot(), child: const Text('إعادة المحاولة')),
        ]),
      );
    }
    final online = users.where((u) => u['online'] == true).length;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Row(children: [
          Expanded(child: Text('🟢 $online متصل من ${users.length}', style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(tooltip: 'رقمي', icon: const Icon(Icons.phone_android, color: Color(0xFF0369A1)), onPressed: _phone),
          IconButton(tooltip: 'مجموعة جديدة', icon: const Icon(Icons.group_add, color: Color(0xFF16A34A)), onPressed: _newGroup),
          IconButton(tooltip: 'واتساب والأعضاء', icon: const Icon(Icons.settings, color: Color(0xFFC2410C)), onPressed: _settings),
        ]),
        const SizedBox(height: 4),
        for (final c in chats)
          Card(
            color: const Color(0xFFDCFCE7),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: c['kind'] == 'private' ? const Color(0xFFBFDBFE) : const Color(0xFF86EFAC),
                child: Icon(c['kind'] == 'private' ? Icons.person : Icons.groups, color: Colors.black87),
              ),
              title: Text(_title(c as Map), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                c['last'] == null ? '' : ((c['last']['text'] ?? '').toString().isEmpty ? '📎 ملف' : c['last']['text'].toString()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: (c['unread'] ?? 0) > 0
                  ? CircleAvatar(radius: 11, backgroundColor: Colors.red, child: Text('${c['unread']}', style: const TextStyle(color: Colors.white, fontSize: 11)))
                  : null,
              onTap: () => setState(() => cur = c),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text('الأعضاء', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF5B21B6))),
        ),
        for (final u in users)
          if (u['username'] != me)
            Card(
              color: const Color(0xFFEDE9FE),
              child: ListTile(
                dense: true,
                leading: Stack(children: [
                  CircleAvatar(backgroundColor: const Color(0xFFDDD6FE), child: Text(u['name'].toString().isEmpty ? '?' : u['name'].toString()[0])),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(radius: 5, backgroundColor: u['online'] == true ? Colors.green : Colors.grey),
                  ),
                ]),
                title: Text(u['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${u['online'] == true ? 'متصل' : 'غير متصل'}  ${u['phone'] ?? ''}'),
                trailing: (u['phone'] ?? '').toString().isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.chat, color: Color(0xFF16A34A)), onPressed: () => _wa(u as Map)),
                onTap: () => _openPriv(u['username']),
              ),
            ),
      ],
    );
  }
}

class _Room extends StatefulWidget {
  final Map chat;
  final String title, me;
  final String Function(String) nameOf;
  final List users;
  final VoidCallback onBack;
  final bool admin;
  const _Room({super.key, this.admin = false, required this.chat, required this.title, required this.me, required this.nameOf, required this.users, required this.onBack});
  @override
  State<_Room> createState() => _RoomState();
}

class _RoomState extends State<_Room> {
  List msgs = [];
  List users = [];
  final txt = TextEditingController();
  final sc = ScrollController();
  Timer? _t;
  bool sending = false;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    users = widget.users;
    _poll();
    _t = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final r = await Api.auth('chatPoll', [widget.chat['id']]) as Map;
      if (!mounted) return;
      final m = r['msgs'] as List;
      setState(() {
        msgs = m;
        users = r['users'] as List;
      });
      if (m.length != _lastCount) {
        _lastCount = m.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (sc.hasClients) sc.jumpTo(sc.position.maxScrollExtent);
        });
      }
      if (m.any((x) => x['from'] != widget.me && !(x['read'] as List).contains(widget.me))) {
        Api.auth('chatRead', [widget.chat['id']]).catchError((_) {});
      }
    } catch (_) {}
  }


  bool _canAdd() => widget.chat['kind'] == 'group' && widget.chat['members'] != '*' && (widget.admin || widget.chat['createdBy'] == widget.me);

  Future<void> _addMem() async {
    final cur = (widget.chat['members'] as List).map((e) => e.toString()).toList();
    final sel = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, st) => AlertDialog(
          title: const Text('إضافة أعضاء'),
          content: SizedBox(
            width: 320,
            child: ListView(shrinkWrap: true, children: [
              for (final u in users)
                if (!cur.contains(u['username']))
                  CheckboxListTile(
                    dense: true,
                    value: sel.contains(u['username']),
                    title: Text(u['name'].toString()),
                    onChanged: (v) => st(() => v == true ? sel.add(u['username']) : sel.remove(u['username'])),
                  ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (ok == true && sel.isNotEmpty) {
      try {
        final m = await Api.auth('chatAddMembers', [widget.chat['id'], sel.toList()]) as List;
        setState(() => widget.chat['members'] = m);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  List _others() {
    final mem = widget.chat['members'];
    final all = users.map((u) => u['username'].toString()).toList();
    final l = mem == '*' ? all : (mem as List).map((e) => e.toString()).toList();
    return l.where((x) => x != widget.me).toList();
  }

  Future<void> _send({String? file, String? fname}) async {
    final t = txt.text.trim();
    if (t.isEmpty && file == null) return;
    setState(() => sending = true);
    try {
      await Api.auth('chatSend', [widget.chat['id'], t, file ?? '', fname ?? '']);
      txt.clear();
      await _poll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _attach() async {
    final k = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera, color: Color(0xFF1D4ED8)), title: const Text('كاميرا'), onTap: () => Navigator.pop(context, 'cam')),
          ListTile(leading: const Icon(Icons.image, color: Color(0xFFBE185D)), title: const Text('صورة من المعرض'), onTap: () => Navigator.pop(context, 'gal')),
          ListTile(leading: const Icon(Icons.attach_file, color: Color(0xFFC2410C)), title: const Text('مستند / PDF / ملف'), onTap: () => Navigator.pop(context, 'file')),
        ]),
      ),
    );
    if (k == null) return;
    String? path, name;
    if (k == 'file') {
      final r = await FilePicker.platform.pickFiles();
      if (r == null || r.files.single.path == null) return;
      path = r.files.single.path;
      name = r.files.single.name;
    } else {
      final x = await ImagePicker().pickImage(source: k == 'cam' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, imageQuality: 75);
      if (x == null) return;
      path = x.path;
      name = x.name;
    }
    final f = File(path!);
    if (await f.length() > 6 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حجم الملف كبير (الحد 6 ميجا)')));
      return;
    }
    final b = base64Encode(await f.readAsBytes());
    await _send(file: 'data:${_mime(name!)};base64,$b', fname: name);
  }

  Future<void> _openFile(Map m) async {
    try {
      final r = await Api.auth('chatFile', [m['id']]) as Map?;
      if (r == null) throw ApiException('الملف غير متاح');
      final data = (r['data'] as String).split(',').last;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${r['name'] ?? 'file'}');
      await f.writeAsBytes(base64Decode(data));
      await Share.shareXFiles([XFile(f.path)]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _receipts(Map m) {
    final others = _others();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: [
          const Text('تفاصيل الرسالة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          for (final o in others)
            ListTile(
              dense: true,
              leading: Icon(
                (m['read'] as List).contains(o) ? Icons.done_all : (m['recv'] as List).contains(o) ? Icons.done_all : Icons.done,
                color: (m['read'] as List).contains(o) ? Colors.blue : Colors.grey,
              ),
              title: Text(widget.nameOf(o)),
              subtitle: Text((m['read'] as List).contains(o) ? 'قرأها' : (m['recv'] as List).contains(o) ? 'استلمها' : 'لم تصل بعد'),
            ),
        ]),
      ),
    );
  }

  Widget _ticks(Map m) {
    final o = _others();
    final read = o.isNotEmpty && o.every((x) => (m['read'] as List).contains(x));
    final recv = o.isNotEmpty && o.every((x) => (m['recv'] as List).contains(x) || (m['read'] as List).contains(x));
    return Icon(recv || read ? Icons.done_all : Icons.done, size: 15, color: read ? Colors.blue : Colors.grey);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: const Color(0xFFDCFCE7),
        child: ListTile(
          dense: true,
          leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: widget.onBack),
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900)),
          trailing: _canAdd() ? IconButton(icon: const Icon(Icons.person_add, color: Color(0xFF16A34A)), onPressed: _addMem) : null,
          subtitle: Text('${_others().where((x) => users.any((u) => u['username'] == x && u['online'] == true)).length} متصل'),
        ),
      ),
      Expanded(
        child: ListView.builder(
          controller: sc,
          padding: const EdgeInsets.all(8),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i] as Map;
            final mine = m['from'] == widget.me;
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: mine ? () => _receipts(m) : null,
                onTap: mine ? () => _receipts(m) : null,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: mine ? const Color(0xFFBBF7D0) : const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!mine) Text(m['fromName'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF5B21B6))),
                    if (m['hasFile'] == true)
                      InkWell(
                        onTap: () => _openFile(m),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon((m['ftype'] ?? '').toString().startsWith('image/') ? Icons.image : Icons.insert_drive_file, color: const Color(0xFFC2410C)),
                            const SizedBox(width: 4),
                            Flexible(child: Text(m['fname'].toString(), style: const TextStyle(decoration: TextDecoration.underline))),
                          ]),
                        ),
                      ),
                    if ((m['text'] ?? '').toString().isNotEmpty) Text(m['text'].toString()),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_hm(m['at'] as num), style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      if (mine) ...[const SizedBox(width: 4), _ticks(m)],
                    ]),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Row(children: [
          IconButton(icon: const Icon(Icons.attach_file, color: Color(0xFFC2410C)), onPressed: sending ? null : _attach),
          Expanded(
            child: TextField(controller: txt, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'اكتب رسالة...', isDense: true)),
          ),
          IconButton(
            icon: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send, color: Color(0xFF16A34A)),
            onPressed: sending ? null : () => _send(),
          ),
        ]),
      ),
    ]);
  }
}

class _PhoneRow extends StatelessWidget {
  final Map u;
  final bool editable;
  final Future<void> Function(String) onSave;
  final VoidCallback onWa;
  const _PhoneRow({required this.u, required this.editable, required this.onSave, required this.onWa});
  @override
  Widget build(BuildContext context) {
    final c = TextEditingController(text: (u['phone'] ?? '').toString());
    return Row(children: [
      CircleAvatar(radius: 5, backgroundColor: u['online'] == true ? Colors.green : Colors.grey),
      const SizedBox(width: 8),
      Expanded(child: Text(u['name'].toString())),
      if (editable)
        SizedBox(
          width: 130,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(isDense: true, hintText: 'رقم'),
            onSubmitted: onSave,
            onTapOutside: (_) => onSave(c.text),
          ),
        )
      else
        Text((u['phone'] ?? '—').toString(), textDirection: TextDirection.ltr),
      if ((u['phone'] ?? '').toString().isNotEmpty) IconButton(icon: const Icon(Icons.chat, color: Color(0xFF16A34A)), onPressed: onWa),
    ]);
  }
}
