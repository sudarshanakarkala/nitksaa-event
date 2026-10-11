-- 026: Admin revamp step 1 — two admin levels.
--
--   event_users.is_admin          overall admin (sees and manages everything)
--   event_users.is_event_creator  may create events (overall admins always may)
--
-- Event admins stay in event_members (role = 'event_admin', status = 'active');
-- this migration backfills every event's creator as its event admin.
--
-- Additive only: the running API ignores the new columns until the
-- feat/admin-roles backend is deployed.
--
-- After running, set the current overall admins by hand:
--   UPDATE event_users SET is_admin = true
--   WHERE firebase_uid IN ('<uid>', '<uid>');

ALTER TABLE event_users
  ADD COLUMN IF NOT EXISTS is_admin         BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_event_creator BOOLEAN NOT NULL DEFAULT false;

-- Every event's creator becomes its event admin (keeps any existing row).
INSERT INTO event_members (event_id, firebase_uid, role, status)
SELECT e.event_id, e.created_by_firebase_uid, 'event_admin', 'active'
FROM events e
JOIN event_users u ON u.firebase_uid = e.created_by_firebase_uid
ON CONFLICT (event_id, firebase_uid) DO NOTHING;
