import { getIdToken } from 'firebase/auth';
import { auth } from '../firebase';
import { getAccessToken, setAccessToken, clearSession } from '../auth/sessionStorage';

const BASE_URL = (import.meta.env.VITE_BACKEND_BASE_URL || 'http://localhost:8000').replace(/\/$/, '');

/**
 * Typed error for every non-OK backend response. `.message` stays the
 * human-readable string existing callers already render; `.status` and
 * `.category` let callers/UX branch without string-matching.
 *
 *   category: 'auth'       → 401, identity could not be recovered (session cleared)
 *             'forbidden'  → 403, authenticated but not permitted (session KEPT)
 *             'not_found'  → 404 (session KEPT)
 *             'conflict'   → 409 (session KEPT)
 *             'validation' → 422 (session KEPT)
 *             'server'     → 5xx (session KEPT)
 *             'network'    → transport failure (session KEPT)
 *             'error'      → any other non-OK status (session KEPT)
 */
export class ApiError extends Error {
  constructor(message, { status = null, category = 'error', detail = null } = {}) {
    super(message || `HTTP ${status ?? 'error'}`);
    this.name = 'ApiError';
    this.status = status;
    this.category = category;
    this.detail = detail;
  }
}

function categoryForStatus(status) {
  if (status === 401) return 'auth';
  if (status === 403) return 'forbidden';
  if (status === 404) return 'not_found';
  if (status === 409) return 'conflict';
  if (status === 422) return 'validation';
  if (status >= 500) return 'server';
  return 'error';
}

// Redirect to the login screen without stacking history entries or looping
// when we are already there.
function redirectToLogin() {
  if (window.location.pathname !== '/login') {
    window.location.replace('/login');
  }
}

// ── Silent session recovery ──────────────────────────────────────────────────
// A 401 means the stored backend JWT is missing/expired/invalid. Before we
// destroy the session we try once to recover it from the still-live Firebase
// sign-in: force-refresh the Firebase ID token and re-exchange it for a fresh
// backend JWT. Done inline (not via authApi) to avoid an import cycle.
// Concurrent 401s share a single in-flight refresh.
let refreshInFlight = null;

async function doRefreshBackendToken() {
  const fbUser = auth.currentUser;
  if (!fbUser) return null;

  let firebaseIdToken;
  try {
    firebaseIdToken = await getIdToken(fbUser, /* forceRefresh */ true);
  } catch {
    return null;
  }

  let response;
  try {
    response = await fetch(`${BASE_URL}/api/v1/auth/firebase`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: firebaseIdToken }),
    });
  } catch {
    return null; // network — caller keeps the session and surfaces a network error
  }
  if (!response.ok) return null;

  let data;
  try {
    data = await response.json();
  } catch {
    return null;
  }
  if (!data?.access_token) return null;

  setAccessToken(data.access_token);
  return data.access_token;
}

export function refreshBackendToken() {
  if (!refreshInFlight) {
    refreshInFlight = doRefreshBackendToken().finally(() => { refreshInFlight = null; });
  }
  return refreshInFlight;
}

// ── Core request ────────────────────────────────────────────────────────────
async function request(path, options = {}, _retried = false) {
  const { skipAuth = false, ...fetchOptions } = options;

  const token = skipAuth ? null : getAccessToken();
  const headers = {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...fetchOptions.headers,
  };

  let response;
  try {
    response = await fetch(`${BASE_URL}${path}`, { ...fetchOptions, headers });
  } catch {
    throw new ApiError(
      `Network error: cannot reach backend at ${BASE_URL}. Is it running?`,
      { category: 'network' },
    );
  }

  // 401 — attempt one silent recovery, then replay the original request once.
  if (response.status === 401 && !skipAuth && !_retried) {
    const newToken = await refreshBackendToken();
    if (newToken) return request(path, options, /* _retried */ true);
  }

  // 401 that could not be recovered — the identity is genuinely gone.
  // This is the ONLY path that clears the session. skipAuth calls are
  // unauthenticated by construction, so a 401 there never touches the session.
  if (response.status === 401) {
    if (!skipAuth) {
      clearSession();
      redirectToLogin();
    }
    throw new ApiError('Your session has expired. Please sign in again.', {
      status: 401,
      category: 'auth',
    });
  }

  // Every other non-OK status (403/404/409/422/5xx/…): the session is still
  // valid. Surface a typed error — never sign the admin out here.
  if (!response.ok) {
    let detail = null;
    try {
      const data = await response.json();
      detail = data.detail ?? data.message ?? null;
      if (Array.isArray(detail)) {
        // FastAPI 422 shape: [{loc:[...], msg:"..."}] → "field: message; …"
        detail = detail
          .map((e) => {
            const field = Array.isArray(e?.loc) ? e.loc[e.loc.length - 1] : null;
            return field ? `${field}: ${e.msg}` : e?.msg;
          })
          .filter(Boolean)
          .join('; ') || null;
      }
    } catch { /* non-JSON error body */ }
    const status = response.status;
    const fallback =
      status === 403 ? 'You do not have permission to perform this action.'
      : `HTTP ${status}`;
    throw new ApiError(detail || fallback, {
      status,
      category: categoryForStatus(status),
      detail,
    });
  }

  if (response.status === 204) return null;
  return response.json();
}

export const apiClient = {
  get:    (path, opts)       => request(path, { ...opts, method: 'GET' }),
  post:   (path, body, opts) => request(path, { ...opts, method: 'POST',  body: JSON.stringify(body) }),
  put:    (path, body, opts) => request(path, { ...opts, method: 'PUT',   body: JSON.stringify(body) }),
  patch:  (path, body, opts) => request(path, { ...opts, method: 'PATCH', body: JSON.stringify(body) }),
  delete: (path, opts)       => request(path, { ...opts, method: 'DELETE' }),
};

export { BASE_URL };
