import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './auth/AuthProvider';
import RequireAuth from './auth/RequireAuth';
import AdminLayout from './layout/AdminLayout';
import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import EventsPage from './pages/EventsPage';
import EventFormPage from './pages/EventFormPage';
import RegistrationsPage from './pages/RegistrationsPage';
import AttendeesPage from './pages/AttendeesPage';
import SettingsPage from './pages/SettingsPage';
import LoadingView from './components/LoadingView';

function RootRedirect() {
  const { isAuthenticated, isLoading } = useAuth();
  if (isLoading) return <LoadingView fullPage message="Starting..." />;
  return <Navigate to={isAuthenticated ? '/dashboard' : '/login'} replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/" element={<RootRedirect />} />
          <Route path="/login" element={<LoginPage />} />

          {/* Protected routes: RequireAuth → AdminLayout → pages */}
          <Route element={<RequireAuth />}>
            <Route element={<AdminLayout />}>
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/events" element={<EventsPage />} />
              <Route path="/events/new" element={<EventFormPage />} />
              <Route path="/events/:eventId/edit" element={<EventFormPage />} />
              <Route path="/registrations" element={<RegistrationsPage />} />
              <Route path="/attendees" element={<AttendeesPage />} />
              <Route path="/settings" element={<SettingsPage />} />
            </Route>
          </Route>

          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
