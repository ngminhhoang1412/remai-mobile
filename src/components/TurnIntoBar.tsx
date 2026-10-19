import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { BLOCK_TYPES } from '@/lib/blocks';
import type { BlockType } from '@/lib/types';
import { colors, radius, spacing } from '@/theme';

import { IconButton } from './ui';

/**
 * Shown above the keyboard while a block is focused: "Turn into" + all 10 block types.
 * keyboardShouldPersistTaps="always" keeps the block focused (and the keyboard up) while tapping.
 */
export function TurnIntoBar({
  current,
  onPick,
  onDone,
  bottomInset,
}: Readonly<{ current: BlockType; onPick: (type: BlockType) => void; onDone: () => void; bottomInset: number }>) {
  return (
    <View style={[styles.bar, { paddingBottom: bottomInset }]}>
      <ScrollView
        horizontal
        keyboardShouldPersistTaps="always"
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.content}
        accessibilityLabel="Turn into"
      >
        <Text style={styles.label}>Turn into</Text>
        {BLOCK_TYPES.map(({ type, label }) => {
          const selected = type === current;
          return (
            <Pressable
              key={type}
              onPress={() => onPick(type)}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              accessibilityLabel={`Turn into ${label}`}
              style={({ pressed }) => [styles.chip, selected && styles.chipSelected, pressed && styles.chipPressed]}
            >
              <Text style={[styles.chipText, selected && styles.chipTextSelected]}>{label}</Text>
            </Pressable>
          );
        })}
      </ScrollView>
      <View style={styles.done}>
        <IconButton name="chevron-down" label="Hide keyboard" onPress={onDone} color={colors.muted} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  content: { alignItems: 'center', paddingHorizontal: spacing.sm, paddingVertical: spacing.sm, gap: spacing.xs },
  label: { fontSize: 13, color: colors.muted, fontWeight: '600', marginRight: spacing.xs },
  chip: {
    paddingHorizontal: spacing.md,
    paddingVertical: 7,
    borderRadius: radius.lg,
    backgroundColor: colors.bg,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
  },
  chipSelected: { backgroundColor: colors.accent, borderColor: colors.accent },
  chipPressed: { opacity: 0.7 },
  chipText: { fontSize: 14, color: colors.text },
  chipTextSelected: { color: colors.accentText, fontWeight: '600' },
  done: { borderLeftWidth: StyleSheet.hairlineWidth, borderLeftColor: colors.border, paddingHorizontal: spacing.xs },
});
