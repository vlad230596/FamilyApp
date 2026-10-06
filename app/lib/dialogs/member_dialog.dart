import 'package:flutter/material.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/child_icons.dart';

/// Creates a family member, or edits the name and icon of an existing one.
Future<void> showMemberDialog(
  BuildContext context,
  FamilyStore store, {
  Member? member,
}) async {
  final nameController = TextEditingController(text: member?.name ?? '');
  var selectedIcon = member?.icon ?? 'star';
  var role = member?.role ?? 'child';
  String? nameError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(member == null ? 'Новый член семьи' : member.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: member == null,
                decoration: InputDecoration(
                  labelText: 'Имя',
                  errorText: nameError,
                ),
              ),
              if (member == null) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'child', label: Text('Ребенок')),
                    ButtonSegment(value: 'parent', label: Text('Родитель')),
                  ],
                  selected: {role},
                  onSelectionChanged: (value) =>
                      setState(() => role = value.first),
                ),
              ],
              const SizedBox(height: 12),
              ChildIconPicker(
                selectedIcon: selectedIcon,
                onSelected: (icon) => setState(() => selectedIcon = icon),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              setState(() {
                nameError = nameController.text.trim().isEmpty
                    ? 'Введите имя'
                    : null;
              });
              if (nameError != null) return;
              final ok = member == null
                  ? await store.createMember(
                      name: nameController.text,
                      icon: selectedIcon,
                      role: role,
                    )
                  : await store.updateMember(
                      member.id,
                      nameController.text,
                      selectedIcon,
                    );
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: Text(member == null ? 'Добавить' : 'Сохранить'),
          ),
        ],
      ),
    ),
  );
}

/// Sets or replaces login and password of a family member.
Future<void> showCredentialsDialog(
  BuildContext context,
  FamilyStore store,
  Member member, {
  required bool isSelf,
}) async {
  final loginController = TextEditingController(text: member.login ?? '');
  final passwordController = TextEditingController();
  final repeatController = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          member.hasAccount ? 'Логин и пароль' : 'Доступ для ${member.name}',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: loginController,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Логин'),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Новый пароль'),
              ),
              TextField(
                controller: repeatController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Повторите пароль',
                  errorText: error,
                ),
              ),
              if (member.hasAccount) ...[
                const SizedBox(height: 8),
                Text(
                  isSelf
                      ? 'На других устройствах нужно будет войти заново.'
                      : 'На всех устройствах ${member.name} нужно будет войти заново.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (passwordController.text != repeatController.text) {
                setState(() => error = 'Пароли не совпадают');
                return;
              }
              setState(() => error = null);
              final ok = await store.setCredentials(
                member.id,
                loginController.text.trim(),
                passwordController.text,
              );
              if (ok && context.mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

class ChildIconPicker extends StatelessWidget {
  const ChildIconPicker({
    required this.selectedIcon,
    required this.onSelected,
    super.key,
  });

  final String selectedIcon;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: childIconOptions
          .map(
            (option) => ChoiceChip(
              avatar: Icon(childIcon(option), size: 18),
              label: Text(childIconLabel(option)),
              selected: selectedIcon == option,
              onSelected: (_) => onSelected(option),
            ),
          )
          .toList(),
    );
  }
}
