import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { signOut } from 'firebase/auth';
import { auth } from '../firebase';
import { exchangeFirebaseToken, getCurrentUser } from '../api/authApi';
import {
  clearSession,
  getAccessToken,
  getStoredUser,
  setAccessToken,
  setStoredUser,
} from './sessionStorage';
import { BASE_URL } from '../api/apiClient';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser]         = useState(null);
  const [isLoading, setLoading] = useState(true);

  // On mount: check for a stored backend JWT and validate it with /auth/me.
  // Uses fetch directly to avoid the apiClient's 401 hard-redirect during restore.
  useEffect(() => {
    async function restore() {
      const token = getAccessToken();
      if (!token) {
        setLoading(false);
        return;
      }
      try {
        const response = await fetch(`${BASE_URL}/api/v1/auth/me`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!response.ok) {
          clearSession();
        } else {
          const me = await response.json();
          setUser(me);
        }
      } catch {
        // Network unreachable — keep cached user so the session survives an offline reload.
        const stored = getStoredUser();
        if (stored) setUser(stored);
      } finally {
        setLoading(false);
      }
    }
    restore();
  }, []);

  // Call this after Firebase sign-in to exchange the Firebase token for a backend JWT.
  const loginWithFirebaseToken = useCallback(async (firebaseIdToken) => {
    const backendData = await exchangeFirebaseToken(firebaseIdToken);
    setAccessToken(backendData.access_token);
    const me = await getCurrentUser();
    setStoredUser(me);
    setUser(me);
    return me;
  }, []);

  const logout = useCallback(async () => {
    try { await signOut(auth); } catch { /* Firebase signout is best-effort */ }
    clearSession();
    setUser(null);
  }, []);

  const value = {
    user,
    isAuthenticated: !!user,
    isLoading,
    loginWithFirebaseToken,
    logout,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
