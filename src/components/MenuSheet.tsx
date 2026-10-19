import Ionicons from '@expo/vector-icons/Ionicons';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { colors, radius, spacing } from '@/theme';

import type { IconName } from './ui';

export interface MenuItem {
  label: string;
  icon: IconName;
  onPress: () => void;
  destructive?: boolean;
}

/** A small popover menu anchored under the header's top-right corner. */
export function MenuSheet({
  visible,
  onClose,
  items,
}: Readonly<{ visible: boolean; onClose: () => void; items: MenuItem[] }>) {
  const insets = useSafeAreaInsets();
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose} statusBarTranslucent>
      <Pressable style={styles.backdrop} onPress={onClose} accessibilityLabel="Close menu">
        <View style={[styles.card, { top: insets.top + 52, right: spacing.md }]} accessibilityRole="menu">
          {items.map((item) => (
            <Pressable
              key={item.label}
              accessibilityRole="menuitem"
              onPress={() => {
                onClose();
                item.onPress();
              }}
              style={({ pressed }) => [styles.item, pressed && { backgroundColor: colors.pressed }]}
            >
              <Ionicons name={item.icon} size={20} color={item.destructive ? colors.danger : colors.text} />
              <Text style={[styles.label, item.destructive && { color: colors.danger }]}>{item.label}</Text>
            </Pressable>
          ))}
        </View>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.08)' },
  card: {
    position: 'absolute',
    minWidth: 200,
    backgroundColor: colors.bg,
    borderRadius: radius.lg,
    paddingVertical: spacing.xs,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: colors.border,
    shadowColor: '#000',
    shadowOpacity: 0.12,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
    elevation: 6,
  },
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.md,
  },
  label: { fontSize: 16, color: colors.text },
});
