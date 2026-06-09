import { useEffect } from 'react';
import '../styles/confirm-dialog.css';

// Keyed by the target status value sent to the API
const CONFIGS = {
  published: {
    title:        'Publish Event',
    body:         'Are you sure you want to publish this event? It will become visible to all users.',
    confirmLabel: 'Publish',
    confirmCls:   'btn-primary',
  },
  draft: {
    title:        'Unpublish Event',
    body:         'Are you sure you want to move this event back to draft? It will no longer be visible to users.',
    confirmLabel: 'Unpublish',
    confirmCls:   'btn-ghost cd-btn-unpublish',
  },
  cancelled: {
    title:        'Cancel Event',
    body:         'Are you sure you want to cancel this event? This cannot be undone in Week 2.',
    confirmLabel: 'Cancel Event',
    confirmCls:   'btn-danger',
  },
};

export default function ConfirmDialog({ data, loading, error, onClose, onConfirm }) {
  // Escape-key handler — runs whenever data/loading changes but is guarded inside
  useEffect(() => {
    if (!data) return;
    const handleKey = e => { if (e.key === 'Escape' && !loading) onClose(); };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [data, loading, onClose]);

  if (!data) return null;

  const cfg = CONFIGS[data.status] ?? {
    title: 'Confirm Action', body: 'Are you sure?',
    confirmLabel: 'Confirm', confirmCls: 'btn-primary',
  };

  return (
    <div className="cd-overlay" onClick={() => !loading && onClose()}>
      <div
        className="cd-box"
        onClick={e => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="cd-title"
      >
        <h3 className="cd-title" id="cd-title">{cfg.title}</h3>
        <p className="cd-event-name">"{data.eventTitle}"</p>
        <p className="cd-body">{cfg.body}</p>

        {error && <p className="cd-error">{error}</p>}

        <div className="cd-actions">
          <button className="btn btn-ghost" onClick={onClose} disabled={loading}>
            Cancel
          </button>
          <button
            className={`btn ${cfg.confirmCls}`}
            onClick={onConfirm}
            disabled={loading}
            autoFocus
          >
            {loading ? 'Updating…' : cfg.confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
