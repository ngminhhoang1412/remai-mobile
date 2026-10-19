import * as SecureStore from 'expo-secure-store';

// The session token lives only in the platform's secure storage
// (iOS Keychain / Android Keystore-backed), never in AsyncStorage or plain files.
const TOKEN_KEY = 'remai.session.token';

export async function loadToken(): Promise<string | null> {
  try {
    return await SecureStore.getItemAsync(TOKEN_KEY);
  } catch {
    // Unreadable keychain entry (e.g. restored backup on a new device): treat as signed out.
    return null;
  }
}

export async function saveToken(token: string): Promise<void> {
  await SecureStore.setItemAsync(TOKEN_KEY, token, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  });
}

export async function deleteToken(): Promise<void> {
  try {
    await SecureStore.deleteItemAsync(TOKEN_KEY);
  } catch {
    // Nothing stored / already gone.
  }
}
