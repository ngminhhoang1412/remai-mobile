// EXPO_PUBLIC_* variables are inlined at bundle time, so this must be a literal
// `process.env.EXPO_PUBLIC_API_URL` access (no destructuring / dynamic keys).
const fromEnv = process.env.EXPO_PUBLIC_API_URL;

/**
 * Base URL of remai-backend, without a trailing slash. Set EXPO_PUBLIC_API_URL in .env
 * (Android emulator: http://10.0.2.2:8080, physical device: http://<PC LAN IP>:8080).
 */
export const API_URL = (fromEnv && fromEnv.trim() !== '' ? fromEnv.trim() : 'http://localhost:8080').replace(
  /\/+$/,
  '',
);
