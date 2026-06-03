import Card from '../components/Card';

const PLANNED_APIS = [
  { method: 'GET', path: '/api/v1/events/{id}/attendees',        desc: 'List confirmed attendees' },
  { method: 'GET', path: '/api/v1/events/{id}/attendees/export', desc: 'Export attendees as CSV' },
];

export default function AttendeesPage() {
  return (
    <div>
      <p className="page-eyebrow">Coming in Week 4</p>
      <h1 className="page-heading">Attendees</h1>
      <p className="page-sub">Admin can manage attendees. Full end-to-end stable. Demo-ready.</p>

      <Card className="placeholder-page-card">
        <div className="notice notice--info placeholder-notice">
          <span>👥</span>
          <span>Attendee management APIs will be implemented in Week 4. This page will show a searchable attendee table and provide CSV export.</span>
        </div>

        <div className="planned-apis">
          <h4>Planned APIs</h4>
          <div className="planned-apis-list">
            {PLANNED_APIS.map(api => (
              <div key={`${api.method}-${api.path}`} className="planned-api-row">
                <span className="api-method">{api.method}</span>
                <span className="api-path">{api.path}</span>
                <span className="api-desc">{api.desc}</span>
              </div>
            ))}
          </div>
        </div>
      </Card>
    </div>
  );
}
