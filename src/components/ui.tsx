// Small shared UI pieces: header, buttons, text field, loading/error/empty states.
import Ionicons from '@expo/vector-icons/Ionicons';
import { router } from 'expo-router';
import type { ComponentProps, ReactNode, Ref } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type StyleProp,
  type TextInputInstance,
  type TextInputProps,
  type ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { errorMessage, isApiError } from '@/lib/api';
import { colors, fontSize, radius, spacing } from '@/theme';

export type IconName = ComponentProps<typeof Ionicons>['name'];

export function ScreenHeader({
  left,
  title,
  right,
  children,
}: Readonly<{ left?: ReactNode; title?: string; right?: ReactNode; children?: ReactNode }>) {
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.header, { paddingTop: insets.top + spacing.xs }]}>
      {left}
      {children ?? (
        <Text style={styles.headerTitle} numberOfLines={1} accessibilityRole="header">
          {title ?? ''}
        </Text>
      )}
      {right ? <View style={styles.headerRight}>{right}</View> : null}
    </View>
  );
}

export function IconButton({
  name,
  onPress,
  label,
  color = colors.text,
  size = 22,
  disabled,
}: Readonly<{ name: IconName; onPress: () => void; label: string; color?: string; size?: number; disabled?: boolean }>) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      hitSlop={8}
      style={({ pressed }) => [styles.iconButton, pressed && styles.pressed, disabled && styles.disabled]}
    >
      <Ionicons name={name} size={size} color={color} />
    </Pressable>
  );
}

export function BackButton() {
  return (
    <IconButton
      name="chevron-back"
      label="Back"
      size={26}
      onPress={() => {
        if (router.canGoBack()) router.back();
        else router.replace('/');
      }}
    />
  );
}

export function Button({
  title,
  onPress,
  variant = 'primary',
  loading,
  disabled,
  style,
}: Readonly<{
  title: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary' | 'danger';
  loading?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}>) {
  const isDisabled = disabled || loading;
  return (
    <Pressable
      onPress={onPress}
      disabled={isDisabled}
      accessibilityRole="button"
      accessibilityState={{ disabled: !!isDisabled, busy: !!loading }}
      style={({ pressed }) => [
        styles.button,
        variant === 'primary' && styles.buttonPrimary,
        variant === 'secondary' && styles.buttonSecondary,
        variant === 'danger' && styles.buttonDanger,
        pressed && { opacity: 0.75 },
        isDisabled && styles.disabled,
        style,
      ]}
    >
      {loading ? (
        <ActivityIndicator color={variant === 'primary' ? colors.accentText : colors.text} />
      ) : (
        <Text
          style={[
            styles.buttonText,
            variant === 'primary' && { color: colors.accentText },
            variant === 'danger' && { color: colors.danger },
          ]}
        >
          {title}
        </Text>
      )}
    </Pressable>
  );
}

export function TextField({
  label,
  error,
  ...input
}: Readonly<TextInputProps & { label: string; error?: string | null; ref?: Ref<TextInputInstance> }>) {
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        placeholderTextColor={colors.faint}
        {...input}
        style={[styles.fieldInput, error ? styles.fieldInputError : null]}
        accessibilityLabel={label}
      />
      {error ? <Text style={styles.fieldError}>{error}</Text> : null}
    </View>
  );
}

export function LoadingState() {
  return (
    <View style={styles.center}>
      <ActivityIndicator color={colors.muted} />
    </View>
  );
}

export function MessageState({
  icon,
  title,
  message,
  actionLabel,
  onAction,
}: Readonly<{ icon: IconName; title: string; message?: string; actionLabel?: string; onAction?: () => void }>) {
  return (
    <View style={styles.center}>
      <Ionicons name={icon} size={40} color={colors.faint} />
      <Text style={styles.stateTitle}>{title}</Text>
      {message ? <Text style={styles.stateMessage}>{message}</Text> : null}
      {actionLabel && onAction ? (
        <Button title={actionLabel} onPress={onAction} variant="secondary" style={{ marginTop: spacing.lg }} />
      ) : null}
    </View>
  );
}

export const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.sm,
    paddingBottom: spacing.sm,
    minHeight: 48,
    backgroundColor: colors.bg,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
    gap: spacing.xs,
  },
  headerTitle: { flex: 1, fontSize: 18, fontWeight: '600', color: colors.text, paddingHorizontal: spacing.sm },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
  iconButton: { padding: spacing.sm, borderRadius: radius.md },
  pressed: { backgroundColor: colors.pressed },
  disabled: { opacity: 0.45 },
  button: {
    minHeight: 46,
    borderRadius: radius.md,
    paddingHorizontal: spacing.lg,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonPrimary: { backgroundColor: colors.accent },
  buttonSecondary: { backgroundColor: colors.bg, borderWidth: 1, borderColor: colors.border },
  buttonDanger: { backgroundColor: colors.dangerBg },
  buttonText: { fontSize: fontSize.body, fontWeight: '600', color: colors.text },
  field: { marginBottom: spacing.lg },
  fieldLabel: { fontSize: fontSize.small, color: colors.muted, marginBottom: spacing.xs, fontWeight: '500' },
  fieldInput: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    fontSize: fontSize.body,
    color: colors.text,
    backgroundColor: colors.bg,
  },
  fieldInputError: { borderColor: colors.danger },
  fieldError: { color: colors.danger, fontSize: fontSize.small, marginTop: spacing.xs },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  stateTitle: { marginTop: spacing.md, fontSize: 17, fontWeight: '600', color: colors.text, textAlign: 'center' },
  stateMessage: { marginTop: spacing.xs, fontSize: 15, color: colors.muted, textAlign: 'center' },
});

/** Alert for a failed action. Silent on 401: the session was cleared and sign-in is showing. */
export function showError(title: string, e: unknown) {
  if (isApiError(e) && e.status === 401) return;
  Alert.alert(title, errorMessage(e));
}
