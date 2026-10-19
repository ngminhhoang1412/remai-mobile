import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';

import { createApiClient, isApiError, type ApiClient } from '@/lib/api';
import { API_URL } from '@/lib/config';
import { deleteToken, loadToken, saveToken } from '@/lib/tokenStorage';
import type { User } from '@/lib/types';

/**
 * - `loading`: reading the stored token / checking it with GET /auth/me
 * - `unreachable`: a token is stored but the server couldn't be reached to check it
 */
export type SessionStatus = 'loading' | 'signedOut' | 'signedIn' | 'unreachable';

interface SessionValue {
  status: SessionStatus;
  user: User | null;
  api: ApiClient;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, name: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  retryLaunchCheck: () => void;
}

const SessionContext = createContext<SessionValue | null>(null);

export function SessionProvider({ children }: Readonly<{ children: ReactNode }>) {
  const [status, setStatus] = useState<SessionStatus>('loading');
  const [user, setUser] = useState<User | null>(null);
  const tokenRef = useRef<string | null>(null);

  // Drop the session locally: forget the token in memory first so nothing sends it again.
  const clearSession = useCallback(async () => {
    tokenRef.current = null;
    setUser(null);
    setStatus('signedOut');
    await deleteToken();
  }, []);

  const api = useMemo(
    () =>
      createApiClient({
        baseUrl: API_URL,
        getToken: () => tokenRef.current,
        onUnauthorized: (tokenUsed) => {
          // Ignore a late 401 for a token that has already been replaced by a new sign-in.
          if (tokenUsed !== null && tokenUsed !== tokenRef.current) return;
          void clearSession();
        },
      }),
    [clearSession],
  );

  const checkStoredToken = useCallback(async () => {
    setStatus('loading');
    const token = await loadToken();
    if (!token) {
      setStatus('signedOut');
      return;
    }
    tokenRef.current = token;
    try {
      const me = await api.me();
      setUser(me);
      setStatus('signedIn');
    } catch (e) {
      // 401 already cleared the session via onUnauthorized.
      if (isApiError(e) && e.status === 401) return;
      setStatus('unreachable');
    }
  }, [api]);

  useEffect(() => {
    void checkStoredToken();
  }, [checkStoredToken]);

  const startSession = useCallback(async (token: string, u: User) => {
    await saveToken(token);
    tokenRef.current = token;
    setUser(u);
    setStatus('signedIn');
  }, []);

  const value = useMemo<SessionValue>(
    () => ({
      status,
      user,
      api,
      signIn: async (email, password) => {
        const res = await api.login(email.trim(), password);
        await startSession(res.token, res.user);
      },
      signUp: async (email, name, password) => {
        const res = await api.register(email.trim(), name.trim(), password);
        await startSession(res.token, res.user);
      },
      signOut: clearSession,
      retryLaunchCheck: () => {
        void checkStoredToken();
      },
    }),
    [status, user, api, startSession, clearSession, checkStoredToken],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionValue {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error('useSession must be used inside SessionProvider');
  return ctx;
}
