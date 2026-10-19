import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect, type ReactNode } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { Button, LoadingState } from '@/components/ui';
import { API_URL } from '@/lib/config';
import { PagesProvider } from '@/state/pages';
import { SessionProvider, useSession } from '@/state/session';
import { colors, spacing } from '@/theme';

void SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <SessionProvider>
        <PagesProvider>
          <StatusBar style="dark" />
          <RootNavigator />
        </PagesProvider>
      </SessionProvider>
    </SafeAreaProvider>
  );
}

/**
 * Stack navigation: sign-in/sign-up → Home → Page (+ Search, Trash). Stack.Protected swaps the
 * available screens on the session status, so a 401 anywhere (which clears the session) lands
 * the user on sign-in without explicit navigation.
 */
function RootNavigator() {
  const { status } = useSession();
  const signedIn = status === 'signedIn';

  useEffect(() => {
    if (status !== 'loading') void SplashScreen.hideAsync();
  }, [status]);

  return (
    <View style={styles.root}>
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.bg } }}>
        <Stack.Protected guard={signedIn}>
          <Stack.Screen name="index" />
          <Stack.Screen name="page/[id]" />
          <Stack.Screen name="search" options={{ animation: 'fade' }} />
          <Stack.Screen name="trash" />
        </Stack.Protected>
        <Stack.Protected guard={!signedIn}>
          <Stack.Screen name="sign-in" />
          <Stack.Screen name="sign-up" />
        </Stack.Protected>
      </Stack>
      {status === 'loading' ? (
        <Overlay>
          <LoadingState />
        </Overlay>
      ) : null}
      {status === 'unreachable' ? <UnreachableOverlay /> : null}
    </View>
  );
}

function Overlay({ children }: Readonly<{ children: ReactNode }>) {
  return <View style={[StyleSheet.absoluteFill, styles.overlay]}>{children}</View>;
}

/** A token is stored but the server could not be reached to check it: offer retry, keep the token. */
function UnreachableOverlay() {
  const { retryLaunchCheck, signOut } = useSession();
  return (
    <Overlay>
      <View style={styles.unreachable}>
        <Text style={styles.title}>Can’t reach remai</Text>
        <Text style={styles.message}>
          Check your connection and that the server at {API_URL} is running.
        </Text>
        <Button title="Try again" onPress={retryLaunchCheck} style={styles.button} />
        <Button title="Sign out" variant="secondary" onPress={() => void signOut()} style={styles.button} />
      </View>
    </Overlay>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.bg },
  overlay: { backgroundColor: colors.bg, justifyContent: 'center' },
  unreachable: { padding: spacing.xl, alignItems: 'stretch' },
  title: { fontSize: 22, fontWeight: '700', color: colors.text, textAlign: 'center' },
  message: { fontSize: 15, color: colors.muted, textAlign: 'center', marginTop: spacing.sm, marginBottom: spacing.xl },
  button: { marginTop: spacing.md },
});
