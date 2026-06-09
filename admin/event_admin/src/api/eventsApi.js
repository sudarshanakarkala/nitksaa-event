import { apiClient } from './apiClient.js';

export function listEvents({ page = 1, perPage = 20, status, isVirtual, search } = {}) {
  const params = new URLSearchParams({ page, per_page: perPage });
  if (status != null)    params.set('status',     status);
  if (isVirtual != null) params.set('is_virtual',  isVirtual);
  if (search)            params.set('search',      search);
  return apiClient.get(`/api/v1/events?${params}`);
}

export function getEvent(eventId) {
  return apiClient.get(`/api/v1/events/${eventId}`);
}

export function createEvent(data) {
  return apiClient.post('/api/v1/events', data);
}

export function updateEvent(eventId, data) {
  return apiClient.patch(`/api/v1/events/${eventId}`, data);
}

export function updateEventStatus(eventId, status) {
  return apiClient.patch(`/api/v1/events/${eventId}/status`, { status });
}
