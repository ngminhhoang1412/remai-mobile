import 'package:flutter/material.dart';

import '../theme.dart';

/// Icon picker set from designs/design-tokens.md (≥ 20, web-client "Page header").
const List<String> pageEmoji = [
  '📄', '📝', '📌', '📚', '💡', '✅', '🗓️', '🎯', //
  '🚀', '⭐', '🔥', '💼', '🏠', '🎨', '🧪', '🛒', //
  '✈️', '💰', '🎵', '🌱', '🧠', '📊', '🔒', '❤️', //
];

/// Bottom sheet with a grid of emoji and a Remove action. Resolves to the chosen emoji, '' for
/// Remove, or null when dismissed.
Future<String?> showEmojiPicker(BuildContext context, {required bool hasIcon}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Page icon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (hasIcon)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(''),
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Remove'),
                  ),
              ],
            ),
            const SizedBox(height: Space.s2),
            GridView.count(
              crossAxisCount: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final e in pageEmoji)
                  InkWell(
                    key: ValueKey('emoji-$e'),
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: () => Navigator.of(context).pop(e),
                    child: Semantics(
                      label: 'Icon $e',
                      button: true,
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
