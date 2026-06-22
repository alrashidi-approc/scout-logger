const assignableProjectRoles = ['qa', 'developer', 'support', 'project_manager'];

String projectRoleLabel(String role) => switch (role) {
      'owner' => 'Owner',
      'qa' => 'QA',
      'developer' => 'Developer',
      'support' => 'Support',
      'project_manager' => 'Project manager',
      'admin' => 'Admin',
      'member' => 'Member',
      'viewer' => 'Viewer',
      _ => role,
    };
