import { apiClient } from './apiClient.js';

// ── People ────────────────────────────────────────────────────────────────────

export function listPeople(eventId) {
  return apiClient.get(`/api/v1/events/${eventId}/people`);
}

export function createPerson(eventId, data) {
  return apiClient.post(`/api/v1/events/${eventId}/people`, data);
}

export function updatePerson(eventId, personId, data) {
  return apiClient.put(`/api/v1/events/${eventId}/people/${personId}`, data);
}

export function deletePerson(eventId, personId) {
  return apiClient.delete(`/api/v1/events/${eventId}/people/${personId}`);
}

// ── Sponsors ──────────────────────────────────────────────────────────────────

export function listSponsors(eventId) {
  return apiClient.get(`/api/v1/events/${eventId}/sponsors`);
}

export function createSponsor(eventId, data) {
  return apiClient.post(`/api/v1/events/${eventId}/sponsors`, data);
}

export function updateSponsor(eventId, sponsorId, data) {
  return apiClient.put(`/api/v1/events/${eventId}/sponsors/${sponsorId}`, data);
}

export function deleteSponsor(eventId, sponsorId) {
  return apiClient.delete(`/api/v1/events/${eventId}/sponsors/${sponsorId}`);
}

// ── Partners ──────────────────────────────────────────────────────────────────

export function listPartners(eventId) {
  return apiClient.get(`/api/v1/events/${eventId}/partners`);
}

export function createPartner(eventId, data) {
  return apiClient.post(`/api/v1/events/${eventId}/partners`, data);
}

export function updatePartner(eventId, partnerId, data) {
  return apiClient.put(`/api/v1/events/${eventId}/partners/${partnerId}`, data);
}

export function deletePartner(eventId, partnerId) {
  return apiClient.delete(`/api/v1/events/${eventId}/partners/${partnerId}`);
}
