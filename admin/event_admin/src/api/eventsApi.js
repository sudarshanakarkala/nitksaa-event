import { apiClient } from './apiClient.js';

export function listEvents({ page = 1, perPage = 20, status, isVirtual, search } = {}) {
  const params = new URLSearchParams({ page, per_page: perPage });
  if (status != null)    params.set('status',     status);
  if (isVirtual != null) params.set('is_virtual',  isVirtual);
  if (search)            params.set('search',      search);
  return apiClient.get(`/api/v1/events?${params}`);
}
