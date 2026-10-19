import { ApiError, createApiClient } from '../api';

type FetchArgs = [string, RequestInit];

// Synthetic test values only.
const TEST_TOKEN = 'test-token';
const TEST_PW = 'p'.repeat(10);

function jsonResponse(status: number, body?: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => {
      if (body === undefined) throw new SyntaxError('no body');
      return body;
    },
  } as unknown as Response;
}

function setup(response: Response | Error, token: string | null = TEST_TOKEN) {
  const calls: FetchArgs[] = [];
  const onUnauthorized = jest.fn();
  const fetchImpl = jest.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    calls.push([String(url), init ?? {}]);
    if (response instanceof Error) throw response;
    return response;
  });
  const api = createApiClient({
    baseUrl: 'http://10.0.2.2:8080/',
    getToken: () => token,
    onUnauthorized,
    fetchImpl: fetchImpl as unknown as typeof fetch,
  });
  return { api, calls, onUnauthorized };
}

const headersOf = (init: RequestInit) => init.headers as Record<string, string>;

describe('API client', () => {
  test('authenticated requests send the bearer token to EXPO_PUBLIC_API_URL + /api/v1', async () => {
    const { api, calls } = setup(jsonResponse(200, { pages: [] }));
    await expect(api.listPages()).resolves.toEqual([]);
    const [url, init] = calls[0];
    expect(url).toBe('http://10.0.2.2:8080/api/v1/pages');
    expect(headersOf(init).Authorization).toBe(`Bearer ${TEST_TOKEN}`);
  });

  test('login sends no bearer token and a JSON body', async () => {
    const { api, calls } = setup(jsonResponse(200, { token: 't', user: { id: 'u' } }));
    await api.login('ada@example.com', TEST_PW);
    const [url, init] = calls[0];
    expect(url).toBe('http://10.0.2.2:8080/api/v1/auth/login');
    expect(init.method).toBe('POST');
    expect(headersOf(init).Authorization).toBeUndefined();
    expect(JSON.parse(init.body as string)).toEqual({ email: 'ada@example.com', password: TEST_PW });
  });

  test('error envelope is parsed into ApiError code and message', async () => {
    const { api } = setup(
      jsonResponse(400, { error: { code: 'invalid_parent', message: 'parentId is not a live page' } }),
    );
    const err = await api.createPage({ parentId: 'x' }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err).toMatchObject({ status: 400, code: 'invalid_parent', message: 'parentId is not a live page' });
  });

  test('a non-JSON error body still yields an ApiError', async () => {
    const { api } = setup(jsonResponse(500));
    await expect(api.listTrash()).rejects.toMatchObject({ status: 500, code: 'http_error' });
  });

  test('Token rejected: any API call returning 401 triggers the sign-out callback', async () => {
    const { api, onUnauthorized } = setup(
      jsonResponse(401, { error: { code: 'unauthorized', message: 'invalid token' } }),
    );
    await expect(api.getPage('p1')).rejects.toMatchObject({ status: 401, code: 'unauthorized' });
    expect(onUnauthorized).toHaveBeenCalledTimes(1);
    expect(onUnauthorized).toHaveBeenCalledWith(TEST_TOKEN);
  });

  test('Wrong credentials on login is an error, not a session expiry', async () => {
    const { api, onUnauthorized } = setup(
      jsonResponse(401, { error: { code: 'invalid_credentials', message: 'Invalid email or password.' } }),
      null,
    );
    await expect(api.login('a@b.co', TEST_PW)).rejects.toMatchObject({ code: 'invalid_credentials' });
    expect(onUnauthorized).not.toHaveBeenCalled();
  });

  test('network failure becomes ApiError status 0 without signing out', async () => {
    const { api, onUnauthorized } = setup(new TypeError('Network request failed'));
    await expect(api.me()).rejects.toMatchObject({ status: 0, code: 'network_error' });
    expect(onUnauthorized).not.toHaveBeenCalled();
  });

  test('Sign out: with no stored token, authenticated calls fail locally without a request', async () => {
    const { api, calls, onUnauthorized } = setup(jsonResponse(200, { pages: [] }), null);
    await expect(api.listPages()).rejects.toMatchObject({ status: 401, code: 'unauthorized' });
    expect(calls).toHaveLength(0);
    expect(onUnauthorized).not.toHaveBeenCalled();
  });

  test('204 responses resolve to undefined', async () => {
    const { api, calls } = setup(jsonResponse(204));
    await expect(api.deleteForever('p1')).resolves.toBeUndefined();
    expect(calls[0][0]).toBe('http://10.0.2.2:8080/api/v1/trash/p1');
    expect(calls[0][1].method).toBe('DELETE');
  });

  test('saveBlocks PUTs the whole ordered list with only BlockInput fields', async () => {
    const { api, calls } = setup(jsonResponse(200, { blocks: [], updatedAt: 'now' }));
    const blocks = [{ id: 'b1', type: 'todo' as const, text: 'Ship', checked: true }];
    await api.saveBlocks('p1', blocks);
    expect(calls[0][0]).toBe('http://10.0.2.2:8080/api/v1/pages/p1/blocks');
    expect(calls[0][1].method).toBe('PUT');
    expect(JSON.parse(calls[0][1].body as string)).toEqual({ blocks });
  });

  test('search encodes the query literally', async () => {
    const { api, calls } = setup(jsonResponse(200, { results: [] }));
    await api.search('100% & more');
    expect(calls[0][0]).toBe('http://10.0.2.2:8080/api/v1/search?q=100%25%20%26%20more');
  });
});
