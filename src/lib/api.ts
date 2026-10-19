import type {
  AuthResponse,
  Block,
  CreatePageInput,
  Page,
  PageWithBlocks,
  SaveBlocksResponse,
  SearchResult,
  TrashedPage,
  UpdatePageInput,
  User,
} from './types';

/**
 * Error raised for every failed API call. `status` is the HTTP status (0 for a
 * network failure) and `code` is the envelope's snake_case code
 * (`{"error":{"code","message"}}`), or a client-side code when the server sent none.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
  }
}

export function isApiError(e: unknown): e is ApiError {
  return e instanceof ApiError;
}

/** A user-facing message for any thrown value. */
export function errorMessage(e: unknown): string {
  if (isApiError(e)) return e.message;
  if (e instanceof Error && e.message) return e.message;
  return 'Something went wrong.';
}

export interface ApiClientOptions {
  baseUrl: string;
  /** Returns the current session token, or null when signed out. */
  getToken: () => string | null;
  /**
   * Called when an authenticated request gets 401: the session must be discarded. Receives the
   * token that request used, so a late 401 for an old token can be ignored after a new sign-in.
   */
  onUnauthorized: (tokenUsed: string | null) => void;
  fetchImpl?: typeof fetch;
}

type Method = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';

interface RequestOptions {
  body?: unknown;
  /** False for register/login: no bearer header, and a 401 there is not a session expiry. */
  auth?: boolean;
}

async function parseError(res: Response): Promise<ApiError> {
  let code = 'http_error';
  let message = `Request failed (${res.status}).`;
  try {
    const data = (await res.json()) as { error?: { code?: unknown; message?: unknown } };
    if (data && data.error && typeof data.error.code === 'string') {
      code = data.error.code;
      if (typeof data.error.message === 'string' && data.error.message) message = data.error.message;
    }
  } catch {
    // Non-JSON body (proxy error page, empty body...): keep the generic message.
  }
  return new ApiError(res.status, code, message);
}

export function createApiClient(opts: ApiClientOptions) {
  const baseUrl = opts.baseUrl.replace(/\/+$/, '');
  const doFetch = opts.fetchImpl ?? ((input: RequestInfo | URL, init?: RequestInit) => fetch(input, init));

  async function request<T>(method: Method, path: string, { body, auth = true }: RequestOptions = {}): Promise<T> {
    const headers: Record<string, string> = { Accept: 'application/json' };
    const token = auth ? opts.getToken() : null;
    // Signed out: never hit the network for an authenticated endpoint.
    if (auth && !token) throw new ApiError(401, 'unauthorized', 'You are signed out.');
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;

    let res: Response;
    try {
      res = await doFetch(`${baseUrl}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ApiError(0, 'network_error', "Can't reach the server. Check your connection.");
    }

    if (!res.ok) {
      const err = await parseError(res);
      if (res.status === 401 && auth) opts.onUnauthorized(token);
      throw err;
    }
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }

  const enc = encodeURIComponent;

  return {
    register: (email: string, name: string, password: string) =>
      request<AuthResponse>('POST', '/api/v1/auth/register', { body: { email, name, password }, auth: false }),
    login: (email: string, password: string) =>
      request<AuthResponse>('POST', '/api/v1/auth/login', { body: { email, password }, auth: false }),
    me: () => request<User>('GET', '/api/v1/auth/me'),

    listPages: async () => (await request<{ pages: Page[] }>('GET', '/api/v1/pages')).pages,
    createPage: (input: CreatePageInput = {}) => request<Page>('POST', '/api/v1/pages', { body: input }),
    getPage: (id: string) => request<PageWithBlocks>('GET', `/api/v1/pages/${enc(id)}`),
    updatePage: (id: string, input: UpdatePageInput) =>
      request<Page>('PATCH', `/api/v1/pages/${enc(id)}`, { body: input }),
    trashPage: (id: string) => request<void>('DELETE', `/api/v1/pages/${enc(id)}`),
    saveBlocks: (id: string, blocks: Block[]) =>
      request<SaveBlocksResponse>('PUT', `/api/v1/pages/${enc(id)}/blocks`, {
        body: { blocks: blocks.map(({ id: bid, type, text, checked }) => ({ id: bid, type, text, checked })) },
      }),

    search: async (q: string) =>
      (await request<{ results: SearchResult[] }>('GET', `/api/v1/search?q=${enc(q)}`)).results,

    listTrash: async () => (await request<{ pages: TrashedPage[] }>('GET', '/api/v1/trash')).pages,
    restorePage: (id: string) => request<Page>('POST', `/api/v1/trash/${enc(id)}/restore`),
    deleteForever: (id: string) => request<void>('DELETE', `/api/v1/trash/${enc(id)}`),
  };
}

export type ApiClient = ReturnType<typeof createApiClient>;
