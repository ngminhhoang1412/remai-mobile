import * as Crypto from 'expo-crypto';

/** RFC 4122 v4 UUID for client-created block ids (kept by the server, see page-content spec). */
export function newId(): string {
  return Crypto.randomUUID();
}
