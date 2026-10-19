import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { colors, radius, spacing } from '@/theme';

export const EMOJI = [
  '📄', '📝', '📌', '📚', '📅', '✅', '💡', '🚀',
  '🎯', '⭐', '🔥', '❤️', '🌱', '🏠', '💼', '🧠',
  '🎨', '🎵', '✈️', '🍕', '☕', '🛒', '💰', '📈',
  '🐛', '🔧', '🔒', '🌍', '🎉', '🙂', '🤔', '⚡',
];

/** Bottom sheet with a grid of emoji and a Remove action (page icon picker). */
export function EmojiPicker({
  visible,
  hasIcon,
  onSelect,
  onRemove,
  onClose,
}: Readonly<{
  visible: boolean;
  hasIcon: boolean;
  onSelect: (emoji: string) => void;
  onRemove: () => void;
  onClose: () => void;
}>) {
  const insets = useSafeAreaInsets();
  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose} statusBarTranslucent>
      <Pressable style={styles.backdrop} onPress={onClose} accessibilityLabel="Close icon picker" />
      <View style={[styles.sheet, { paddingBottom: insets.bottom + spacing.md }]}>
        <View style={styles.headerRow}>
          <Text style={styles.title}>Page icon</Text>
          {hasIcon ? (
            <Pressable onPress={onRemove} accessibilityRole="button" hitSlop={8}>
              <Text style={styles.remove}>Remove</Text>
            </Pressable>
          ) : null}
        </View>
        <View style={styles.grid}>
          {EMOJI.map((e) => (
            <Pressable
              key={e}
              onPress={() => onSelect(e)}
              accessibilityRole="button"
              accessibilityLabel={`Icon ${e}`}
              style={({ pressed }) => [styles.cell, pressed && { backgroundColor: colors.pressed }]}
            >
              <Text style={styles.emoji}>{e}</Text>
            </Pressable>
          ))}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.backdrop },
  sheet: {
    backgroundColor: colors.bg,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    paddingTop: spacing.lg,
    paddingHorizontal: spacing.md,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: spacing.sm,
    marginBottom: spacing.sm,
  },
  title: { fontSize: 16, fontWeight: '600', color: colors.text },
  remove: { fontSize: 15, color: colors.danger, fontWeight: '500' },
  grid: { flexDirection: 'row', flexWrap: 'wrap' },
  cell: { width: '12.5%', aspectRatio: 1, alignItems: 'center', justifyContent: 'center', borderRadius: radius.md },
  emoji: { fontSize: 26 },
});
