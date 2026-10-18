// نافذة تغيير رابط السيرفر (رابط تطبيق الويب في Apps Script الذي ينتهي بـ /exec)
import 'package:flutter/material.dart';
import 'api.dart';

/// ترجع true إذا تغيّر الرابط
Future<bool> showServerUrlDialog(BuildContext context) async {
  final cur = await Api.getUrl() ?? defaultUrlText;
  final c = TextEditingController(text: cur);
  String err = '';
  final changed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('رابط السيرفر', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('الصق رابط الويب الذي تفتحه في المتصفح (ينتهي بـ /exec). يظهر أيضًا في الويب بزر 🔗 أعلى الصفحة.', style: TextStyle(fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 10),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(controller: c, maxLines: 4, style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
            ),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: Colors.red, fontSize: 12.5))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              await Api.saveUrl('');
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('الافتراضي'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await Api.saveUrl(c.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on ApiException catch (e) {
                setD(() => err = e.message);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
  return changed == true;
}

const String defaultUrlText = Api.defaultUrl;
