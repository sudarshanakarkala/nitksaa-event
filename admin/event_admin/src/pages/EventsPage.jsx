import { useEffect, useState } from 'react';
import StatusBadge from '../components/StatusBadge';
import LoadingView from '../components/LoadingView';
import { listEvents } from '../api/eventsApi';
import '../styles/events.css';

function formatDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('en-IN', {
    day:    '2-digit',
    month:  'short',
    year:   'numeric',
    hour:   '2-digit',
    minute: '2-digit',
    hour12: true,
  });
}

export default function EventsPage() {
  const [events,  setEvents]  = useState([]);
  const [total,   setTotal]   = useState(0);
  const [loading, setLoading] = useState(true);
  const [error,   setError]   = useState(null);

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

  return (
    <div>
      <p className="page-eyebrow">Week 2</p>
      <h1 className="page-heading">Events</h1>
      <p className="page-sub">Manage and monitor all NITKSAA events.</p>

      <div className="events-toolbar">
        <span className="events-count">
          {!loading && !error && `${total} event${total !== 1 ? 's' : ''}`}
        </span>
        <button className="btn btn-ghost" onClick={fetchEvents} disabled={loading}>
          ↻ Refresh
        </button>
      </div>

      {loading && <LoadingView message="Loading events…" />}

      {!loading && error && (
        <p className="error-msg">{error}</p>
      )}

      {!loading && !error && events.length === 0 && (
        <div className="empty-state fade-up">
          <p>No events found.</p>
          <p style={{ marginTop: 8, fontSize: '0.8rem' }}>Create your first event to get started.</p>
        </div>
      )}

      {!loading && !error && events.length > 0 && (
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
              {events.map(event => (
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
                      <button className="btn btn-ghost btn-xs" disabled title="Coming soon">View</button>
                      <button className="btn btn-ghost btn-xs" disabled title="Coming soon">Edit</button>
                      <button className="btn btn-ghost btn-xs" disabled title="Coming soon">Publish</button>
                      <button className="btn btn-danger btn-xs" disabled title="Coming soon">Cancel</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
