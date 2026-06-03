import { useEffect, useState } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { healthCheck } from '../api/authApi';

export default function Header() {
  const { user, logout } = useAuth();
  const [health, setHealth]   = useState('checking');
  const [loggingOut, setOut]  = useState(false);

  useEffect(() => {
    healthCheck()
      .then(() => setHealth('ok'))
      .catch(() => setHealth('error'));
  }, []);

  async function handleLogout() {
    setOut(true);
    await logout();
    window.location.replace('/login');
  }

  const displayName = user?.fullname || user?.email || 'Admin';

  return (
    <header className="admin-header">
      <span className="header-app-name">NITKSAA Event Admin</span>

      <span className="header-spacer" />

      <span className="header-health">
        <span
          className={`header-health-dot header-health-dot--${health}`}
          title={`Backend: ${health}`}
        />
        Backend {health === 'checking' ? 'checking…' : health === 'ok' ? 'online' : 'offline'}
      </span>

      <span className="header-divider" />

      <span className="header-user" title={user?.email}>
        {displayName}
      </span>

      <button
        className="btn btn-ghost"
        style={{ fontSize: '0.8rem', padding: '6px 14px' }}
        onClick={handleLogout}
        disabled={loggingOut}
      >
        {loggingOut ? 'Signing out…' : 'Logout'}
      </button>
    </header>
  );
}
