import { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import StatusBadge from '../components/StatusBadge';
import LoadingView from '../components/LoadingView';
import ConfirmDialog from '../components/ConfirmDialog';
import { listEvents, updateEventStatus } from '../api/eventsApi';
import '../styles/events.css';

// ── Status filter definitions ──────────────────────────────────────────────
const STATUS_FILTERS = [
  { label: 'All',               value: 'all',               match: null },
  { label: 'Draft',             value: 'draft',             match: ['draft'] },
  { label: 'Published',         value: 'published',         match: ['published'] },
  { label: 'Registration Open', value: 'registration_open', match: ['registration_open'] },
  { label: 'Cancelled',         value: 'cancelled',         match: ['cancelled'] },
  { label: 'Archived',          value: 'archived',          match: ['archived', 'completed'] },
];

// Which action buttons are enabled for a given event status
function getActions(status) {
  const s = status?.toLowerCase();
  return {
    canPublish:   s === 'draft',
    canUnpublish: s === 'published',
    canEdit:      s === 'draft' || s === 'published' || s === 'registration_open',
    canCancel:    s === 'draft' || s === 'published' || s === 'registration_open',
  };
}

// Turn backend error strings into human-readable messages
function friendlyError(msg) {
  if (!msg) return 'An unexpected error occurred.';
  if (msg.startsWith('invalid_status_transition')) {
    const [from, to] = msg.replace('invalid_status_transition_', '').split('_to_');
    if (from && to) return `Cannot change from "${from}" to "${to}". Please refresh the list.`;
  }
  if (msg.startsWith('missing_fields_for_publish')) {
    return `Cannot publish: missing required fields — ${msg.replace('missing_fields_for_publish: ', '')}.`;
  }
  if (msg === 'event_not_found') return 'Event not found — it may have been deleted.';
  if (msg === 'event_not_editable') return 'This event cannot be edited in its current status.';
  return msg;
}

function formatDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: true,
  });
}

function matchesSearch(event, query) {
  if (!query) return true;
  const q = query.toLowerCase();
  return [event.title, event.tagline, event.description, event.location_text]
    .some(field => field?.toLowerCase().includes(q));
}

export default function EventsPage() {
  // ── List state ─────────────────────────────────────────────────────────
  const [events,       setEvents]       = useState([]);
  const [total,        setTotal]        = useState(0);
  const [loading,      setLoading]      = useState(true);
  const [error,        setError]        = useState(null);
  const [statusFilter, setStatusFilter] = useState('all');
  const [search,       setSearch]       = useState('');
  const searchRef = useRef(null);

  // ── Status action state ────────────────────────────────────────────────
  const [confirmState, setConfirmState] = useState(null); // { eventId, eventTitle, status }
  const [actioningId,  setActioningId]  = useState(null); // event_id currently being updated
  const [dialogError,  setDialogError]  = useState(null);
  const [toast,        setToast]        = useState(null);  // { msg, type }
  const toastRef = useRef(null);

  // ── Data fetching ──────────────────────────────────────────────────────
  function fetchEvents() {
    setLoading(true);
    setError(null);
    listEvents()
      .then(data => {
        setEvents(data.events ?? []);
        setTotal(data.total ?? 0);
      })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }

  useEffect(() => { fetchEvents(); }, []);

  // ── Toast helpers ──────────────────────────────────────────────────────
  function showToast(msg, type = 'success') {
    setToast({ msg, type });
    clearTimeout(toastRef.current);
    toastRef.current = setTimeout(() => setToast(null), 3500);
  }

  // ── Confirmation dialog ────────────────────────────────────────────────
  function openConfirm(event, targetStatus) {
    setDialogError(null);
    setConfirmState({ eventId: event.event_id, eventTitle: event.title, status: targetStatus });
  }

  async function handleStatusConfirm() {
    if (!confirmState) return;
    const { eventId, status } = confirmState;
    setActioningId(eventId);
    setDialogError(null);
    try {
      await updateEventStatus(eventId, status);
      setConfirmState(null);
      const label = status === 'published' ? 'published'
                  : status === 'draft'     ? 'moved to draft'
                  :                          'cancelled';
      showToast(`Event ${label} successfully.`);
      fetchEvents(); // statusFilter + search remain in state — list re-filters automatically
    } catch (err) {
      setDialogError(friendlyError(err.message));
    } finally {
      setActioningId(null);
    }
  }

  // ── Client-side filtering ──────────────────────────────────────────────
  const filteredEvents = useMemo(() => {
    const filter = STATUS_FILTERS.find(f => f.value === statusFilter);
    const q = search.trim();
    return events.filter(ev => {
      const matchStatus = !filter?.match || filter.match.includes(ev.status);
      return matchStatus && matchesSearch(ev, q);
    });
  }, [events, statusFilter, search]);

  const isFiltered = search.trim() !== '' || statusFilter !== 'all';
  const countLabel = !loading && !error
    ? (isFiltered
        ? `Showing ${filteredEvents.length} of ${total} event${total !== 1 ? 's' : ''}`
        : `${total} event${total !== 1 ? 's' : ''}`)
    : '';

  return (
    <div>
      <p className="page-eyebrow">Week 2</p>
      <h1 className="page-heading">Events</h1>
      <p className="page-sub">Manage and monitor all NITKSAA events.</p>

      {/* ── Toolbar ──────────────────────────────────────────────────── */}
      <div className="events-toolbar-wrap">

        {/* Row 1: status filter pills + Create Event button */}
        <div className="events-filters-row">
          <div className="events-filters">
            {STATUS_FILTERS.map(f => (
              <button
                key={f.value}
                className={`events-filter-btn${statusFilter === f.value ? ' events-filter-btn--active' : ''}`}
                onClick={() => setStatusFilter(f.value)}
              >
                {f.label}
              </button>
            ))}
          </div>

          <Link className="btn btn-primary" to="/events/new">
            + Create Event
          </Link>
        </div>

        {/* Row 2: search input + event count + refresh */}
        <div className="events-search-row">
          <div className="events-search-wrap">
            <IconSearch className="events-search-icon" />
            <input
              ref={searchRef}
              type="search"
              className="events-search-input"
              placeholder="Search events…"
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
            {search && (
              <button
                className="events-search-clear"
                onClick={() => { setSearch(''); searchRef.current?.focus(); }}
                title="Clear search"
                aria-label="Clear search"
              >
                <IconX />
              </button>
            )}
          </div>

          <span className="events-count">{countLabel}</span>

          <button className="btn btn-ghost" onClick={fetchEvents} disabled={loading}>
            ↻ Refresh
          </button>
        </div>
      </div>

      {/* ── Toast notification ────────────────────────────────────────── */}
      {toast && (
        <div className={`events-toast notice notice--${toast.type === 'error' ? 'warning' : 'success'} fade-up`}>
          <span>{toast.msg}</span>
          <button
            className="events-toast-close"
            onClick={() => setToast(null)}
            aria-label="Dismiss notification"
          >✕</button>
        </div>
      )}

      {/* ── States ───────────────────────────────────────────────────── */}
      {loading && <LoadingView message="Loading events…" />}

      {!loading && error && (
        <p className="error-msg">{error}</p>
      )}

      {!loading && !error && filteredEvents.length === 0 && (
        <div className="empty-state fade-up">
          {events.length === 0 ? (
            <>
              <p>No events found.</p>
              <p style={{ marginTop: 8, fontSize: '0.8rem' }}>
                Create your first event to get started.
              </p>
            </>
          ) : (
            <p>No events match your current filter.</p>
          )}
        </div>
      )}

      {/* ── Table ────────────────────────────────────────────────────── */}
      {!loading && !error && filteredEvents.length > 0 && (
        <div className="events-table-wrap fade-up">
          <table className="events-table">
            <thead>
              <tr>
                <th>Title</th>
                <th>Status</th>
                <th>Event Type</th>
                <th>Capacity</th>
                <th>Start Date</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredEvents.map(event => {
                const acts       = getActions(event.status);
                const isActioning = actioningId === event.event_id;
                return (
                  <tr key={event.event_id}>
                    <td>
                      <div className="event-title-cell">
                        <span className="event-title">{event.title}</span>
                        {event.tagline && (
                          <span className="event-tagline">{event.tagline}</span>
                        )}
                      </div>
                    </td>
                    <td>
                      <StatusBadge status={event.status} />
                    </td>
                    <td>{event.is_virtual ? 'Virtual' : 'In-person'}</td>
                    <td className="capacity-cell">
                      {event.capacity == null
                        ? 'Unlimited'
                        : `${event.registered_count ?? 0} / ${event.capacity}`}
                    </td>
                    <td className="date-cell">{formatDate(event.start_datetime)}</td>
                    <td>
                      <div className="actions-cell">
                        <button className="btn btn-ghost btn-xs" disabled title="Coming soon">
                          View
                        </button>

                        {acts.canEdit ? (
                          <Link
                            className="btn btn-ghost btn-xs"
                            to={`/events/${event.event_id}/edit`}
                          >Edit</Link>
                        ) : (
                          <button className="btn btn-ghost btn-xs" disabled>Edit</button>
                        )}

                        <button
                          className="btn btn-ghost btn-xs"
                          disabled={!acts.canPublish || isActioning}
                          onClick={() => openConfirm(event, 'published')}
                        >Publish</button>

                        <button
                          className="btn btn-ghost btn-xs"
                          disabled={!acts.canUnpublish || isActioning}
                          onClick={() => openConfirm(event, 'draft')}
                        >Unpublish</button>

                        <button
                          className="btn btn-danger btn-xs"
                          disabled={!acts.canCancel || isActioning}
                          onClick={() => openConfirm(event, 'cancelled')}
                        >{isActioning ? '…' : 'Cancel'}</button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* ── Confirmation dialog (portal-like, fixed overlay) ─────────── */}
      <ConfirmDialog
        data={confirmState}
        loading={!!actioningId}
        error={dialogError}
        onClose={() => { setConfirmState(null); setDialogError(null); }}
        onConfirm={handleStatusConfirm}
      />
    </div>
  );
}

function IconSearch({ className }) {
  return (
    <svg className={className} width="15" height="15" viewBox="0 0 24 24"
      fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
    </svg>
  );
}

function IconX() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24"
      fill="none" stroke="currentColor" strokeWidth="2.5"
      strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 6 6 18M6 6l12 12" />
    </svg>
  );
}
