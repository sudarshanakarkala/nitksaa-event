import { useEffect, useState } from 'react';
import StatusBadge from '../components/StatusBadge';
import LoadingView from '../components/LoadingView';
import {
  listAdminEvents,
  listAdminRegistrations,
} from '../api/attendeesApi';
import '../styles/attendees.css';

const STATUS_FILTERS = [
  { label: 'All',        value: '' },
  { label: 'Registered', value: 'registered' },
  { label: 'Cancelled',  value: 'cancelled' },
];

function formatDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: true,
  });
}

export default function RegistrationsPage() {
  const [events,          setEvents]         = useState([]);
  const [eventsLoading,   setEventsLoading]  = useState(true);
  const [selectedEventId, setSelectedEventId] = useState('');
  const [statusFilter,    setStatusFilter]   = useState('');
  const [page,            setPage]           = useState(1);
  const perPage = 50;

  const [registrations, setRegistrations] = useState([]);
  const [total,         setTotal]         = useState(0);
  const [loading,       setLoading]       = useState(false);
  const [error,         setError]         = useState(null);

  // Load events list on mount
  useEffect(() => {
    setEventsLoading(true);
    listAdminEvents()
      .then(data => setEvents(data.events ?? []))
      .catch(() => setEvents([]))
      .finally(() => setEventsLoading(false));
  }, []);

  // Load registrations when event or filters change
  useEffect(() => {
    if (!selectedEventId) return;
    setLoading(true);
    setError(null);
    listAdminRegistrations(selectedEventId, {
      status:   statusFilter || undefined,
      page,
      per_page: perPage,
    })
      .then(data => {
        setRegistrations(data.registrations ?? []);
        setTotal(data.total ?? 0);
      })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }, [selectedEventId, statusFilter, page]);

  function handleEventChange(e) {
    setSelectedEventId(e.target.value);
    setStatusFilter('');
    setPage(1);
  }

  function handleStatusFilter(value) {
    setStatusFilter(value);
    setPage(1);
  }

  const totalPages = Math.max(1, Math.ceil(total / perPage));
  const startRow   = total === 0 ? 0 : (page - 1) * perPage + 1;
  const endRow     = Math.min(page * perPage, total);

  return (
    <div>
      <p className="page-eyebrow">Week 4</p>
      <h1 className="page-heading">Registrations</h1>
      <p className="page-sub">Audit view — all registration statuses including cancelled.</p>

      {/* ── Toolbar ────────────────────────────────────────────────────── */}
      <div className="att-toolbar">

        {/* Row 1: event selector */}
        <div className="att-toolbar-row">
          <select
            className="att-event-select"
            value={selectedEventId}
            onChange={handleEventChange}
            disabled={eventsLoading}
          >
            <option value="">{eventsLoading ? 'Loading events…' : '— Select an event —'}</option>
            {events.map(e => (
              <option key={e.event_id} value={e.event_id}>
                {e.title} ({e.status})
              </option>
            ))}
          </select>
        </div>

        {/* Row 2: status filter pills + count */}
        {selectedEventId && (
          <div className="att-toolbar-row">
            <div className="att-filter-pills">
              {STATUS_FILTERS.map(f => (
                <button
                  key={f.value}
                  className={`att-filter-pill${statusFilter === f.value ? ' att-filter-pill--active' : ''}`}
                  onClick={() => handleStatusFilter(f.value)}
                >
                  {f.label}
                </button>
              ))}
            </div>

            {!loading && !error && (
              <span className="att-count-label">
                {total === 0 ? 'No registrations' : `${startRow}–${endRow} of ${total}`}
              </span>
            )}
          </div>
        )}
      </div>

      {/* ── No event selected ──────────────────────────────────────────── */}
      {!selectedEventId && (
        <div className="att-select-prompt fade-up">
          <div className="att-select-prompt-icon">📋</div>
          <p>Select an event above to view its registrations.</p>
        </div>
      )}

      {/* ── Loading / error states ─────────────────────────────────────── */}
      {selectedEventId && loading && <LoadingView message="Loading registrations…" />}
      {selectedEventId && !loading && error && <p className="error-msg">{error}</p>}

      {/* ── Empty state ────────────────────────────────────────────────── */}
      {selectedEventId && !loading && !error && registrations.length === 0 && (
        <div className="empty-state fade-up">
          <p>{statusFilter ? `No ${statusFilter} registrations.` : 'No registrations for this event.'}</p>
        </div>
      )}

      {/* ── Registrations table ────────────────────────────────────────── */}
      {selectedEventId && !loading && !error && registrations.length > 0 && (
        <div className="att-table-wrap fade-up">
          <table className="att-table">
            <thead>
              <tr>
                <th>Registration #</th>
                <th>Name</th>
                <th>Status</th>
                <th>Registered At</th>
                <th>Cancelled At</th>
              </tr>
            </thead>
            <tbody>
              {registrations.map(r => (
                <tr key={r.registration_id}>
                  <td className="att-cell-mono">{r.registration_number || '—'}</td>
                  <td>
                    <div className="att-cell-name">{r.fullname_snapshot || '—'}</div>
                    {r.email_snapshot && (
                      <div className="att-cell-muted">{r.email_snapshot}</div>
                    )}
                  </td>
                  <td><StatusBadge status={r.status} /></td>
                  <td className="att-cell-muted">{formatDate(r.registered_at)}</td>
                  <td className="att-cell-muted">{r.cancelled_at ? formatDate(r.cancelled_at) : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* ── Pagination ─────────────────────────────────────────────────── */}
      {selectedEventId && !loading && !error && total > perPage && (
        <div className="att-pagination fade-up">
          <span className="att-pagination-info">
            Page {page} of {totalPages} — {total} total registration{total !== 1 ? 's' : ''}
          </span>
          <div className="att-pagination-btns">
            <button
              className="btn btn-ghost btn-xs"
              disabled={page <= 1}
              onClick={() => setPage(p => p - 1)}
            >
              ← Prev
            </button>
            <button
              className="btn btn-ghost btn-xs"
              disabled={page >= totalPages}
              onClick={() => setPage(p => p + 1)}
            >
              Next →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
