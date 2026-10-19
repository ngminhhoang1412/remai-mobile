// Wire types mirroring remai-central-specs/docs/api/openapi.yaml (camelCase JSON).

export type BlockType =
  | 'paragraph'
  | 'heading1'
  | 'heading2'
  | 'heading3'
  | 'todo'
  | 'bulleted'
  | 'numbered'
  | 'quote'
  | 'code'
  | 'divider';

export interface User {
  id: string;
  email: string;
  name: string;
  createdAt: string;
}

export interface AuthResponse {
  token: string;
  user: User;
}

export interface Page {
  id: string;
  parentId: string | null;
  title: string;
  icon: string;
  createdAt: string;
  updatedAt: string;
}

export interface Block {
  id: string;
  type: BlockType;
  text: string;
  checked: boolean;
}

export interface PageWithBlocks extends Page {
  blocks: Block[];
}

export interface SaveBlocksResponse {
  blocks: Block[];
  updatedAt: string;
}

export interface TrashedPage {
  id: string;
  title: string;
  icon: string;
  trashedAt: string;
}

export interface SearchResult {
  id: string;
  parentId: string | null;
  title: string;
  icon: string;
  snippet: string;
}

export interface CreatePageInput {
  title?: string;
  icon?: string;
  parentId?: string | null;
}

export interface UpdatePageInput {
  title?: string;
  icon?: string;
  parentId?: string | null;
}

/** Shows an empty (or whitespace-only) page title as "Untitled" (page-management spec). */
export function displayTitle(title: string | null | undefined): string {
  return title && title.trim() !== '' ? title : 'Untitled';
}
