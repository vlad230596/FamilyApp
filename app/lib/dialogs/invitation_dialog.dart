import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:familyapp/models/member.dart';

Future<void> showInvitationDialog(
  BuildContext context,
  ApiClient api, {
  Member? member,
}) async {
  var role = member?.role ?? 'parent';
  var busy = false;
  String? code;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          member == null ? 'Приглашение в семью' : 'Пригласить: ${member.name}',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (code == null && member == null)
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Роль в семье'),
                  items: const [
                    DropdownMenuItem(value: 'parent', child: Text('Родитель')),
                    DropdownMenuItem(value: 'child', child: Text('Ребёнок')),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => role = value!),
                ),
              if (code != null) ...[
                const Text(
                  'Передайте код приглашённому. Он действует 48 часов и используется один раз.',
                ),
                const SizedBox(height: 16),
                SelectableText(code!),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code!));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Код скопирован')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Скопировать код'),
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          if (code == null)
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final data = await api.createInvitation(
                          role: role,
                          memberId: member?.id,
                        );
                        if (context.mounted) {
                          setState(() => code = data['code'] as String);
                        }
                      } catch (exception) {
                        if (context.mounted) {
                          setState(() => error = exception.toString());
                        }
                      } finally {
                        if (context.mounted) setState(() => busy = false);
                      }
                    },
              child: const Text('Создать приглашение'),
            ),
        ],
      ),
    ),
  );
}
