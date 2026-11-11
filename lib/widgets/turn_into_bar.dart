import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// "Turn into" bar shown above the keyboard while a block is focused: scrolls sideways through all
/// 10 block types. It sits in a [TextFieldTapRegion] so tapping it counts as a tap inside the
/// focused field and never unfocuses it (the keyboard stays up).
class TurnIntoBar extends StatelessWidget {
  const TurnIntoBar({super.key, required this.current, required this.onPick, required this.onDone});

  final BlockType current;
  final ValueChanged<BlockType> onPick;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: Material(
        color: AppColors.bgSidebar,
        child: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: Space.s3, right: Space.s1),
                  child: Text(
                    'Turn into',
                    style: TextStyle(fontSize: FontSizes.small, color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const ValueKey('turn-into-list'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Space.s1),
                    children: [
                      for (final t in BlockType.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: Space.s2),
                          child: _TypeChip(type: t, selected: t == current, onTap: () => onPick(t)),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hide keyboard',
                  icon: const Icon(Icons.keyboard_hide_outlined, color: AppColors.textMuted),
                  onPressed: onDone,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type, required this.selected, required this.onTap});

  final BlockType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('turn-into-${type.name}'),
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.s3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.bgSelected : AppColors.bg,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            type.label,
            style: TextStyle(
              fontSize: FontSizes.small,
              color: AppColors.text,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
