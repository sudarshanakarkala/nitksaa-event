import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { clearSession, getAccessToken } from '../auth/sessionStorage';
import Card from '../components/Card';

export default function SettingsPage() {
  const { user, logout }  = useAuth();
  const navigate          = useNavigate();
  const [cleared, setCleared]   = useState(false);
  const [loggingOut, setOut]    = useState(false);

  const backendUrl  = import.meta.env.VITE_BACKEND_BASE_URL || 'http://localhost:8000';
  const projectId   = import.meta.env.VITE_FIREBASE_PROJECT_ID || 'N/A';
  const authDomain  = import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || 'N/A';
  const hasToken    = !!getAccessToken();

  function handleClearSession() {
    clearSession();
    setCleared(true);
    setTimeout(() => setCleared(false), 4000);
  }

  async function handleLogout() {
    setOut(true);
    await logout();
    navigate('/login', { replace: true });
  }

  return (
    <div>
      <p className="page-eyebrow">Configuration</p>
      <h1 className="page-heading">Settings</h1>
      <p className="page-sub">Current session, environment, and account controls.</p>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 20, maxWidth: 640 }}>

        {/* Current user */}
        <Card>
          <h3 style={{ fontFamily: 'var(--font-serif)', marginBottom: 16, fontSize: '1rem' }}>Current User</h3>
          <SettingRow label="Name"      value={user?.fullname     || '—'} />
          <SettingRow label="Email"     value={user?.email        || '—'} />
          <SettingRow label="User Type" value={user?.user_type    || '—'} />
          <SettingRow label="Ref ID"    value={user?.ref_id       || '—'} />
          <SettingRow label="Backend JWT" value={hasToken ? 'Stored ✓' : 'Not stored'} />
        </Card>

        {/* Environment */}
        <Card>
          <h3 style={{ fontFamily: 'var(--font-serif)', marginBottom: 16, fontSize: '1rem' }}>Environment</h3>
          <SettingRow label="Backend URL"     value={backendUrl} mono />
          <SettingRow label="Firebase Project" value={projectId} mono />
          <SettingRow label="Auth Domain"      value={authDomain} mono />
        </Card>

        {/* Account controls */}
        <Card>
          <h3 style={{ fontFamily: 'var(--font-serif)', marginBottom: 16, fontSize: '1rem' }}>Account</h3>

          {cleared && (
            <div className="notice notice--success" style={{ marginBottom: 14 }}>
              Local session cleared. Reload the page to re-authenticate.
            </div>
          )}

          <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 14, lineHeight: 1.55 }}>
            <strong>Clear local session</strong> removes the stored backend JWT from your browser without signing out of Firebase.
            Use this to force a fresh authentication cycle during debugging.
          </p>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
            <button className="btn btn-ghost" onClick={handleClearSession}>
              Clear Local Session
            </button>
            <button
              className="btn btn-danger"
              onClick={handleLogout}
              disabled={loggingOut}
            >
              {loggingOut ? 'Signing out…' : 'Logout'}
            </button>
          </div>
        </Card>

      </div>
    </div>
  );
}

function SettingRow({ label, value, mono = false }) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'flex-start',
      justifyContent: 'space-between',
      gap: 16,
      padding: '9px 0',
      borderBottom: '1px solid var(--border)',
    }}>
      <span style={{ fontSize: '0.82rem', color: 'var(--text-muted)', flexShrink: 0, minWidth: 120 }}>
        {label}
      </span>
      <span style={{
        fontSize: '0.85rem',
        color: 'var(--text-primary)',
        fontWeight: 500,
        fontFamily: mono ? 'monospace' : undefined,
        wordBreak: 'break-all',
        textAlign: 'right',
      }}>
        {value}
      </span>
    </div>
  );
}
