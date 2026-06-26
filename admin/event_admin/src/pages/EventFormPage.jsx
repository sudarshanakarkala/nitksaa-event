import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { createEvent, getEvent, updateEvent } from '../api/eventsApi';
import EventEnrichmentPanel from './EventEnrichmentPanel';
import '../styles/event-form.css';

// ── Timezone options and UTC offset lookup ────────────────────────────────
const TIMEZONES = [
  { label: 'India — IST (UTC+05:30)',      value: 'Asia/Kolkata' },
  { label: 'UTC (UTC+00:00)',               value: 'UTC' },
  { label: 'Dubai — GST (UTC+04:00)',      value: 'Asia/Dubai' },
  { label: 'London — GMT/BST',             value: 'Europe/London' },
  { label: 'New York — EST/EDT',           value: 'America/New_York' },
  { label: 'San Francisco — PST/PDT',      value: 'America/Los_Angeles' },
  { label: 'Singapore — SGT (UTC+08:00)',  value: 'Asia/Singapore' },
  { label: 'Sydney — AEST/AEDT',          value: 'Australia/Sydney' },
];

// Approximate static offsets — sufficient for dev prototype
const TZ_OFFSETS = {
  'Asia/Kolkata':        '+05:30',
  'UTC':                 '+00:00',
  'Asia/Dubai':          '+04:00',
  'Europe/London':       '+00:00',
  'America/New_York':    '-05:00',
  'America/Los_Angeles': '-08:00',
  'Asia/Singapore':      '+08:00',
  'Australia/Sydney':    '+10:00',
};

// ── Initial empty form state ──────────────────────────────────────────────
const EMPTY = {
  title:                  '',
  tagline:                '',
  description:            '',
  start_datetime:         '',
  end_datetime:           '',
  timezone:               'Asia/Kolkata',
  is_virtual:             false,
  location_text:          '',
  virtual_url:            '',
  capacity:               '',
  registration_opens_at:  '',
  registration_closes_at: '',
  thumbnail_url:          '',
  banner_url:             '',
  is_full_day:            false,
  is_free:                true,
  ticket_price:           '',
};

// Convert a UTC ISO datetime string to a datetime-local input value (YYYY-MM-DDTHH:mm)
// in the given IANA timezone (e.g. "Asia/Kolkata").
// Uses Intl.DateTimeFormat — no extra libraries required.
// Edge case: hour12:false can return "24" for midnight on some platforms; normalised to "00".
function toDatetimeLocalInTZ(iso, tz) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';

  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone: tz ?? 'UTC',
      year:     'numeric',
      month:    '2-digit',
      day:      '2-digit',
      hour:     '2-digit',
      minute:   '2-digit',
      hour12:   false,
    })
    .formatToParts(d)
    .map(({ type, value }) => [type, value])
  );

  const hour = parts.hour === '24' ? '00' : (parts.hour ?? '00');
  return `${parts.year}-${parts.month}-${parts.day}T${hour}:${parts.minute}`;
}

// Convert a UTC ISO datetime string to a date-only value (YYYY-MM-DD) for full-day events.
function toDateOnlyInTZ(iso, tz) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', {
      timeZone: tz ?? 'UTC',
      year: 'numeric', month: '2-digit', day: '2-digit',
    })
    .formatToParts(d)
    .map(({ type, value }) => [type, value])
  );
  return `${parts.year}-${parts.month}-${parts.day}`;
}

// Validate form; returns object of {field: errorMessage}
function validate(f) {
  const e = {};
  if (!f.title.trim())
    e.title = 'Title is required.';

  if (f.is_full_day) {
    if (!f.start_datetime) e.start_datetime = 'Start date is required.';
    if (!f.end_datetime)   e.end_datetime   = 'End date is required.';
    if (f.start_datetime && f.end_datetime && f.end_datetime < f.start_datetime)
      e.end_datetime = 'End date must be on or after start date.';
  } else {
    if (!f.start_datetime) e.start_datetime = 'Start date & time is required.';
    if (!f.end_datetime)   e.end_datetime   = 'End date & time is required.';
    if (f.start_datetime && f.end_datetime && f.end_datetime <= f.start_datetime)
      e.end_datetime = 'End must be after start.';
  }

  if (!f.timezone.trim())
    e.timezone = 'Timezone is required.';
  if (f.capacity !== '' && (isNaN(Number(f.capacity)) || Number(f.capacity) <= 0))
    e.capacity = 'Capacity must be a positive number.';
  if (!f.is_virtual && !f.location_text.trim())
    e.location_text = 'Venue is required for physical events.';
  if (f.is_virtual && !f.virtual_url.trim())
    e.virtual_url = 'Join URL is required for virtual events.';
  if (!f.is_free) {
    if (f.ticket_price === '' || isNaN(Number(f.ticket_price)) || Number(f.ticket_price) < 0)
      e.ticket_price = 'Enter a valid ticket price (0 or more).';
  }
  return e;
}

// Build API payload from form state
function buildPayload(f) {
  const offset = TZ_OFFSETS[f.timezone] ?? '+05:30';
  const dt     = v => v ? `${v}:00${offset}` : null;

  let start_datetime, end_datetime;
  if (f.is_full_day) {
    start_datetime = f.start_datetime ? `${f.start_datetime}T00:00:00${offset}` : null;
    end_datetime   = f.end_datetime   ? `${f.end_datetime}T23:59:59${offset}`   : null;
  } else {
    start_datetime = dt(f.start_datetime);
    end_datetime   = dt(f.end_datetime);
  }

  return {
    title:                  f.title.trim(),
    tagline:                f.tagline.trim()                || null,
    description:            f.description.trim()            || null,
    start_datetime,
    end_datetime,
    timezone:               f.timezone,
    is_virtual:             f.is_virtual,
    location_text:          f.is_virtual ? null : (f.location_text.trim() || null),
    virtual_url:            f.is_virtual ? (f.virtual_url.trim() || null) : null,
    capacity:               f.capacity !== '' ? parseInt(f.capacity, 10) : null,
    registration_opens_at:  dt(f.registration_opens_at),
    registration_closes_at: dt(f.registration_closes_at),
    thumbnail_url:          f.thumbnail_url.trim()          || null,
    banner_url:             f.banner_url.trim()             || null,
    is_full_day:            Boolean(f.is_full_day),
    is_free:                Boolean(f.is_free),
    ticket_price:           f.is_free ? null : (f.ticket_price !== '' ? parseFloat(f.ticket_price) : null),
  };
}

// ── Component ─────────────────────────────────────────────────────────────
export default function EventFormPage() {
  const { eventId } = useParams();
  const navigate    = useNavigate();
  const isEdit      = !!eventId;

  const [form,         setForm]         = useState(EMPTY);
  const [errors,       setErrors]       = useState({});
  const [saving,       setSaving]       = useState(false);
  const [apiError,     setApiError]     = useState(null);
  const [loadingEvent, setLoadingEvent] = useState(isEdit);
  const [loadError,    setLoadError]    = useState(null);

  // Load existing event in edit mode
  useEffect(() => {
    if (!isEdit) return;
    setLoadingEvent(true);
    getEvent(eventId)
      .then(data => {
        const ev  = data.event;
        const tz  = ev.timezone ?? 'Asia/Kolkata';
        const fd  = Boolean(ev.is_full_day);
        setForm({
          title:                  ev.title                  ?? '',
          tagline:                ev.tagline                ?? '',
          description:            ev.description            ?? '',
          start_datetime:         fd
                                    ? toDateOnlyInTZ(ev.start_datetime, tz)
                                    : toDatetimeLocalInTZ(ev.start_datetime, tz),
          end_datetime:           fd
                                    ? toDateOnlyInTZ(ev.end_datetime, tz)
                                    : toDatetimeLocalInTZ(ev.end_datetime, tz),
          timezone:               tz,
          is_virtual:             ev.is_virtual             ?? false,
          location_text:          ev.location_text          ?? '',
          virtual_url:            ev.virtual_url            ?? '',
          capacity:               ev.capacity != null ? String(ev.capacity) : '',
          show_attendee_list:     ev.show_attendee_list     ?? false,
          registration_opens_at:  toDatetimeLocalInTZ(ev.registration_opens_at,  tz),
          registration_closes_at: toDatetimeLocalInTZ(ev.registration_closes_at, tz),
          thumbnail_url:          ev.thumbnail_url          ?? '',
          banner_url:             ev.banner_url             ?? '',
          is_full_day:            fd,
          is_free:                ev.is_free                ?? true,
          ticket_price:           ev.ticket_price != null ? String(ev.ticket_price) : '',
        });
      })
      .catch(err => setLoadError(err.message))
      .finally(() => setLoadingEvent(false));
  }, [eventId, isEdit]);

  // Update a single form field and clear its error
  function set(key, value) {
    setForm(prev => ({ ...prev, [key]: value }));
    if (errors[key]) setErrors(prev => { const n = { ...prev }; delete n[key]; return n; });
  }

  async function handleSubmit(e) {
    e.preventDefault();
    const errs = validate(form);
    if (Object.keys(errs).length > 0) {
      setErrors(errs);
      document.querySelector('.ef-field-error')
        ?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }
    setSaving(true);
    setApiError(null);
    try {
      const payload = buildPayload(form);
      if (isEdit) {
        await updateEvent(eventId, payload);
        navigate('/events');
      } else {
        const result = await createEvent(payload);
        // Navigate to edit view so the enrichment panel (people/sponsors/partners) is immediately accessible.
        navigate(`/events/${result.event_id}/edit`);
      }
    } catch (err) {
      setApiError(err.message);
      setSaving(false);
    }
  }

  // ── Loading state (edit mode only) ──────────────────────────────────────
  if (loadingEvent) {
    return (
      <div className="ef-page fade-up">
        <p className="page-eyebrow">Week 5</p>
        <h1 className="page-heading">Edit Event</h1>
        <p style={{ color: 'var(--text-muted)', marginTop: 8 }}>Loading event…</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="ef-page fade-up">
        <p className="page-eyebrow">Week 5</p>
        <h1 className="page-heading">Edit Event</h1>
        <p className="error-msg" style={{ marginTop: 12 }}>{loadError}</p>
        <button
          className="btn btn-ghost"
          style={{ marginTop: 16 }}
          onClick={() => navigate('/events')}
        >
          ← Back to Events
        </button>
      </div>
    );
  }

  // ── Form ─────────────────────────────────────────────────────────────────
  return (
    <div className="ef-page fade-up">
      <button className="btn btn-ghost ef-back-btn" onClick={() => navigate('/events')}>
        ← Back to Events
      </button>

      <p className="page-eyebrow">Week 5</p>
      <h1 className="page-heading">{isEdit ? 'Edit Event' : 'Create Event'}</h1>
      <p className="page-sub">
        {isEdit
          ? 'Update the event details and save your changes.'
          : 'Fill in the details below to create a new event.'}
      </p>

      {apiError && <p className="error-msg ef-api-error">{apiError}</p>}

      <form className="ef-form" onSubmit={handleSubmit} noValidate>

        {/* ── Section 1: Event Details ──────────────────────────────────── */}
        <div className="card ef-section">
          <h3 className="ef-section-title">Event Details</h3>

          {/* Title + Tagline */}
          <div className="ef-field-row">
            <div className="ef-field">
              <label htmlFor="ef-title">
                Title <span className="ef-req">*</span>
              </label>
              <input
                id="ef-title"
                type="text"
                placeholder="e.g. Breakfast Club Bangalore"
                value={form.title}
                onChange={e => set('title', e.target.value)}
              />
              {errors.title && <span className="ef-field-error">{errors.title}</span>}
            </div>
            <div className="ef-field">
              <label htmlFor="ef-tagline">Tagline</label>
              <input
                id="ef-tagline"
                type="text"
                placeholder="Short one-liner for the event"
                value={form.tagline}
                onChange={e => set('tagline', e.target.value)}
              />
            </div>
          </div>

          {/* Event Type */}
          <div className="ef-field">
            <label>Event Type <span className="ef-req">*</span></label>
            <div className="ef-type-group">
              <label
                className={`ef-type-option${!form.is_virtual ? ' ef-type-option--active' : ''}`}
              >
                <input
                  type="radio"
                  name="is_virtual"
                  checked={!form.is_virtual}
                  onChange={() => set('is_virtual', false)}
                />
                Physical / In-person
              </label>
              <label
                className={`ef-type-option${form.is_virtual ? ' ef-type-option--active' : ''}`}
              >
                <input
                  type="radio"
                  name="is_virtual"
                  checked={form.is_virtual}
                  onChange={() => set('is_virtual', true)}
                />
                Virtual / Online
              </label>
            </div>
          </div>

          {/* Venue (physical) or Join URL (virtual) */}
          {!form.is_virtual ? (
            <div className="ef-field">
              <label htmlFor="ef-venue">
                Venue <span className="ef-req">*</span>
              </label>
              <input
                id="ef-venue"
                type="text"
                placeholder="e.g. The Leela Palace, Bangalore"
                value={form.location_text}
                onChange={e => set('location_text', e.target.value)}
              />
              {errors.location_text && (
                <span className="ef-field-error">{errors.location_text}</span>
              )}
            </div>
          ) : (
            <div className="ef-field">
              <label htmlFor="ef-virtual-url">
                Join URL <span className="ef-req">*</span>
              </label>
              <input
                id="ef-virtual-url"
                type="url"
                placeholder="https://meet.google.com/your-meeting-link"
                value={form.virtual_url}
                onChange={e => set('virtual_url', e.target.value)}
              />
              {errors.virtual_url && (
                <span className="ef-field-error">{errors.virtual_url}</span>
              )}
            </div>
          )}

          {/* Full Day toggle */}
          <label className="ef-toggle-option" htmlFor="ef-full-day">
            <input
              id="ef-full-day"
              type="checkbox"
              checked={form.is_full_day}
              onChange={e => {
                set('is_full_day', e.target.checked);
                set('start_datetime', '');
                set('end_datetime', '');
              }}
            />
            <span>
              <strong>Full Day Event</strong>
              <small>
                All-day or multi-day event — time fields are hidden. End date = start date for a single-day event.
              </small>
            </span>
          </label>

          {/* Start + End — date-only for full-day, datetime-local otherwise */}
          <div className="ef-field-row">
            <div className="ef-field">
              <label htmlFor="ef-start">
                {form.is_full_day ? 'Start Date' : 'Start Date & Time'}{' '}
                <span className="ef-req">*</span>
              </label>
              <input
                id="ef-start"
                type={form.is_full_day ? 'date' : 'datetime-local'}
                value={form.start_datetime}
                onChange={e => set('start_datetime', e.target.value)}
              />
              {errors.start_datetime && (
                <span className="ef-field-error">{errors.start_datetime}</span>
              )}
            </div>
            <div className="ef-field">
              <label htmlFor="ef-end">
                {form.is_full_day ? 'End Date' : 'End Date & Time'}{' '}
                <span className="ef-req">*</span>
              </label>
              <input
                id="ef-end"
                type={form.is_full_day ? 'date' : 'datetime-local'}
                value={form.end_datetime}
                onChange={e => set('end_datetime', e.target.value)}
              />
              {errors.end_datetime && (
                <span className="ef-field-error">{errors.end_datetime}</span>
              )}
              {form.is_full_day && (
                <span className="ef-hint">Same as start date for a single-day event.</span>
              )}
            </div>
          </div>

          {/* Timezone — hidden for full-day events (no time component) */}
          {!form.is_full_day && (
            <div className="ef-field">
              <label htmlFor="ef-timezone">
                Timezone <span className="ef-req">*</span>
              </label>
              <select
                id="ef-timezone"
                value={form.timezone}
                onChange={e => set('timezone', e.target.value)}
              >
                {TIMEZONES.map(tz => (
                  <option key={tz.value} value={tz.value}>{tz.label}</option>
                ))}
              </select>
              {errors.timezone && <span className="ef-field-error">{errors.timezone}</span>}
            </div>
          )}

          {/* Description */}
          <div className="ef-field">
            <label htmlFor="ef-desc">Description</label>
            <textarea
              id="ef-desc"
              rows={5}
              placeholder="Detailed description of the event…"
              value={form.description}
              onChange={e => set('description', e.target.value)}
            />
          </div>
        </div>

        {/* ── Section 2: Registration & Capacity ───────────────────────── */}
        <div className="card ef-section">
          <h3 className="ef-section-title">Registration &amp; Capacity</h3>

          <div className="ef-field-row">
            <div className="ef-field">
              <label htmlFor="ef-capacity">Capacity</label>
              <input
                id="ef-capacity"
                type="number"
                min="1"
                placeholder="Leave empty for unlimited"
                value={form.capacity}
                onChange={e => set('capacity', e.target.value)}
              />
              {errors.capacity
                ? <span className="ef-field-error">{errors.capacity}</span>
                : <span className="ef-hint">Leave empty for unlimited attendance.</span>
              }
            </div>
            <div className="ef-field" />
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label htmlFor="ef-reg-opens">Registration Opens At</label>
              <input
                id="ef-reg-opens"
                type="datetime-local"
                value={form.registration_opens_at}
                onChange={e => set('registration_opens_at', e.target.value)}
              />
            </div>
            <div className="ef-field">
              <label htmlFor="ef-reg-closes">Registration Deadline</label>
              <input
                id="ef-reg-closes"
                type="datetime-local"
                value={form.registration_closes_at}
                onChange={e => set('registration_closes_at', e.target.value)}
              />
            </div>
          </div>

          <label className="ef-toggle-option" htmlFor="ef-show-attendee-list">
            <input
              id="ef-show-attendee-list"
              type="checkbox"
              checked={form.show_attendee_list}
              onChange={e => set('show_attendee_list', e.target.checked)}
            />
            <span>
              <strong>Show attendee list publicly</strong>
              <small>
                Keep this off unless the event should expose attendee visibility in a future attendee feature.
              </small>
            </span>
          </label>
        </div>

        {/* ── Section 3: Pricing ───────────────────────────────────────── */}
        <div className="card ef-section">
          <h3 className="ef-section-title">Pricing</h3>

          <label className="ef-toggle-option" htmlFor="ef-is-free">
            <input
              id="ef-is-free"
              type="checkbox"
              checked={form.is_free}
              onChange={e => {
                set('is_free', e.target.checked);
                if (e.target.checked) set('ticket_price', '');
              }}
            />
            <span>
              <strong>Free event</strong>
              <small>No ticket price required. Uncheck to specify a ticket price.</small>
            </span>
          </label>

          {!form.is_free && (
            <div className="ef-field-row" style={{ marginTop: '14px' }}>
              <div className="ef-field">
                <label htmlFor="ef-ticket-price">
                  Ticket Price (INR) <span className="ef-req">*</span>
                </label>
                <div className="ef-input-prefix-wrap">
                  <span className="ef-input-prefix">₹</span>
                  <input
                    id="ef-ticket-price"
                    type="number"
                    min="0"
                    step="1"
                    placeholder="0"
                    value={form.ticket_price}
                    onChange={e => set('ticket_price', e.target.value)}
                    style={{ paddingLeft: '2rem' }}
                  />
                </div>
                {errors.ticket_price
                  ? <span className="ef-field-error">{errors.ticket_price}</span>
                  : <span className="ef-hint">Display-only. Payment processing is not enabled.</span>
                }
              </div>
              <div className="ef-field" />
            </div>
          )}
        </div>

        {/* ── Section 4: Media ─────────────────────────────────────────── */}
        <div className="card ef-section">
          <h3 className="ef-section-title">Media</h3>

          <div className="ef-field-row">
            <div className="ef-field">
              <label htmlFor="ef-thumb">Thumbnail URL</label>
              <input
                id="ef-thumb"
                type="url"
                placeholder="https://example.com/thumbnail.jpg"
                value={form.thumbnail_url}
                onChange={e => set('thumbnail_url', e.target.value)}
              />
            </div>
            <div className="ef-field">
              <label htmlFor="ef-banner">Banner URL</label>
              <input
                id="ef-banner"
                type="url"
                placeholder="https://example.com/banner.jpg"
                value={form.banner_url}
                onChange={e => set('banner_url', e.target.value)}
              />
            </div>
          </div>
        </div>

        {/* ── Actions ──────────────────────────────────────────────────── */}
        <div className="ef-actions">
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => navigate('/events')}
            disabled={saving}
          >
            Cancel
          </button>
          <button type="submit" className="btn btn-primary" disabled={saving}>
            {saving ? 'Saving…' : (isEdit ? 'Update Event' : 'Create Event')}
          </button>
        </div>

      </form>

      {/* ── Event Enrichment (edit mode only) ────────────────────────── */}
      {isEdit && <EventEnrichmentPanel eventId={eventId} />}

    </div>
  );
}
