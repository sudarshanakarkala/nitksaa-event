const statusMap = {
  ok:          { label: 'OK',          cls: 'badge-active' },
  active:      { label: 'Active',      cls: 'badge-active' },
  confirmed:   { label: 'Confirmed',   cls: 'badge-active' },
  published:   { label: 'Published',   cls: 'badge-active' },
  pending:     { label: 'Pending',     cls: 'badge-pending' },
  draft:       { label: 'Draft',       cls: 'badge-pending' },
  error:       { label: 'Error',       cls: 'badge-blocked' },
  blocked:     { label: 'Blocked',     cls: 'badge-blocked' },
  cancelled:   { label: 'Cancelled',   cls: 'badge-blocked' },
  unknown:     { label: 'Unknown',     cls: 'badge-unregistered' },
  placeholder: { label: 'Coming Soon', cls: 'badge-unregistered' },
};

export default function StatusBadge({ status, label }) {
  const config = statusMap[status?.toLowerCase()] ?? {
    label: label || status || 'Unknown',
    cls:   'badge-unregistered',
  };
  return (
    <span className={`badge ${config.cls}`}>
      {label || config.label}
    </span>
  );
}
