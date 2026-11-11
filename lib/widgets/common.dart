import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../theme.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// Centered icon + title + message, with an optional action (empty, error and not-found states).
class MessageState extends StatelessWidget {
  const MessageState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textFaint),
            const SizedBox(height: Space.s3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
            if (message != null) ...[
              const SizedBox(height: Space.s2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: FontSizes.small, color: AppColors.textMuted),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Space.s4),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: Space.s2),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Page icon (emoji) or a neutral document glyph.
class PageIcon extends StatelessWidget {
  const PageIcon(this.icon, {super.key, this.size = 18});

  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (icon.isEmpty) return Icon(Icons.description_outlined, size: size + 2, color: AppColors.textMuted);
    return Text(icon, style: TextStyle(fontSize: size, height: 1.2));
  }
}

/// Page title, with "Untitled" in the muted colour for an empty title.
class PageTitleText extends StatelessWidget {
  const PageTitleText(this.title, {super.key, this.style});

  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final untitled = title.trim().isEmpty;
    final base = style ?? const TextStyle(fontSize: FontSizes.body, color: AppColors.text);
    return Text(
      displayTitle(title),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: untitled ? base.copyWith(color: AppColors.textMuted) : base,
    );
  }
}

void showErrorSnack(BuildContext context, String prefix, Object error) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$prefix: ${errorMessage(error)}')));
}
