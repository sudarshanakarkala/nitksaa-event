import { useEffect, useRef, useState } from 'react';
import Card from '../components/Card';
import StatusBadge from '../components/StatusBadge';
import LoadingView from '../components/LoadingView';
import {
  listAdminEvents,
  listAdminAttendees,
  exportAttendeesCSV,
} from '../api/attendeesApi';
import '../styles/attendees.css';

const BATCH_YEAR_OPTIONS = (() => {
  const current = new Date().getFullYear();
  const years = [];
  for (let y = current; y >= 1960; y--) years.push(y);
  return years;
})();

function formatDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: true,
  });
}

function EmailStatusCell({ status }) {
  const dotClass = {
    sent:    'att-email-dot--sent',
    failed:  'att-email-dot--failed',
    pending: 'att-email-dot--pending',
    skipped: 'att-email-dot--skipped',
  }[status?.toLowerCase()] ?? 'att-email-dot--skipped';
  return (
    <span className="att-email-status">
      <span className={`att-email-dot ${dotClass}`} />
      {status || '—'}
    </span>
  );
}

function SummaryCard({ event, total, perPage }) {
  if (!event) return null;
  const capacity    = event.capacity ?? null;
  const registered  = typeof event.registered_count === 'number' ? event.registered_count : total;
  const remaining   = capacity != null ? Math.max(0, capacity - registered) : null;

  function row(label, value) {
    return (
      <div className="att-summary-item" key={label}>
        <span className="att-summary-label">{label}</span>
        <span className={`att-summary-value${!value && value !== 0 ? ' att-summary-value--muted' : ''}`}>
          {value ?? '—'}
        </span>
      </div>
    );
  }

  return (
    <Card className="att-summary-card">
      <div className="card-header">
        <h2 className="card-title">{event.title}</h2>
        <StatusBadge status={event.status} />
      </div>
      <div className="att-summary-grid">
        <div className="att-summary-item">
          <span className="att-summary-label">Attendees</span>
          <span className="att-summary-count">{total}</span>
        </div>
        {row('Capacity',              capacity != null ? capacity : 'Unlimited')}
        {row('Remaining Seats',       remaining != null ? remaining : 'Unlimited')}
        {row('Registration Deadline', formatDate(event.registration_closes_at))}
        {row('Created By',            event.created_by_name || '—')}
        {row('Created At',            formatDate(event.created_at))}
        {row('Published At',          formatDate(event.published_at))}
      </div>
    </Card>
  );
}

export default function AttendeesPage() {
  const [events,          setEvents]         = useState([]);
  const [eventsLoading,   setEventsLoading]  = useState(true);
  const [selectedEventId, setSelectedEventId] = useState('');
  const [search,          setSearch]         = useState('');
  const [batchYear,       setBatchYear]      = useState('');
  const [page,            setPage]           = useState(1);
  const perPage = 50;

  const [attendees, setAttendees] = useState([]);
  const [total,     setTotal]     = useState(0);
  const [loading,   setLoading]   = useState(false);
  const [error,     setError]     = useState(null);
  const [exporting, setExporting] = useState(false);
  const [toast,     setToast]     = useState(null);
  const toastRef   = useRef(null);
  const searchRef  = useRef(null);

  const selectedEvent = events.find(e => String(e.event_id) === String(selectedEventId)) ?? null;

  // Load events list on mount
  useEffect(() => {
    setEventsLoading(true);
    listAdminEvents()
      .then(data => setEvents(data.events ?? []))
      .catch(() => setEvents([]))
      .finally(() => setEventsLoading(false));
  }, []);

  // Load attendees when event or filters change
  useEffect(() => {
    if (!selectedEventId) return;
    setLoading(true);
    setError(null);
    listAdminAttendees(selectedEventId, {
      search:     search  || undefined,
      batch_year: batchYear ? Number(batchYear) : undefined,
      page,
      per_page: perPage,
    })
      .then(data => {
        setAttendees(data.attendees ?? []);
        setTotal(data.total ?? 0);
      })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }, [selectedEventId, search, batchYear, page]);

  function handleEventChange(e) {
    setSelectedEventId(e.target.value);
    setSearch('');
    setBatchYear('');
    setPage(1);
  }

  function handleSearch(e) {
    setSearch(e.target.value);
    setPage(1);
  }

  function handleBatchYear(e) {
    setBatchYear(e.target.value);
    setPage(1);
  }

  function showToast(msg, type = 'success') {
    setToast({ msg, type });
    clearTimeout(toastRef.current);
    toastRef.current = setTimeout(() => setToast(null), 4000);
  }

  async function handleExport() {
    if (!selectedEventId || exporting) return;
    setExporting(true);
    try {
      const blob = await exportAttendeesCSV(selectedEventId, {
        search:     search     || undefined,
        batch_year: batchYear  ? Number(batchYear) : undefined,
      });
      const url = URL.createObjectURL(blob);
      const a   = document.createElement('a');
      a.href     = url;
      a.download = `attendees-event-${selectedEventId}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      showToast('CSV exported successfully.');
    } catch (err) {
      showToast(`Export failed: ${err.message}`, 'error');
    } finally {
      setExporting(false);
    }
  }

  const totalPages = Math.max(1, Math.ceil(total / perPage));
  const startRow   = total === 0 ? 0 : (page - 1) * perPage + 1;
  const endRow     = Math.min(page * perPage, total);

  return (
    <div>
      <p className="page-eyebrow">Week 4</p>
      <h1 className="page-heading">Attendees</h1>
      <p className="page-sub">Operational attendee list — active registrations only. Cancelled registrations are hidden.</p>

      {/* ── Toolbar ────────────────────────────────────────────────────── */}
      <div className="att-toolbar">

        {/* Row 1: event selector + export */}
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

          <button
            className="btn btn-primary"
            disabled={!selectedEventId || exporting}
            onClick={handleExport}
          >
            {exporting ? 'Exporting…' : 'Export CSV'}
          </button>
        </div>

        {/* Row 2: search + batch year + count */}
        {selectedEventId && (
          <div className="att-toolbar-row">
            <div className="att-search-wrap">
              <IconSearch className="att-search-icon" />
              <input
                ref={searchRef}
                type="search"
                className="att-search-input"
                placeholder="Search by name…"
                value={search}
                onChange={handleSearch}
              />
              {search && (
                <button
                  className="att-search-clear"
                  onClick={() => { setSearch(''); setPage(1); searchRef.current?.focus(); }}
                  title="Clear search"
                >
                  <IconX />
                </button>
              )}
            </div>

            <select
              className="att-batch-select"
              value={batchYear}
              onChange={handleBatchYear}
            >
              <option value="">All Batches</option>
              {BATCH_YEAR_OPTIONS.map(y => (
                <option key={y} value={y}>{y}</option>
              ))}
            </select>

            {!loading && !error && (
              <span className="att-count-label">
                {total === 0 ? 'No attendees' : `${startRow}–${endRow} of ${total}`}
              </span>
            )}
          </div>
        )}
      </div>

      {/* ── Toast ──────────────────────────────────────────────────────── */}
      {toast && (
        <div className={`att-toast notice notice--${toast.type === 'error' ? 'warning' : 'success'} fade-up`}>
          <span>{toast.msg}</span>
          <button className="att-toast-close" onClick={() => setToast(null)}>✕</button>
        </div>
      )}

      {/* ── No event selected ──────────────────────────────────────────── */}
      {!selectedEventId && (
        <div className="att-select-prompt fade-up">
          <div className="att-select-prompt-icon">👥</div>
          <p>Select an event above to view its attendees.</p>
        </div>
      )}

      {/* ── Summary card ───────────────────────────────────────────────── */}
      {selectedEventId && !loading && !error && (
        <SummaryCard event={selectedEvent} total={total} perPage={perPage} />
      )}

      {/* ── Loading / error states ─────────────────────────────────────── */}
      {selectedEventId && loading && <LoadingView message="Loading attendees…" />}
      {selectedEventId && !loading && error && <p className="error-msg">{error}</p>}

      {/* ── Empty state ────────────────────────────────────────────────── */}
      {selectedEventId && !loading && !error && attendees.length === 0 && (
        <div className="empty-state fade-up">
          <p>{search || batchYear ? 'No attendees match your filter.' : 'No attendees registered for this event yet.'}</p>
        </div>
      )}

      {/* ── Attendees table ────────────────────────────────────────────── */}
      {selectedEventId && !loading && !error && attendees.length > 0 && (
        <div className="att-table-wrap fade-up">
          <table className="att-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Batch</th>
                <th>Branch</th>
                <th>Email</th>
                <th>Phone</th>
                <th>Registered At</th>
                <th>Email Status</th>
              </tr>
            </thead>
            <tbody>
              {attendees.map(a => (
                <tr key={a.registration_id}>
                  <td>
                    <div className="att-cell-name">{a.fullname_snapshot || '—'}</div>
                    {a.registration_number && (
                      <div className="att-cell-muted att-cell-mono">{a.registration_number}</div>
                    )}
                  </td>
                  <td>{a.batch_year_snapshot ?? '—'}</td>
                  <td>{a.branch_snapshot || '—'}</td>
                  <td className="att-cell-muted">{a.email_snapshot || '—'}</td>
                  <td className="att-cell-muted">{a.phone_snapshot || '—'}</td>
                  <td className="att-cell-muted">{formatDate(a.registered_at)}</td>
                  <td><EmailStatusCell status={a.confirmation_email_status} /></td>
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
            Page {page} of {totalPages} — {total} total attendee{total !== 1 ? 's' : ''}
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
