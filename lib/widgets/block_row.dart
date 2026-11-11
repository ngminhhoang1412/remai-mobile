import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/blocks.dart';
import '../models/models.dart';
import '../theme.dart';

/// Controller for a block's field. The field text is [sentinel] + block text (see AGENTS.md,
/// "Backspace on an empty block"); every value written to it, by the user or the framework, gets
/// its selection moved out of the sentinel, so typing and caret moves never land before it.
class BlockTextController extends TextEditingController {
  BlockTextController(String blockText) : super(text: withSentinel(blockText));

  @override
  set value(TextEditingValue newValue) {
    final sel = newValue.selection;
    final clamped = sel.isValid ? clampSelection(newValue.text, sel.baseOffset, sel.extentOffset) : null;
    super.value = clamped == null
        ? newValue
        : newValue.copyWith(
            selection: sel.copyWith(baseOffset: clamped.base, extentOffset: clamped.extent),
            composing: TextRange.empty,
          );
  }

  /// The block text without the sentinel.
  String get blockText => readSentinel(text).text;

  /// Replaces the field with [blockText] (+ sentinel) and puts the caret at the end, or at the
  /// start of the text when [atEnd] is false.
  void setBlockText(String blockText, {bool atEnd = true}) {
    final full = withSentinel(blockText);
    value = TextEditingValue(text: full, selection: TextSelection.collapsed(offset: atEnd ? full.length : 1));
  }

  void moveCaret({required bool atEnd}) {
    selection = TextSelection.collapsed(offset: atEnd ? text.length : 1);
  }
}

/// One block, edited in place with a multiline TextField. The widget tree is the same shape for
/// every editable type (margin > decoration > padding > Row[prefix slot, Expanded[Stack[hint, field]]])
/// so "Turn into" re-styles the existing field instead of remounting it, which would drop focus
/// and close the keyboard.
class BlockRow extends StatelessWidget {
  const BlockRow({
    super.key,
    required this.block,
    required this.number,
    required this.controller,
    required this.focusNode,
    required this.showPlaceholder,
    required this.onChanged,
    required this.onToggle,
    required this.onDividerLongPress,
  });

  final Block block;

  /// Running number for numbered blocks, else null.
  final int? number;
  final BlockTextController controller;
  final FocusNode focusNode;
  final bool showPlaceholder;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggle;
  final VoidCallback onDividerLongPress;

  static const double _gutter = 26;

  @override
  Widget build(BuildContext context) {
    final type = block.type;
    if (type == BlockType.divider) {
      return Semantics(
        label: 'Divider. Long press to delete.',
        child: GestureDetector(
          key: ValueKey('divider-${block.id}'),
          behavior: HitTestBehavior.opaque,
          onLongPress: onDividerLongPress,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.s3),
            child: Divider(height: 1),
          ),
        ),
      );
    }

    final isCode = type == BlockType.code;
    final style = _textStyle(type, block.checked);

    return Padding(
      padding: EdgeInsets.only(top: _topMargin(type), bottom: isCode || type == BlockType.quote ? Space.s1 : 0),
      child: DecoratedBox(
        decoration: switch (type) {
          BlockType.quote => const BoxDecoration(border: Border(left: BorderSide(color: AppColors.text, width: 3))),
          BlockType.code => BoxDecoration(
              color: AppColors.codeBg,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
          _ => const BoxDecoration(),
        },
        child: Padding(
          padding: switch (type) {
            BlockType.quote => const EdgeInsets.only(left: 14),
            BlockType.code => const EdgeInsets.all(Space.s3),
            _ => EdgeInsets.zero,
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: switch (type) {
                  BlockType.todo || BlockType.bulleted || BlockType.numbered => _gutter,
                  _ => 0,
                },
                child: _prefix(type),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Placeholder (the field's own hint never shows: its text always holds the sentinel).
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            showPlaceholder && block.text.isEmpty ? placeholderFor(type) : '',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: style.copyWith(color: AppColors.textFaint, decoration: TextDecoration.none),
                          ),
                        ),
                      ),
                    ),
                    TextField(
                      key: ValueKey('block-field-${block.id}'),
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: style,
                      cursorColor: AppColors.text,
                      decoration: const InputDecoration.collapsed(hintText: null)
                          .copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 3), isCollapsed: true),
                      // 10000 characters of text plus the sentinel (page-content limits).
                      inputFormatters: [LengthLimitingTextInputFormatter(10001)],
                      textCapitalization: isCode ? TextCapitalization.none : TextCapitalization.sentences,
                      autocorrect: !isCode,
                      enableSuggestions: !isCode,
                      smartDashesType: isCode ? SmartDashesType.disabled : SmartDashesType.enabled,
                      smartQuotesType: isCode ? SmartQuotesType.disabled : SmartQuotesType.enabled,
                      scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 64),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _prefix(BlockType type) {
    switch (type) {
      case BlockType.todo:
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 22,
            height: 30,
            child: Checkbox(
              key: ValueKey('todo-check-${block.id}'),
              value: block.checked,
              onChanged: (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              semanticLabel: block.checked ? 'Mark as not done' : 'Mark as done',
            ),
          ),
        );
      case BlockType.bulleted:
        return const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Text('•', style: TextStyle(fontSize: 20, height: 1.3, color: AppColors.text)),
        );
      case BlockType.numbered:
        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${number ?? 1}.',
            style: const TextStyle(
              fontSize: FontSizes.body,
              height: 1.5,
              color: AppColors.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      default:
        return null;
    }
  }

  static double _topMargin(BlockType type) => switch (type) {
        BlockType.heading1 => Space.s5,
        BlockType.heading2 => Space.s4,
        BlockType.heading3 => Space.s3,
        BlockType.code || BlockType.quote => Space.s1,
        _ => 1,
      };

  static TextStyle _textStyle(BlockType type, bool checked) {
    const body = TextStyle(fontSize: FontSizes.body, height: 1.5, color: AppColors.text);
    return switch (type) {
      BlockType.heading1 => body.copyWith(fontSize: FontSizes.h1, height: 1.3, fontWeight: FontWeight.w600),
      BlockType.heading2 => body.copyWith(fontSize: FontSizes.h2, height: 1.3, fontWeight: FontWeight.w600),
      BlockType.heading3 => body.copyWith(fontSize: FontSizes.h3, height: 1.3, fontWeight: FontWeight.w600),
      BlockType.code => body.copyWith(
          fontSize: FontSizes.code,
          height: 1.45,
          fontFamily: monoFamily,
          fontFamilyFallback: monoFallback,
        ),
      BlockType.todo when checked => body.copyWith(
          color: AppColors.textMuted,
          decoration: TextDecoration.lineThrough,
          decorationColor: AppColors.textMuted,
        ),
      _ => body,
    };
  }
}
