import { useEffect, useState } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { healthCheck } from '../api/authApi';
import { getAccessToken } from '../auth/sessionStorage';
import Card from '../components/Card';
import LoadingView from '../components/LoadingView';
import '../styles/dashboard.css';

export default function DashboardPage() {
  const { user } = useAuth();

  const [health,        setHealth]        = useState(null);
  const [healthLoading, setHealthLoading] = useState(true);
  const [healthError,   setHealthError]   = useState(null);

  function fetchHealth() {
    setHealthLoading(true);
    setHealthError(null);
    healthCheck()
      .then(data => setHealth(data))
      .catch(err  => setHealthError(err.message))
      .finally(()  => setHealthLoading(false));
  }

  useEffect(() => { fetchHealth(); }, []);

  const hasToken = !!getAccessToken();

  return (
    <div>
      <p className="page-eyebrow">Week 1 Foundation</p>
      <h1 className="page-heading">Dashboard</h1>
      <p className="page-sub">Platform health, session status, and upcoming feature previews.</p>

      <div className="dashboard-grid">

        {/* ── 1. Backend Health ── */}
        <Card>
          <div className="card-header">
            <span className="card-header-icon"><IconHealth /></span>
            <h2 className="card-title">Backend Health</h2>
            <button
              className="card-refresh-btn"
              onClick={fetchHealth}
              disabled={healthLoading}
            >
              ↻ Refresh
            </button>
          </div>

          {healthLoading && <LoadingView message="Checking…" />}
          {healthError   && (
            <p className="error-msg">{healthError}</p>
          )}
          {health && !healthLoading && (
            <>
              <div className="health-row">
                <span className="health-label">Status</span>
                <span className={`health-value health-value--${health.status === 'ok' ? 'ok' : 'error'}`}>
                  {health.status?.toUpperCase() ?? '—'}
                </span>
              </div>
              <div className="health-row">
                <span className="health-label">Database</span>
                <span className={`health-value health-value--${health.db === 'ok' ? 'ok' : 'error'}`}>
                  {health.db ?? '—'}
                </span>
              </div>
              <div className="health-row">
                <span className="health-label">Environment</span>
                <span className="health-value">{health.env ?? '—'}</span>
              </div>
              <div className="health-row">
                <span className="health-label">Version</span>
                <span className="health-value">{health.version ?? '—'}</span>
              </div>
            </>
          )}
        </Card>

        {/* ── 2. Logged-in User ── */}
        <Card>
          <div className="card-header">
            <span className="card-header-icon"><IconUser /></span>
            <h2 className="card-title">Logged-in User</h2>
          </div>
          {user ? (
            <>
              <div className="user-avatar">
                {(user.fullname || user.email || 'A')[0].toUpperCase()}
              </div>
              <UserField label="Name"         value={user.fullname} />
              <UserField label="Email"        value={user.email} />
              <UserField label="User Type"    value={user.user_type} />
              <UserField label="Ref ID"       value={user.ref_id} />
              <UserField label="Graduation"   value={user.graduation_year} />
            </>
          ) : (
            <p style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>No user data.</p>
          )}
        </Card>

        {/* ── 3. Auth Status ── */}
        <Card>
          <div className="card-header">
            <span className="card-header-icon"><IconShield /></span>
            <h2 className="card-title">Auth Status</h2>
          </div>
          <div className="auth-status-row">
            <span className="auth-status-label">Authenticated</span>
            <span className={`auth-status-value auth-status-value--${user ? 'ok' : 'error'}`}>
              {user ? 'Yes' : 'No'}
            </span>
          </div>
          <div className="auth-status-row">
            <span className="auth-status-label">Backend JWT</span>
            <span className={`auth-status-value auth-status-value--${hasToken ? 'ok' : 'error'}`}>
              {hasToken ? 'Present' : 'Not stored'}
            </span>
          </div>
          <div className="auth-status-row">
            <span className="auth-status-label">Session Source</span>
            <span className="auth-status-value">
              {user ? '/api/v1/auth/me ✓' : '—'}
            </span>
          </div>
          <div className="auth-status-row">
            <span className="auth-status-label">User Type</span>
            <span className="auth-status-value">{user?.user_type ?? '—'}</span>
          </div>
        </Card>

        {/* ── 4. Events placeholder ── */}
        <PlaceholderCard
          icon="📅"
          title="Events"
          message="Event management APIs will be implemented in Week 2."
          week="Week 2"
        />

        {/* ── 5. Registrations placeholder ── */}
        <PlaceholderCard
          icon="📋"
          title="Registrations"
          message="Registration APIs will be implemented in Week 3."
          week="Week 3"
        />

        {/* ── 6. Attendees placeholder ── */}
        <PlaceholderCard
          icon="👥"
          title="Attendees"
          message="Attendee management APIs will be implemented in Week 4."
          week="Week 4"
        />
      </div>
    </div>
  );
}

function UserField({ label, value }) {
  return (
    <div className="user-field">
      <div className="user-field-label">{label}</div>
      <div className={`user-field-value${!value ? ' user-field-value--muted' : ''}`}>
        {value ?? 'N/A'}
      </div>
    </div>
  );
}

function PlaceholderCard({ icon, title, message, week }) {
  return (
    <Card>
      <div className="card-header">
        <span className="card-header-icon" style={{ fontSize: '1rem' }}>{icon}</span>
        <h2 className="card-title">{title}</h2>
      </div>
      <div className="placeholder-card-inner">
        <p className="placeholder-text">{message}</p>
        <p className="placeholder-week">{week}</p>
      </div>
    </Card>
  );
}

function IconHealth() {
  return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>;
}
function IconUser() {
  return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>;
}
function IconShield() {
  return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>;
}
