import Card from '../components/Card';

const PLANNED_APIS = [
  { method: 'POST', path: '/api/v1/events/{id}/register',        desc: 'Register attendee' },
  { method: 'GET',  path: '/api/v1/events/{id}/my-registration', desc: 'Check registration status' },
];

export default function RegistrationsPage() {
  return (
    <div>
      <p className="page-eyebrow">Week 4</p>
      <h1 className="page-heading">Registrations</h1>
      <p className="page-sub">Registration backend is live. Admin UI for viewing and managing registrations per event is coming in Week 4.</p>

      <Card className="placeholder-page-card">
        <div className="notice notice--info placeholder-notice">
          <span>📋</span>
          <span>Registration APIs are live (Week 3). This page will display and manage attendee registrations per event — coming in Week 4.</span>
        </div>

        <div className="planned-apis">
          <h4>Live APIs</h4>
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
