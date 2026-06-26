import { useCallback, useEffect, useState } from 'react';
import {
  createPartner, createPerson, createSponsor,
  deletePartner, deletePerson, deleteSponsor,
  listPartners, listPeople, listSponsors,
  updatePartner, updatePerson, updateSponsor,
} from '../api/enrichmentApi';
import '../styles/enrichment.css';

// ── Constants ──────────────────────────────────────────────────────────────────

const PEOPLE_ROLES = [
  'HOST', 'MODERATOR', 'SPEAKER', 'PANELIST',
  'CHIEF_GUEST', 'GUEST_OF_HONOUR', 'ORGANIZER',
];

const SPONSOR_TYPES = [
  'TITLE_SPONSOR', 'GOLD_SPONSOR', 'SILVER_SPONSOR',
  'BRONZE_SPONSOR', 'ASSOCIATE_SPONSOR',
];

const PARTNER_TYPES = [
  'COMMUNITY_PARTNER', 'KNOWLEDGE_PARTNER', 'MEDIA_PARTNER',
  'VENUE_PARTNER', 'TECHNOLOGY_PARTNER', 'ECOSYSTEM_PARTNER', 'HIRING_PARTNER',
];

const EMPTY_PERSON = {
  fullname: '', role: 'SPEAKER', title: '', organisation: '',
  bio: '', photo_url: '', linkedin_url: '', display_order: 0, is_visible: true,
};

const EMPTY_SPONSOR = {
  name: '', sponsor_type: 'TITLE_SPONSOR', logo_url: '',
  website_url: '', description: '', display_order: 0, is_visible: true,
};

const EMPTY_PARTNER = {
  name: '', partner_type: 'COMMUNITY_PARTNER', logo_url: '',
  website_url: '', description: '', display_order: 0, is_visible: true,
};

// ── Shared helpers ─────────────────────────────────────────────────────────────

function roleLabel(value) {
  return value.replace(/_/g, ' ');
}

function visibilityBadge(visible) {
  return (
    <span className={`enr-badge ${visible ? 'enr-badge--visible' : 'enr-badge--hidden'}`}>
      {visible ? 'Visible' : 'Hidden'}
    </span>
  );
}

// ── People Tab ─────────────────────────────────────────────────────────────────

function PeopleTab({ eventId }) {
  const [items,       setItems]       = useState([]);
  const [loading,     setLoading]     = useState(true);
  const [error,       setError]       = useState(null);
  const [form,        setForm]        = useState(null);   // null = closed, obj = open
  const [editingId,   setEditingId]   = useState(null);
  const [saving,      setSaving]      = useState(false);
  const [formError,   setFormError]   = useState(null);
  const [deleteId,    setDeleteId]    = useState(null);
  const [deleting,    setDeleting]    = useState(false);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    listPeople(eventId)
      .then(data => setItems(Array.isArray(data) ? data : []))
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }, [eventId]);

  useEffect(() => { load(); }, [load]);

  function openAdd() {
    setEditingId(null);
    setForm({ ...EMPTY_PERSON });
    setFormError(null);
  }

  function openEdit(item) {
    setEditingId(item.person_id);
    setForm({
      fullname:      item.fullname      ?? '',
      role:          item.role          ?? 'SPEAKER',
      title:         item.title         ?? '',
      organisation:  item.organisation  ?? '',
      bio:           item.bio           ?? '',
      photo_url:     item.photo_url     ?? '',
      linkedin_url:  item.linkedin_url  ?? '',
      display_order: item.display_order ?? 0,
      is_visible:    item.is_visible    ?? true,
    });
    setFormError(null);
  }

  function closeForm() { setForm(null); setEditingId(null); setFormError(null); }

  function setField(key, value) { setForm(prev => ({ ...prev, [key]: value })); }

  async function handleSave(e) {
    e.preventDefault();
    if (!form.fullname.trim()) { setFormError('Full name is required.'); return; }
    setSaving(true);
    setFormError(null);
    try {
      const payload = {
        fullname:      form.fullname.trim(),
        role:          form.role,
        title:         form.title.trim()        || null,
        organisation:  form.organisation.trim() || null,
        bio:           form.bio.trim()           || null,
        photo_url:     form.photo_url.trim()     || null,
        linkedin_url:  form.linkedin_url.trim()  || null,
        display_order: Number(form.display_order) || 0,
        is_visible:    Boolean(form.is_visible),
      };
      if (editingId) {
        await updatePerson(eventId, editingId, payload);
      } else {
        await createPerson(eventId, payload);
      }
      closeForm();
      load();
    } catch (err) {
      setFormError(err.message);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!deleteId) return;
    setDeleting(true);
    try {
      await deletePerson(eventId, deleteId);
      setDeleteId(null);
      load();
    } catch (err) {
      setError(err.message);
      setDeleteId(null);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div className="enr-tab-body">
      <div className="enr-tab-header">
        <span className="enr-tab-count">{items.length} {items.length === 1 ? 'person' : 'people'}</span>
        {!form && (
          <button className="btn btn-primary btn-sm" onClick={openAdd}>+ Add Person</button>
        )}
      </div>

      {loading && <p className="enr-loading">Loading…</p>}
      {!loading && error && <p className="error-msg">{error}</p>}

      {!loading && !error && items.length === 0 && !form && (
        <p className="enr-empty">No people yet. Add a host, speaker, or panelist to get started.</p>
      )}

      {!loading && !error && items.map(item => (
        editingId === item.person_id ? null : (
          <div key={item.person_id} className="enr-row">
            <div className="enr-row-main">
              <span className="enr-row-name">{item.fullname}</span>
              <span className="enr-row-type">{roleLabel(item.role)}</span>
              {item.title && <span className="enr-row-sub">{item.title}</span>}
              {item.organisation && <span className="enr-row-sub">{item.organisation}</span>}
            </div>
            <div className="enr-row-meta">
              {visibilityBadge(item.is_visible)}
              <span className="enr-row-order">#{item.display_order}</span>
              <button className="btn btn-ghost btn-xs" onClick={() => openEdit(item)}>Edit</button>
              <button className="btn btn-danger btn-xs" onClick={() => setDeleteId(item.person_id)}>Delete</button>
            </div>
          </div>
        )
      ))}

      {form && (
        <form className="enr-form card" onSubmit={handleSave} noValidate>
          <h4 className="enr-form-title">{editingId ? 'Edit Person' : 'Add Person'}</h4>
          {formError && <p className="error-msg">{formError}</p>}

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Full Name <span className="ef-req">*</span></label>
              <input type="text" value={form.fullname}
                onChange={e => setField('fullname', e.target.value)}
                placeholder="Dr. Jane Doe" />
            </div>
            <div className="ef-field">
              <label>Role <span className="ef-req">*</span></label>
              <select value={form.role} onChange={e => setField('role', e.target.value)}>
                {PEOPLE_ROLES.map(r => <option key={r} value={r}>{roleLabel(r)}</option>)}
              </select>
            </div>
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Title / Designation</label>
              <input type="text" value={form.title}
                onChange={e => setField('title', e.target.value)}
                placeholder="Professor of Computer Science" />
            </div>
            <div className="ef-field">
              <label>Organisation</label>
              <input type="text" value={form.organisation}
                onChange={e => setField('organisation', e.target.value)}
                placeholder="NITK Surathkal" />
            </div>
          </div>

          <div className="ef-field">
            <label>Bio</label>
            <textarea rows={3} value={form.bio}
              onChange={e => setField('bio', e.target.value)}
              placeholder="Short biography…" />
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Photo URL</label>
              <input type="url" value={form.photo_url}
                onChange={e => setField('photo_url', e.target.value)}
                placeholder="https://example.com/photo.jpg" />
            </div>
            <div className="ef-field">
              <label>LinkedIn URL</label>
              <input type="url" value={form.linkedin_url}
                onChange={e => setField('linkedin_url', e.target.value)}
                placeholder="https://linkedin.com/in/…" />
            </div>
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Display Order</label>
              <input type="number" min="0" value={form.display_order}
                onChange={e => setField('display_order', e.target.value)} />
            </div>
            <div className="ef-field" style={{ justifyContent: 'flex-end' }}>
              <label className="ef-toggle-option" style={{ marginTop: 20 }}>
                <input type="checkbox" checked={form.is_visible}
                  onChange={e => setField('is_visible', e.target.checked)} />
                <span><strong>Visible publicly</strong></span>
              </label>
            </div>
          </div>

          <div className="enr-form-actions">
            <button type="button" className="btn btn-ghost" onClick={closeForm} disabled={saving}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Saving…' : (editingId ? 'Update Person' : 'Add Person')}
            </button>
          </div>
        </form>
      )}

      {deleteId && (
        <div className="enr-confirm-overlay">
          <div className="enr-confirm card">
            <p>Delete this person? This cannot be undone.</p>
            <div className="enr-form-actions">
              <button className="btn btn-ghost" onClick={() => setDeleteId(null)} disabled={deleting}>Cancel</button>
              <button className="btn btn-danger" onClick={handleDelete} disabled={deleting}>
                {deleting ? 'Deleting…' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Sponsors Tab ───────────────────────────────────────────────────────────────

function SponsorsTab({ eventId }) {
  const [items,       setItems]       = useState([]);
  const [loading,     setLoading]     = useState(true);
  const [error,       setError]       = useState(null);
  const [form,        setForm]        = useState(null);
  const [editingId,   setEditingId]   = useState(null);
  const [saving,      setSaving]      = useState(false);
  const [formError,   setFormError]   = useState(null);
  const [deleteId,    setDeleteId]    = useState(null);
  const [deleting,    setDeleting]    = useState(false);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    listSponsors(eventId)
      .then(data => setItems(Array.isArray(data) ? data : []))
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }, [eventId]);

  useEffect(() => { load(); }, [load]);

  function openAdd() { setEditingId(null); setForm({ ...EMPTY_SPONSOR }); setFormError(null); }

  function openEdit(item) {
    setEditingId(item.sponsor_id);
    setForm({
      name:          item.name          ?? '',
      sponsor_type:  item.sponsor_type  ?? 'TITLE_SPONSOR',
      logo_url:      item.logo_url      ?? '',
      website_url:   item.website_url   ?? '',
      description:   item.description   ?? '',
      display_order: item.display_order ?? 0,
      is_visible:    item.is_visible    ?? true,
    });
    setFormError(null);
  }

  function closeForm() { setForm(null); setEditingId(null); setFormError(null); }
  function setField(key, value) { setForm(prev => ({ ...prev, [key]: value })); }

  async function handleSave(e) {
    e.preventDefault();
    if (!form.name.trim()) { setFormError('Sponsor name is required.'); return; }
    setSaving(true);
    setFormError(null);
    try {
      const payload = {
        name:          form.name.trim(),
        sponsor_type:  form.sponsor_type,
        logo_url:      form.logo_url.trim()    || null,
        website_url:   form.website_url.trim() || null,
        description:   form.description.trim() || null,
        display_order: Number(form.display_order) || 0,
        is_visible:    Boolean(form.is_visible),
      };
      if (editingId) {
        await updateSponsor(eventId, editingId, payload);
      } else {
        await createSponsor(eventId, payload);
      }
      closeForm();
      load();
    } catch (err) {
      setFormError(err.message);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!deleteId) return;
    setDeleting(true);
    try {
      await deleteSponsor(eventId, deleteId);
      setDeleteId(null);
      load();
    } catch (err) {
      setError(err.message);
      setDeleteId(null);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div className="enr-tab-body">
      <div className="enr-tab-header">
        <span className="enr-tab-count">{items.length} {items.length === 1 ? 'sponsor' : 'sponsors'}</span>
        {!form && (
          <button className="btn btn-primary btn-sm" onClick={openAdd}>+ Add Sponsor</button>
        )}
      </div>

      {loading && <p className="enr-loading">Loading…</p>}
      {!loading && error && <p className="error-msg">{error}</p>}

      {!loading && !error && items.length === 0 && !form && (
        <p className="enr-empty">No sponsors yet.</p>
      )}

      {!loading && !error && items.map(item => (
        editingId === item.sponsor_id ? null : (
          <div key={item.sponsor_id} className="enr-row">
            <div className="enr-row-main">
              <span className="enr-row-name">{item.name}</span>
              <span className="enr-row-type">{roleLabel(item.sponsor_type)}</span>
              {item.website_url && <a className="enr-row-link" href={item.website_url} target="_blank" rel="noopener noreferrer">{item.website_url}</a>}
            </div>
            <div className="enr-row-meta">
              {visibilityBadge(item.is_visible)}
              <span className="enr-row-order">#{item.display_order}</span>
              <button className="btn btn-ghost btn-xs" onClick={() => openEdit(item)}>Edit</button>
              <button className="btn btn-danger btn-xs" onClick={() => setDeleteId(item.sponsor_id)}>Delete</button>
            </div>
          </div>
        )
      ))}

      {form && (
        <form className="enr-form card" onSubmit={handleSave} noValidate>
          <h4 className="enr-form-title">{editingId ? 'Edit Sponsor' : 'Add Sponsor'}</h4>
          {formError && <p className="error-msg">{formError}</p>}

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Sponsor Name <span className="ef-req">*</span></label>
              <input type="text" value={form.name}
                onChange={e => setField('name', e.target.value)}
                placeholder="Acme Corporation" />
            </div>
            <div className="ef-field">
              <label>Sponsor Type <span className="ef-req">*</span></label>
              <select value={form.sponsor_type} onChange={e => setField('sponsor_type', e.target.value)}>
                {SPONSOR_TYPES.map(t => <option key={t} value={t}>{roleLabel(t)}</option>)}
              </select>
            </div>
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Logo URL</label>
              <input type="url" value={form.logo_url}
                onChange={e => setField('logo_url', e.target.value)}
                placeholder="https://example.com/logo.png" />
            </div>
            <div className="ef-field">
              <label>Website URL</label>
              <input type="url" value={form.website_url}
                onChange={e => setField('website_url', e.target.value)}
                placeholder="https://acme.com" />
            </div>
          </div>

          <div className="ef-field">
            <label>Description</label>
            <textarea rows={2} value={form.description}
              onChange={e => setField('description', e.target.value)}
              placeholder="Brief description of the sponsorship…" />
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Display Order</label>
              <input type="number" min="0" value={form.display_order}
                onChange={e => setField('display_order', e.target.value)} />
              <span className="ef-hint">Within same tier, lower order = first.</span>
            </div>
            <div className="ef-field" style={{ justifyContent: 'flex-end' }}>
              <label className="ef-toggle-option" style={{ marginTop: 20 }}>
                <input type="checkbox" checked={form.is_visible}
                  onChange={e => setField('is_visible', e.target.checked)} />
                <span><strong>Visible publicly</strong></span>
              </label>
            </div>
          </div>

          <div className="enr-form-actions">
            <button type="button" className="btn btn-ghost" onClick={closeForm} disabled={saving}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Saving…' : (editingId ? 'Update Sponsor' : 'Add Sponsor')}
            </button>
          </div>
        </form>
      )}

      {deleteId && (
        <div className="enr-confirm-overlay">
          <div className="enr-confirm card">
            <p>Delete this sponsor? This cannot be undone.</p>
            <div className="enr-form-actions">
              <button className="btn btn-ghost" onClick={() => setDeleteId(null)} disabled={deleting}>Cancel</button>
              <button className="btn btn-danger" onClick={handleDelete} disabled={deleting}>
                {deleting ? 'Deleting…' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Partners Tab ───────────────────────────────────────────────────────────────

function PartnersTab({ eventId }) {
  const [items,       setItems]       = useState([]);
  const [loading,     setLoading]     = useState(true);
  const [error,       setError]       = useState(null);
  const [form,        setForm]        = useState(null);
  const [editingId,   setEditingId]   = useState(null);
  const [saving,      setSaving]      = useState(false);
  const [formError,   setFormError]   = useState(null);
  const [deleteId,    setDeleteId]    = useState(null);
  const [deleting,    setDeleting]    = useState(false);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    listPartners(eventId)
      .then(data => setItems(Array.isArray(data) ? data : []))
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }, [eventId]);

  useEffect(() => { load(); }, [load]);

  function openAdd() { setEditingId(null); setForm({ ...EMPTY_PARTNER }); setFormError(null); }

  function openEdit(item) {
    setEditingId(item.partner_id);
    setForm({
      name:          item.name          ?? '',
      partner_type:  item.partner_type  ?? 'COMMUNITY_PARTNER',
      logo_url:      item.logo_url      ?? '',
      website_url:   item.website_url   ?? '',
      description:   item.description   ?? '',
      display_order: item.display_order ?? 0,
      is_visible:    item.is_visible    ?? true,
    });
    setFormError(null);
  }

  function closeForm() { setForm(null); setEditingId(null); setFormError(null); }
  function setField(key, value) { setForm(prev => ({ ...prev, [key]: value })); }

  async function handleSave(e) {
    e.preventDefault();
    if (!form.name.trim()) { setFormError('Partner name is required.'); return; }
    setSaving(true);
    setFormError(null);
    try {
      const payload = {
        name:          form.name.trim(),
        partner_type:  form.partner_type,
        logo_url:      form.logo_url.trim()    || null,
        website_url:   form.website_url.trim() || null,
        description:   form.description.trim() || null,
        display_order: Number(form.display_order) || 0,
        is_visible:    Boolean(form.is_visible),
      };
      if (editingId) {
        await updatePartner(eventId, editingId, payload);
      } else {
        await createPartner(eventId, payload);
      }
      closeForm();
      load();
    } catch (err) {
      setFormError(err.message);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!deleteId) return;
    setDeleting(true);
    try {
      await deletePartner(eventId, deleteId);
      setDeleteId(null);
      load();
    } catch (err) {
      setError(err.message);
      setDeleteId(null);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div className="enr-tab-body">
      <div className="enr-tab-header">
        <span className="enr-tab-count">{items.length} {items.length === 1 ? 'partner' : 'partners'}</span>
        {!form && (
          <button className="btn btn-primary btn-sm" onClick={openAdd}>+ Add Partner</button>
        )}
      </div>

      {loading && <p className="enr-loading">Loading…</p>}
      {!loading && error && <p className="error-msg">{error}</p>}

      {!loading && !error && items.length === 0 && !form && (
        <p className="enr-empty">No partners yet.</p>
      )}

      {!loading && !error && items.map(item => (
        editingId === item.partner_id ? null : (
          <div key={item.partner_id} className="enr-row">
            <div className="enr-row-main">
              <span className="enr-row-name">{item.name}</span>
              <span className="enr-row-type">{roleLabel(item.partner_type)}</span>
              {item.website_url && <a className="enr-row-link" href={item.website_url} target="_blank" rel="noopener noreferrer">{item.website_url}</a>}
            </div>
            <div className="enr-row-meta">
              {visibilityBadge(item.is_visible)}
              <span className="enr-row-order">#{item.display_order}</span>
              <button className="btn btn-ghost btn-xs" onClick={() => openEdit(item)}>Edit</button>
              <button className="btn btn-danger btn-xs" onClick={() => setDeleteId(item.partner_id)}>Delete</button>
            </div>
          </div>
        )
      ))}

      {form && (
        <form className="enr-form card" onSubmit={handleSave} noValidate>
          <h4 className="enr-form-title">{editingId ? 'Edit Partner' : 'Add Partner'}</h4>
          {formError && <p className="error-msg">{formError}</p>}

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Partner Name <span className="ef-req">*</span></label>
              <input type="text" value={form.name}
                onChange={e => setField('name', e.target.value)}
                placeholder="NITK Alumni Association" />
            </div>
            <div className="ef-field">
              <label>Partner Type <span className="ef-req">*</span></label>
              <select value={form.partner_type} onChange={e => setField('partner_type', e.target.value)}>
                {PARTNER_TYPES.map(t => <option key={t} value={t}>{roleLabel(t)}</option>)}
              </select>
            </div>
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Logo URL</label>
              <input type="url" value={form.logo_url}
                onChange={e => setField('logo_url', e.target.value)}
                placeholder="https://example.com/logo.png" />
            </div>
            <div className="ef-field">
              <label>Website URL</label>
              <input type="url" value={form.website_url}
                onChange={e => setField('website_url', e.target.value)}
                placeholder="https://nitkalumni.org" />
            </div>
          </div>

          <div className="ef-field">
            <label>Description</label>
            <textarea rows={2} value={form.description}
              onChange={e => setField('description', e.target.value)}
              placeholder="Brief description of the partnership…" />
          </div>

          <div className="ef-field-row">
            <div className="ef-field">
              <label>Display Order</label>
              <input type="number" min="0" value={form.display_order}
                onChange={e => setField('display_order', e.target.value)} />
              <span className="ef-hint">Within same type, lower order = first.</span>
            </div>
            <div className="ef-field" style={{ justifyContent: 'flex-end' }}>
              <label className="ef-toggle-option" style={{ marginTop: 20 }}>
                <input type="checkbox" checked={form.is_visible}
                  onChange={e => setField('is_visible', e.target.checked)} />
                <span><strong>Visible publicly</strong></span>
              </label>
            </div>
          </div>

          <div className="enr-form-actions">
            <button type="button" className="btn btn-ghost" onClick={closeForm} disabled={saving}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Saving…' : (editingId ? 'Update Partner' : 'Add Partner')}
            </button>
          </div>
        </form>
      )}

      {deleteId && (
        <div className="enr-confirm-overlay">
          <div className="enr-confirm card">
            <p>Delete this partner? This cannot be undone.</p>
            <div className="enr-form-actions">
              <button className="btn btn-ghost" onClick={() => setDeleteId(null)} disabled={deleting}>Cancel</button>
              <button className="btn btn-danger" onClick={handleDelete} disabled={deleting}>
                {deleting ? 'Deleting…' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── EventEnrichmentPanel ───────────────────────────────────────────────────────

const TABS = [
  { key: 'people',   label: 'People / Speakers' },
  { key: 'sponsors', label: 'Sponsors' },
  { key: 'partners', label: 'Partners' },
];

export default function EventEnrichmentPanel({ eventId }) {
  const [activeTab, setActiveTab] = useState('people');

  return (
    <div className="enr-panel card">
      <div className="enr-panel-header">
        <h3 className="ef-section-title" style={{ marginBottom: 0 }}>Event Enrichment</h3>
        <p className="enr-panel-sub">
          Manage people, sponsors, and partners for this event. Changes appear immediately in the public event detail.
        </p>
      </div>

      <div className="enr-tabs">
        {TABS.map(tab => (
          <button
            key={tab.key}
            type="button"
            className={`enr-tab${activeTab === tab.key ? ' enr-tab--active' : ''}`}
            onClick={() => setActiveTab(tab.key)}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className="enr-tab-content">
        {activeTab === 'people'   && <PeopleTab   eventId={eventId} />}
        {activeTab === 'sponsors' && <SponsorsTab  eventId={eventId} />}
        {activeTab === 'partners' && <PartnersTab  eventId={eventId} />}
      </div>
    </div>
  );
}
