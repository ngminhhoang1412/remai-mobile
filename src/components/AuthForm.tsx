import type { ReactNode } from 'react';
import { KeyboardAvoidingView, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { colors, spacing } from '@/theme';

/** Shared, keyboard-safe layout for the sign-in and sign-up screens. */
export function AuthLayout({
  subtitle,
  error,
  children,
  footer,
}: Readonly<{ subtitle: string; error: string | null; children: ReactNode; footer: ReactNode }>) {
  const insets = useSafeAreaInsets();
  return (
    <KeyboardAvoidingView style={styles.flex} behavior="padding">
      <ScrollView
        style={styles.flex}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={[
          styles.content,
          { paddingTop: insets.top + spacing.xl * 2, paddingBottom: insets.bottom + spacing.xl },
        ]}
      >
        <View style={styles.inner}>
          <Text style={styles.brand}>remai</Text>
          <Text style={styles.subtitle}>{subtitle}</Text>
          {error ? (
            <View style={styles.errorBox} accessibilityLiveRegion="polite">
              <Text style={styles.errorText}>{error}</Text>
            </View>
          ) : null}
          {children}
          <View style={styles.footer}>{footer}</View>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1, backgroundColor: colors.bg },
  content: { flexGrow: 1, paddingHorizontal: spacing.xl },
  inner: { width: '100%', maxWidth: 420, alignSelf: 'center' },
  brand: { fontSize: 34, fontWeight: '800', color: colors.text, letterSpacing: -0.5 },
  subtitle: { fontSize: 16, color: colors.muted, marginTop: spacing.xs, marginBottom: spacing.xl },
  errorBox: { backgroundColor: colors.dangerBg, borderRadius: 8, padding: spacing.md, marginBottom: spacing.lg },
  errorText: { color: colors.danger, fontSize: 14 },
  footer: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', marginTop: spacing.xl, gap: 6 },
});

export const authStyles = StyleSheet.create({
  footerText: { color: colors.muted, fontSize: 15 },
  link: { color: colors.accent, fontSize: 15, fontWeight: '600' },
});

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function validateEmail(email: string): string | null {
  if (email.trim() === '') return 'Enter your email.';
  return EMAIL_RE.test(email.trim()) ? null : 'Enter a valid email address.';
}

/** Mirrors the server's registration rules (user-auth spec) so most mistakes never round-trip. */
export function validateRegistration(name: string, email: string, password: string) {
  const n = name.trim();
  return {
    name: n.length === 0 ? 'Enter your name.' : n.length > 80 ? 'Name must be at most 80 characters.' : null,
    email: validateEmail(email),
    password:
      password.length < 8
        ? 'Password must be at least 8 characters.'
        : password.length > 72
          ? 'Password must be at most 72 characters.'
          : null,
  };
}
