export default function LoadingView({ fullPage = false, message = 'Loading...' }) {
  if (fullPage) {
    return (
      <div className="loading-center">
        <div className="spinner" />
        <p>{message}</p>
      </div>
    );
  }
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '32px 0', justifyContent: 'center' }}>
      <div className="spinner" style={{ width: 22, height: 22, borderWidth: 2 }} />
      <span style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>{message}</span>
    </div>
  );
}
