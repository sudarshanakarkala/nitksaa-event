import { getAccessToken } from '../auth/sessionStorage.js';
import { apiClient, BASE_URL } from './apiClient.js';

export function listAdminEvents({ page = 1, perPage = 100 } = {}) {
  const params = new URLSearchParams({ page, per_page: perPage });
  return apiClient.get(`/api/v1/events?${params}`);
}

export function listAdminAttendees(eventId, { search, batch_year, page = 1, per_page = 50 } = {}) {
  const params = new URLSearchParams({ page, per_page });
  if (search)      params.set('search',     search);
  if (batch_year)  params.set('batch_year', batch_year);
  return apiClient.get(`/api/v1/admin/events/${eventId}/attendees?${params}`);
}

export async function exportAttendeesCSV(eventId, { search, batch_year } = {}) {
  const params = new URLSearchParams();
  if (search)     params.set('search',     search);
  if (batch_year) params.set('batch_year', batch_year);
  const qs = params.toString() ? `?${params}` : '';

  const token   = getAccessToken();
  const headers = {
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };

  const response = await fetch(
    `${BASE_URL}/api/v1/admin/events/${eventId}/attendees/export${qs}`,
    { method: 'GET', headers },
  );

  if (!response.ok) {
    let message = `HTTP ${response.status}`;
    try {
      const data = await response.json();
      message = data.detail || message;
    } catch { /* non-JSON error */ }
    throw new Error(message);
  }

  return response.blob();
}

export function listAdminRegistrations(eventId, { status, page = 1, per_page = 50 } = {}) {
  const params = new URLSearchParams({ page, per_page });
  if (status) params.set('status', status);
  return apiClient.get(`/api/v1/admin/events/${eventId}/registrations?${params}`);
}
