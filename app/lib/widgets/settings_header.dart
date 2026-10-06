import 'package:flutter/material.dart';

class SettingsHeader extends StatelessWidget {
  const SettingsHeader({
    required this.title,
    required this.actionLabel,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}
