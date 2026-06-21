-- Assign orphan projects (created before auth) to the first admin user.
INSERT INTO project_memberships (user_id, project_id, role)
SELECT admin.id, p.id, 'owner'
FROM projects p
CROSS JOIN LATERAL (
  SELECT id FROM dashboard_users WHERE global_role = 'admin' ORDER BY created_at ASC LIMIT 1
) admin
WHERE NOT EXISTS (SELECT 1 FROM project_memberships m WHERE m.project_id = p.id);
