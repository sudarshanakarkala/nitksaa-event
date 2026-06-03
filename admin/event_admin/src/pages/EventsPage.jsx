import Card from '../components/Card';

const PLANNED_APIS = [
  { method: 'GET',   path: '/api/v1/events',             desc: 'List published events' },
  { method: 'GET',   path: '/api/v1/events/{slug}',      desc: 'Event detail' },
  { method: 'POST',  path: '/api/v1/events',             desc: 'Create event (staff)' },
  { method: 'PATCH', path: '/api/v1/events/{id}/status', desc: 'Publish / unpublish' },
];

export default function EventsPage() {
  return (
    <div>
      <p className="page-eyebrow">Coming in Week 2</p>
      <h1 className="page-heading">Events</h1>
      <p className="page-sub">Staff can create events. Public can browse and view details.</p>

      <Card className="placeholder-page-card">
        <div className="notice notice--info placeholder-notice">
          <span>📅</span>
          <span>Event management APIs will be implemented in Week 2. This page will allow staff to create, publish, and manage events.</span>
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
