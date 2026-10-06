import 'package:flutter/material.dart';
import 'package:familyapp/api/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/dialogs/archive_type_dialog.dart';
import 'package:familyapp/dialogs/member_dialog.dart';
import 'package:familyapp/dialogs/restriction_type_dialog.dart';
import 'package:familyapp/models/member.dart';
import 'package:familyapp/state/auth_store.dart';
import 'package:familyapp/state/family_store.dart';
import 'package:familyapp/utils/child_icons.dart';
import 'package:familyapp/utils/colors.dart';
import 'package:familyapp/widgets/empty_state.dart';
import 'package:familyapp/widgets/settings_header.dart';
import 'package:familyapp/dialogs/invitation_dialog.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({
    required this.state,
    required this.controller,
    super.key,
  });

  final FamilyState state;
  final FamilyStore controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStoreProvider);
    final me = auth.member;
    final canManage = auth.isParent;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Мой аккаунт', style: Theme.of(context).textTheme.titleLarge),
        if (me != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Icon(childIcon(me.icon))),
            title: Text(me.name),
            subtitle: Text('${roleLabel(me.role)} · ${me.login ?? ''}'),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (me != null)
              OutlinedButton.icon(
                onPressed: () => showCredentialsDialog(
                  context,
                  controller,
                  me,
                  isSelf: true,
                ),
                icon: const Icon(Icons.password),
                label: const Text('Сменить пароль'),
              ),
            OutlinedButton.icon(
              onPressed: () => ref.read(authStoreProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Выйти'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ref.read(authStoreProvider.notifier).chooseFamily(),
          icon: const Icon(Icons.family_restroom),
          label: const Text('Выбрать или создать семью'),
        ),
        if (canManage)
          OutlinedButton.icon(
            onPressed: () =>
                showInvitationDialog(context, ref.read(apiClientProvider)),
            icon: const Icon(Icons.person_add),
            label: const Text('Пригласить в семью'),
          ),
        const SizedBox(height: 24),
        if (canManage)
          SettingsHeader(
            title: 'Семья',
            actionLabel: 'Добавить',
            icon: Icons.add,
            onPressed: () => showMemberDialog(context, controller),
          )
        else
          Text('Семья', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (state.members.isEmpty)
          const EmptyInline(message: 'Пока никого нет.')
        else
          ...state.members.map(
            (member) => _MemberTile(
              member: member,
              controller: controller,
              canManage: canManage,
              api: ref.read(apiClientProvider),
              isSelf: member.id == me?.id,
            ),
          ),
        if (canManage) ...[
          const SizedBox(height: 24),
          SettingsHeader(
            title: 'Типы ограничений',
            actionLabel: 'Создать',
            icon: Icons.add,
            onPressed: () =>
                showRestrictionTypeDialog(context, state, controller),
          ),
          const SizedBox(height: 8),
          if (state.restrictionTypes.isEmpty)
            const EmptyInline(message: 'Создайте повторяемые типы с цветами.')
          else
            ...state.restrictionTypes.map(
              (type) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: colorFromHex(type.color),
                ),
                title: Text(type.name),
                trailing: IconButton(
                  tooltip: 'В архив',
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: () =>
                      showArchiveTypeDialog(context, controller, type),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.controller,
    required this.canManage,
    required this.isSelf,
    required this.api,
  });

  final Member member;
  final FamilyStore controller;
  final bool canManage;
  final bool isSelf;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final access = member.hasAccount
        ? 'вход: ${member.login}'
        : 'без входа в приложение';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(childIcon(member.icon))),
      title: Text(isSelf ? '${member.name} (вы)' : member.name),
      subtitle: Text('${roleLabel(member.role)} · $access'),
      trailing: canManage
          ? PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (action) => switch (action) {
                'edit' => showMemberDialog(context, controller, member: member),
                _ => showInvitationDialog(context, api, member: member),
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                if (!member.hasAccount)
                  const PopupMenuItem(
                    value: 'invite',
                    child: Text('Пригласить'),
                  ),
              ],
            )
          : null,
    );
  }
}

String roleLabel(String role) => role == 'parent' ? 'Родитель' : 'Ребенок';
