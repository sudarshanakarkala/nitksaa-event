import { getAccessToken, clearSession } from '../auth/sessionStorage';

const BASE_URL = (import.meta.env.VITE_BACKEND_BASE_URL || 'http://localhost:8000').replace(/\/$/, '');

async function request(path, options = {}) {
  const { skipAuth = false, ...fetchOptions } = options;

  const token = skipAuth ? null : getAccessToken();
  const devUser = import.meta.env.VITE_DEV_USER;
  const headers = {
    'Content-Type': 'application/json',
    ...(token   ? { Authorization: `Bearer ${token}` } : {}),
    ...(devUser ? { 'X-Dev-User': devUser }            : {}),
    ...fetchOptions.headers,
  };

  let response;
  try {
    response = await fetch(`${BASE_URL}${path}`, { ...fetchOptions, headers });
  } catch {
    throw new Error(`Network error: cannot reach backend at ${BASE_URL}. Is it running?`);
  }

  if (response.status === 401 || response.status === 403) {
    clearSession();
    window.location.replace('/login');
    throw new Error('Session expired. Please log in again.');
  }

  if (!response.ok) {
    let message = `HTTP ${response.status}`;
    try {
      const data = await response.json();
      message = data.detail || data.message || message;
    } catch { /* non-JSON error body */ }
    throw new Error(message);
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
