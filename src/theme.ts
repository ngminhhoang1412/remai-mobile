import { Platform } from 'react-native';

// Light, Notion-like palette.
export const colors = {
  bg: '#FFFFFF',
  surface: '#F7F7F5',
  text: '#37352F',
  muted: '#787774',
  faint: '#A5A29C',
  border: '#E9E9E7',
  pressed: '#EFEFED',
  accent: '#2383E2',
  accentText: '#FFFFFF',
  danger: '#E03E3E',
  dangerBg: '#FDEBEC',
  codeBg: '#F2F1EE',
  backdrop: 'rgba(15, 15, 15, 0.35)',
} as const;

export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24 } as const;

export const radius = { sm: 4, md: 8, lg: 12 } as const;

export const monoFont = Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' });

export const fontSize = { small: 13, body: 16, h3: 19, h2: 23, h1: 30, title: 32 } as const;
