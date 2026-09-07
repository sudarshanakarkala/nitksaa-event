/**
 * Regression tests for the admin unexpected-sign-out bug.
 *
 * Root cause (pre-fix): request() in apiClient.js treated `401 || 403`
 * identically — clearSession() + hard redirect to /login. Any 403 from
 * ordinary RBAC / event-scope denial destroyed a perfectly valid admin
 * session. There was also no attempt to recover an expired backend JWT
 * from the still-live Firebase sign-in.
 *
 * These tests lock in the corrected contract:
 *   - 403 / 404 / 409 / 422 / 5xx / network  → session KEPT, typed ApiError
 *   - 401 → try one silent Firebase refresh + replay; only sign out if that
 *           cannot recover the identity
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const getIdTokenMock = vi.fn();
const firebaseAuthStub = { currentUser: null };

vi.mock('firebase/auth', () => ({ getIdToken: (...args) => getIdTokenMock(...args) }));
vi.mock('../firebase', () => ({ auth: firebaseAuthStub }));

const TOKEN_KEY = 'nitksaa_event_admin_access_token';
const USER_KEY = 'nitksaa_event_admin_user';

let replaceSpy;
const realLocation = window.location;

function setLocation(pathname) {
  replaceSpy = vi.fn();
  delete window.location;
  window.location = { ...realLocation, pathname, replace: replaceSpy, assign: vi.fn() };
}

async function loadClient() {
  vi.resetModules();
  return import('./apiClient.js');
}

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  };
}

beforeEach(() => {
  localStorage.clear();
  localStorage.setItem(TOKEN_KEY, 'stale.backend.jwt');
  localStorage.setItem(USER_KEY, JSON.stringify({ email: 'admin@nitksaa.dev' }));
  firebaseAuthStub.currentUser = null;
  getIdTokenMock.mockReset();
  setLocation('/events');
  vi.stubGlobal('fetch', vi.fn());
});

afterEach(() => {
  vi.unstubAllGlobals();
  window.location = realLocation;
});

describe('successful request', () => {
  it('returns the body and keeps the session', async () => {
    fetch.mockResolvedValueOnce(jsonResponse(200, { events: [], total: 0 }));
    const { apiClient } = await loadClient();

    await expect(apiClient.get('/api/v1/events')).resolves.toEqual({ events: [], total: 0 });
    expect(localStorage.getItem(TOKEN_KEY)).toBe('stale.backend.jwt');
    expect(replaceSpy).not.toHaveBeenCalled();
  });
});

describe.each([
  [403, 'forbidden'],
  [404, 'not_found'],
  [409, 'conflict'],
  [422, 'validation'],
  [500, 'server'],
  [503, 'server'],
])('HTTP %i keeps the admin signed in', (status, category) => {
  it(`throws ApiError(category="${category}") without clearing the session`, async () => {
    fetch.mockResolvedValueOnce(jsonResponse(status, { detail: 'nope' }));
    const { apiClient, ApiError } = await loadClient();

    const err = await apiClient.post('/api/v1/events', { title: 'x' }).catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.status).toBe(status);
    expect(err.category).toBe(category);

    expect(localStorage.getItem(TOKEN_KEY)).toBe('stale.backend.jwt');
    expect(localStorage.getItem(USER_KEY)).not.toBeNull();
    expect(replaceSpy).not.toHaveBeenCalled();
    expect(fetch).toHaveBeenCalledTimes(1); // no retry for non-401
  });
});

describe('FastAPI 422 array detail is flattened', () => {
  it('turns [{loc,msg}] into a readable string and keeps the session', async () => {
    fetch.mockResolvedValueOnce(jsonResponse(422, {
      detail: [
        { loc: ['body', 'title'], msg: 'String should have at least 1 character' },
        { loc: ['body', 'end_datetime'], msg: 'Field required' },
      ],
    }));
    const { apiClient, ApiError } = await loadClient();

    const err = await apiClient.post('/api/v1/events', {}).catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.category).toBe('validation');
    expect(err.message).toBe(
      'title: String should have at least 1 character; end_datetime: Field required',
    );
    expect(localStorage.getItem(TOKEN_KEY)).toBe('stale.backend.jwt');
    expect(replaceSpy).not.toHaveBeenCalled();
  });
});

describe('network failure keeps the admin signed in', () => {
  it('throws ApiError(category="network") without clearing the session', async () => {
    fetch.mockRejectedValueOnce(new TypeError('Failed to fetch'));
    const { apiClient, ApiError } = await loadClient();

    const err = await apiClient.get('/api/v1/events').catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.category).toBe('network');
    expect(localStorage.getItem(TOKEN_KEY)).toBe('stale.backend.jwt');
    expect(replaceSpy).not.toHaveBeenCalled();
  });
});

describe('401 with no recoverable Firebase identity → fail closed', () => {
  it('clears the session and redirects to /login exactly once', async () => {
    firebaseAuthStub.currentUser = null; // nothing to refresh from
    fetch.mockResolvedValueOnce(jsonResponse(401, { detail: 'invalid_or_expired_token' }));
    const { apiClient, ApiError } = await loadClient();

    const err = await apiClient.get('/api/v1/events').catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err.category).toBe('auth');
    expect(localStorage.getItem(TOKEN_KEY)).toBeNull();
    expect(localStorage.getItem(USER_KEY)).toBeNull();
    expect(replaceSpy).toHaveBeenCalledWith('/login');
  });
});

describe('401 with a live Firebase session → silent recovery', () => {
  it('refreshes the backend JWT, replays the request, and stays signed in', async () => {
    firebaseAuthStub.currentUser = { uid: 'admin-uid' };
    getIdTokenMock.mockResolvedValueOnce('fresh.firebase.id.token');

    fetch
      // 1. original request — stale JWT rejected
      .mockResolvedValueOnce(jsonResponse(401, { detail: 'invalid_or_expired_token' }))
      // 2. POST /api/v1/auth/firebase — exchange refreshed Firebase token
      .mockResolvedValueOnce(jsonResponse(200, { access_token: 'new.backend.jwt' }))
      // 3. replayed original request — succeeds with the new JWT
      .mockResolvedValueOnce(jsonResponse(200, { events: [{ event_id: 1 }], total: 1 }));

    const { apiClient } = await loadClient();
    const result = await apiClient.get('/api/v1/events');

    expect(result).toEqual({ events: [{ event_id: 1 }], total: 1 });
    expect(localStorage.getItem(TOKEN_KEY)).toBe('new.backend.jwt');
    expect(replaceSpy).not.toHaveBeenCalled();
    expect(getIdTokenMock).toHaveBeenCalledWith({ uid: 'admin-uid' }, true);

    // The replayed (3rd) call must carry the new bearer token.
    const thirdCallHeaders = fetch.mock.calls[2][1].headers;
    expect(thirdCallHeaders.Authorization).toBe('Bearer new.backend.jwt');
  });

  it('signs out when the Firebase token can no longer be exchanged', async () => {
    firebaseAuthStub.currentUser = { uid: 'admin-uid' };
    getIdTokenMock.mockResolvedValueOnce('fresh.firebase.id.token');

    fetch
      .mockResolvedValueOnce(jsonResponse(401, { detail: 'invalid_or_expired_token' }))
      // exchange rejected — Firebase identity is genuinely gone/revoked
      .mockResolvedValueOnce(jsonResponse(401, { detail: 'invalid_firebase_token' }));

    const { apiClient } = await loadClient();
    const err = await apiClient.get('/api/v1/events').catch((e) => e);

    expect(err.category).toBe('auth');
    expect(localStorage.getItem(TOKEN_KEY)).toBeNull();
    expect(replaceSpy).toHaveBeenCalledWith('/login');
  });

  it('does not loop when the replayed request still returns 401', async () => {
    firebaseAuthStub.currentUser = { uid: 'admin-uid' };
    getIdTokenMock.mockResolvedValueOnce('fresh.firebase.id.token');

    fetch
      .mockResolvedValueOnce(jsonResponse(401, { detail: 'expired' }))       // original
      .mockResolvedValueOnce(jsonResponse(200, { access_token: 'new.jwt' })) // exchange ok
      .mockResolvedValueOnce(jsonResponse(401, { detail: 'still 401' }));    // replay still 401

    const { apiClient } = await loadClient();
    const err = await apiClient.get('/api/v1/events').catch((e) => e);

    expect(err.category).toBe('auth');
    expect(fetch).toHaveBeenCalledTimes(3); // original + exchange + one replay, then stop
    expect(replaceSpy).toHaveBeenCalledTimes(1);
  });
});

describe('redirect loop guard', () => {
  it('does not call location.replace when already on /login', async () => {
    setLocation('/login');
    firebaseAuthStub.currentUser = null;
    fetch.mockResolvedValueOnce(jsonResponse(401, { detail: 'expired' }));

    const { apiClient } = await loadClient();
    await apiClient.get('/api/v1/events').catch(() => {});

    expect(localStorage.getItem(TOKEN_KEY)).toBeNull(); // session still cleared
    expect(replaceSpy).not.toHaveBeenCalled();          // but no redirect thrash
  });
});

describe('skipAuth requests', () => {
  it('never attempt Firebase recovery and never redirect on 401', async () => {
    firebaseAuthStub.currentUser = { uid: 'admin-uid' };
    fetch.mockResolvedValueOnce(jsonResponse(401, { detail: 'expired' }));

    const { apiClient } = await loadClient();
    const err = await apiClient.get('/api/v1/health', { skipAuth: true }).catch((e) => e);

    expect(err.category).toBe('auth');
    expect(getIdTokenMock).not.toHaveBeenCalled();
    // a skipAuth 401 never triggers refresh, never clears the session, never redirects
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(localStorage.getItem(TOKEN_KEY)).toBe('stale.backend.jwt');
    expect(replaceSpy).not.toHaveBeenCalled();
  });
});
