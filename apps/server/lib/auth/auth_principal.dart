class AuthPrincipal {
  const AuthPrincipal({
    this.userId,
    this.email,
    this.globalRole = 'user',
    this.canCreateProjects = false,
    this.apiKeyBypass = false,
  });

  final String? userId;
  final String? email;
  final String globalRole;
  final bool canCreateProjects;
  final bool apiKeyBypass;

  bool get isAdmin => globalRole == 'admin' || apiKeyBypass;
  bool get canCreateApps => isAdmin || canCreateProjects;

  static AuthPrincipal apiKey() => const AuthPrincipal(apiKeyBypass: true);

  Map<String, dynamic> toJson() => {
        'id': userId,
        'email': email,
        'globalRole': isAdmin && apiKeyBypass ? 'admin' : globalRole,
        'canCreateProjects': canCreateApps,
        'emailVerified': true,
      };
}

const projectRoles = {'owner', 'admin', 'member', 'viewer', 'qa', 'developer', 'support', 'project_manager'};

/// Roles an owner can assign when inviting dashboard users to a project.
const assignableProjectRoles = {'qa', 'developer', 'support', 'project_manager'};

const writeProjectRoles = {
  'owner',
  'admin',
  'member',
  'developer',
  'qa',
  'project_manager',
};

bool isAssignableProjectRole(String role) => assignableProjectRoles.contains(role);

bool canAccessProject(AuthPrincipal auth, String? membershipRole) =>
    auth.isAdmin || membershipRole != null;

bool canWriteProject(AuthPrincipal auth, String? membershipRole) =>
    auth.isAdmin || (membershipRole != null && writeProjectRoles.contains(membershipRole));

bool canViewCredentials(AuthPrincipal auth, String? membershipRole) =>
    auth.isAdmin || membershipRole != null;

bool canDeleteProject(AuthPrincipal auth, String? membershipRole) =>
    auth.isAdmin || membershipRole == 'owner';

bool canManageProjectMembers(AuthPrincipal auth, String? membershipRole) =>
    auth.isAdmin || membershipRole == 'owner';

bool canManageProjectNotifications(AuthPrincipal auth, String? membershipRole) =>
    auth.isAdmin || membershipRole == 'owner';

bool isPlatformOwner(AuthPrincipal auth, String platformOwnerEmail) =>
    auth.isAdmin || auth.email?.toLowerCase() == platformOwnerEmail.toLowerCase();
