import { useEffect, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import {
  signInWithEmailAndPassword,
  signInWithPopup,
  GoogleAuthProvider,
} from 'firebase/auth';
import { auth, getFirebaseConfigError } from '../firebase';
import { useAuth } from '../auth/AuthProvider';
import { healthCheck } from '../api/authApi';
import LoadingView from '../components/LoadingView';
import '../styles/login.css';

function friendlyError(err) {
  const code = err.code || '';
  if (code.includes('user-not-found') || code.includes('wrong-password') || code.includes('invalid-credential')) {
    return 'Invalid email or password. Please check your credentials.';
  }
  if (code.includes('user-disabled')) return 'This account has been disabled.';
  if (code.includes('too-many-requests')) return 'Too many failed attempts. Try again later.';
  if (code.includes('popup-closed') || code.includes('cancelled-popup')) return 'Google sign-in was cancelled.';
  if (code.includes('network-request-failed')) return 'Network error. Check your connection.';
  return err.message || 'An unexpected error occurred. Please try again.';
}

export default function LoginPage() {
  const { isAuthenticated, isLoading, loginWithFirebaseToken } = useAuth();
  const navigate = useNavigate();

  const [email,     setEmail]     = useState('');
  const [password,  setPassword]  = useState('');
  const [error,     setError]     = useState(null);
  const [loading,   setLoading]   = useState(false);
  const [gLoading,  setGLoading]  = useState(false);
  const [health,    setHealth]    = useState('checking');

  const configError = getFirebaseConfigError();

  useEffect(() => {
    healthCheck()
      .then(() => setHealth('ok'))
      .catch(() => setHealth('error'));
  }, []);

  if (isLoading) return <LoadingView fullPage message="Checking session…" />;
  if (isAuthenticated) return <Navigate to="/dashboard" replace />;

  async function handleEmailLogin(e) {
    e.preventDefault();
    if (!email.trim() || !password) return;
    setError(null);
    setLoading(true);
    try {
      const cred = await signInWithEmailAndPassword(auth, email.trim(), password);
      const firebaseToken = await cred.user.getIdToken(true);
      await loginWithFirebaseToken(firebaseToken);
      navigate('/dashboard', { replace: true });
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setLoading(false);
    }
  }

  async function handleGoogleLogin() {
    setError(null);
    setGLoading(true);
    try {
      const provider = new GoogleAuthProvider();
      const cred = await signInWithPopup(auth, provider);
      const firebaseToken = await cred.user.getIdToken(true);
      await loginWithFirebaseToken(firebaseToken);
      navigate('/dashboard', { replace: true });
    } catch (err) {
      if (err.code !== 'auth/popup-closed-by-user' && err.code !== 'auth/cancelled-popup-request') {
        setError(friendlyError(err));
      }
    } finally {
      setGLoading(false);
    }
  }

  const busy = loading || gLoading;

  return (
    <div className="login-root">
      <div className="login-card fade-up">
        {/* Brand */}
        <div className="login-brand">
          <h1 className="login-brand-title">NITKSAA Event</h1>
          <p className="login-brand-subtitle">Admin Portal</p>
          <div className="login-brand-line" />
        </div>

        {/* Backend health */}
        <div className="login-health">
          <span className={`health-dot health-dot--${health}`} />
          {health === 'checking' && 'Checking backend…'}
          {health === 'ok'       && 'Backend online'}
          {health === 'error'    && 'Backend unreachable — start the server'}
        </div>

        {/* Firebase config missing */}
        {configError && (
          <div className="error-msg" style={{ marginBottom: 20, textAlign: 'left' }}>
            <strong>Configuration error:</strong><br />{configError}
          </div>
        )}

        {/* Error banner */}
        {error && (
          <div className="error-msg" style={{ marginBottom: 16 }}>
            {error}
          </div>
        )}

        {!configError && (
          <>
            {/* Email / password form */}
            <form className="login-form" onSubmit={handleEmailLogin} noValidate>
              <div className="login-field">
                <label htmlFor="email">Email</label>
                <input
                  id="email"
                  type="email"
                  placeholder="admin@example.com"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  autoComplete="email"
                  disabled={busy}
                  required
                />
              </div>
              <div className="login-field">
                <label htmlFor="password">Password</label>
                <input
                  id="password"
                  type="password"
                  placeholder="••••••••"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  autoComplete="current-password"
                  disabled={busy}
                  required
                />
              </div>
              <button
                type="submit"
                className="btn btn-primary btn-full"
                disabled={busy || !email.trim() || !password}
              >
                {loading ? 'Signing in…' : 'Sign In'}
              </button>
            </form>

            {/* Divider */}
            <div className="login-divider" style={{ marginTop: 16, marginBottom: 16 }}>
              <span className="login-divider-line" />
              <span className="login-divider-text">or</span>
              <span className="login-divider-line" />
            </div>

            {/* Google sign-in */}
            <button
              type="button"
              className="btn-google"
              onClick={handleGoogleLogin}
              disabled={busy}
            >
              <GoogleIcon />
              {gLoading ? 'Signing in with Google…' : 'Continue with Google'}
            </button>
          </>
        )}
      </div>
    </div>
  );
}

function GoogleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
    </svg>
  );
}
