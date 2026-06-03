export default function ErrorView({ message, onRetry }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, padding: '32px 0' }}>
      <p className="error-msg" style={{ maxWidth: 480, textAlign: 'center' }}>
        {message || 'Something went wrong.'}
      </p>
      {onRetry && (
        <button className="btn btn-ghost" onClick={onRetry}>
          Retry
        </button>
      )}
    </div>
  );
}
