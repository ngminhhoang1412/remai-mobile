import Ionicons from '@expo/vector-icons/Ionicons';
import { memo, type ReactNode } from 'react';
import {
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInputInstance,
  type TextInputKeyPressEvent,
} from 'react-native';

import { placeholderFor } from '@/lib/blocks';
import type { Block } from '@/lib/types';
import { colors, fontSize, monoFont, radius, spacing } from '@/theme';

export interface BlockRowHandlers {
  onChangeText: (id: string, text: string) => void;
  onBackspace: (id: string) => void;
  onFocus: (id: string) => void;
  onBlur: (id: string) => void;
  onToggle: (id: string) => void;
  onDividerLongPress: (id: string) => void;
  registerInput: (id: string, input: TextInputInstance | null) => void;
  onLayout: (id: string, y: number, height: number) => void;
}

interface Props extends BlockRowHandlers {
  block: Block;
  /** Running number for numbered blocks, else null. */
  number: number | null;
  showPlaceholder: boolean;
}

/**
 * One block, edited in place with a multiline TextInput. The row always renders
 * [prefix slot, TextInput] in the same positions so changing the type ("Turn into") re-styles the
 * existing input instead of remounting it, which would drop focus and the keyboard.
 */
function BlockRowImpl({ block, number, showPlaceholder, ...h }: Readonly<Props>) {
  const { id, type } = block;

  if (type === 'divider') {
    return (
      <Pressable
        onLayout={(e) => h.onLayout(id, e.nativeEvent.layout.y, e.nativeEvent.layout.height)}
        onLongPress={() => h.onDividerLongPress(id)}
        accessibilityRole="none"
        accessibilityLabel="Divider. Long press to delete."
        style={styles.dividerRow}
      >
        <View style={styles.dividerLine} />
      </Pressable>
    );
  }

  let prefix: ReactNode = null;
  if (type === 'todo') {
    prefix = (
      <Pressable
        onPress={() => h.onToggle(id)}
        hitSlop={10}
        accessibilityRole="checkbox"
        accessibilityState={{ checked: block.checked }}
        accessibilityLabel={block.checked ? 'Mark as not done' : 'Mark as done'}
        style={styles.prefix}
      >
        <Ionicons
          name={block.checked ? 'checkbox' : 'square-outline'}
          size={21}
          color={block.checked ? colors.accent : colors.muted}
        />
      </Pressable>
    );
  } else if (type === 'bulleted') {
    prefix = (
      <View style={styles.prefix}>
        <Text style={styles.bullet}>•</Text>
      </View>
    );
  } else if (type === 'numbered') {
    prefix = (
      <View style={styles.prefix}>
        <Text style={styles.number}>{`${number ?? 1}.`}</Text>
      </View>
    );
  }

  const isCode = type === 'code';
  const onKeyPress = (e: TextInputKeyPressEvent) => {
    if (e.nativeEvent.key === 'Backspace') h.onBackspace(id);
  };

  return (
    <View
      onLayout={(e) => h.onLayout(id, e.nativeEvent.layout.y, e.nativeEvent.layout.height)}
      style={[styles.row, type === 'quote' && styles.quoteRow, isCode && styles.codeRow]}
    >
      {prefix}
      <TextInput
        ref={(r) => h.registerInput(id, r)}
        value={block.text}
        onChangeText={(t) => h.onChangeText(id, t)}
        onKeyPress={onKeyPress}
        onFocus={() => h.onFocus(id)}
        onBlur={() => h.onBlur(id)}
        multiline
        scrollEnabled={false}
        maxLength={10000}
        placeholder={showPlaceholder ? placeholderFor(type) : undefined}
        placeholderTextColor={colors.faint}
        autoCapitalize={isCode ? 'none' : 'sentences'}
        autoCorrect={!isCode}
        spellCheck={!isCode}
        textAlignVertical="top"
        underlineColorAndroid="transparent"
        accessibilityLabel={`${type} block`}
        style={[
          styles.input,
          typeStyles[type],
          type === 'todo' && block.checked && styles.checkedText,
        ]}
      />
    </View>
  );
}

export const BlockRow = memo(BlockRowImpl);

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'flex-start', marginVertical: 1 },
  quoteRow: { borderLeftWidth: 3, borderLeftColor: colors.text, paddingLeft: spacing.md, marginVertical: spacing.xs },
  codeRow: {
    backgroundColor: colors.codeBg,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    marginVertical: spacing.xs,
  },
  prefix: { width: 26, height: 30, alignItems: 'flex-start', justifyContent: 'center' },
  bullet: { fontSize: 22, lineHeight: 26, color: colors.text },
  number: { fontSize: fontSize.body, color: colors.text, fontVariant: ['tabular-nums'] },
  input: {
    flex: 1,
    fontSize: fontSize.body,
    lineHeight: 24,
    color: colors.text,
    paddingTop: 3,
    paddingBottom: 3,
    paddingHorizontal: 0,
    margin: 0,
    includeFontPadding: false,
  },
  checkedText: { textDecorationLine: 'line-through', color: colors.muted },
  dividerRow: { paddingVertical: spacing.md },
  dividerLine: { height: 1, backgroundColor: colors.border },
});

const typeStyles = StyleSheet.create({
  paragraph: {},
  heading1: { fontSize: fontSize.h1, lineHeight: 38, fontWeight: '700', marginTop: spacing.md },
  heading2: { fontSize: fontSize.h2, lineHeight: 30, fontWeight: '700', marginTop: spacing.sm },
  heading3: { fontSize: fontSize.h3, lineHeight: 26, fontWeight: '600', marginTop: spacing.xs },
  todo: {},
  bulleted: {},
  numbered: {},
  quote: { fontSize: 17 },
  code: { fontFamily: monoFont, fontSize: 14, lineHeight: 20 },
  divider: {},
});
