import { apiClient, BASE_URL } from './apiClient';

export async function healthCheck() {
  return apiClient.get('/api/v1/health');
}

export async function exchangeFirebaseToken(firebaseIdToken) {
  // Uses fetch directly — we must NOT attach any stored backend JWT as Authorization header,
  // and we must NOT trigger the 401 redirect that apiClient adds for expired sessions.
  let response;
  try {
    response = await fetch(`${BASE_URL}/api/v1/auth/firebase`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: firebaseIdToken }),
    });
  } catch {
    throw new Error(`Network error: cannot reach backend at ${BASE_URL}. Is it running?`);
  }

  if (!response.ok) {
    let message = `HTTP ${response.status}`;
    try {
      const data = await response.json();
      message = data.detail || data.message || message;
    } catch { /* non-JSON error body */ }
    throw new Error(`Backend auth failed: ${message}`);
  }

  const data = await response.json();
  if (!data.access_token) {
    throw new Error('Backend did not return an access token.');
  }
  return data;
}

export async function getCurrentUser() {
  return apiClient.get('/api/v1/auth/me');
}
