import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';

import '../auth/auth_principal.dart';
import '../db/scout_db.dart';
import '../services/key_cipher.dart';
import '../util/ids.dart';

class AuthStore {
  AuthStore(this.db, {required this.cipher});

  final ScoutDb db;
  final KeyCipher cipher;

  Future<int> userCount() async {
    final conn = await db.connect();
    final rows = await conn.execute('SELECT COUNT(*)::int FROM dashboard_users');
    return rows.first[0] as int;
  }

  Future<Map<String, dynamic>?> findUserByEmail(String email) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT id, email, password_hash, display_name, global_role, can_create_projects, email_verified_at, created_at FROM dashboard_users WHERE lower(email) = lower(@email)'),
      parameters: {'email': email.trim()},
    );
    if (rows.isEmpty) return null;
    return _userRow(rows.first);
  }

  Future<Map<String, dynamic>?> findUserById(String id) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT id, email, password_hash, display_name, global_role, can_create_projects, email_verified_at, created_at FROM dashboard_users WHERE id = @id'),
      parameters: {'id': id},
    );
    if (rows.isEmpty) return null;
    return _userRow(rows.first);
  }

  Future<List<Map<String, dynamic>>> listUsers() async {
    final conn = await db.connect();
    final rows = await conn.execute('''
      SELECT u.id, u.email, u.display_name, u.global_role, u.can_create_projects, u.email_verified_at, u.created_at,
             (SELECT COUNT(*)::int FROM project_memberships m WHERE m.user_id = u.id) AS project_count
      FROM dashboard_users u
      ORDER BY u.created_at ASC
    ''');
    return rows
        .map((r) => {
              'id': r[0],
              'email': r[1],
              'displayName': r[2],
              'globalRole': r[3],
              'canCreateProjects': r[4] as bool,
              'emailVerified': r[5] != null,
              'createdAt': (r[6] as DateTime).toUtc().toIso8601String(),
              'projectCount': r[7],
            })
        .toList();
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? displayName,
    bool autoVerify = false,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) throw ArgumentError('Valid email required');
    if (password.length < 8) throw ArgumentError('Password must be at least 8 characters');

    final conn = await db.connect();
    final existing = await findUserByEmail(normalized);
    if (existing != null) throw ArgumentError('Email already registered');

    final count = await userCount();
    final isFirst = count == 0;
    final id = newId();
    final hash = BCrypt.hashpw(password, BCrypt.gensalt());
    final role = isFirst ? 'admin' : 'user';
    final canCreate = isFirst;

    await conn.execute(
      Sql.named('''
        INSERT INTO dashboard_users (id, email, password_hash, display_name, global_role, can_create_projects, email_verified_at)
        VALUES (@id, @email, @hash, @name, @role, @canCreate, @verified)
      '''),
      parameters: {
        'id': id,
        'email': normalized,
        'hash': hash,
        'name': displayName?.trim().isEmpty == true ? null : displayName?.trim(),
        'role': role,
        'canCreate': canCreate,
        'verified': autoVerify ? DateTime.now().toUtc() : null,
      },
    );

    return (await findUserById(id))!;
  }

  bool verifyPassword(String password, String hash) => BCrypt.checkpw(password, hash);

  Future<String> createVerificationToken(String userId) async {
    final conn = await db.connect();
    final token = newToken();
    final id = newId();
    await conn.execute('DELETE FROM email_verification_tokens WHERE user_id = @uid', parameters: {'uid': userId});
    await conn.execute(
      Sql.named('''
        INSERT INTO email_verification_tokens (id, user_id, token_hash, expires_at)
        VALUES (@id, @uid, @hash, now() + interval '24 hours')
      '''),
      parameters: {'id': id, 'uid': userId, 'hash': hashToken(token)},
    );
    return token;
  }

  Future<Map<String, dynamic>?> verifyEmail(String token) async {
    final conn = await db.connect();
    final hash = hashToken(token);
    final rows = await conn.execute(
      Sql.named('''
        SELECT t.user_id FROM email_verification_tokens t
        WHERE t.token_hash = @hash AND t.expires_at > now()
        LIMIT 1
      '''),
      parameters: {'hash': hash},
    );
    if (rows.isEmpty) return null;
    final userId = rows.first[0] as String;
    await conn.execute(
      Sql.named('UPDATE dashboard_users SET email_verified_at = now() WHERE id = @id'),
      parameters: {'id': userId},
    );
    await conn.execute('DELETE FROM email_verification_tokens WHERE user_id = @uid', parameters: {'uid': userId});
    return findUserById(userId);
  }

  Future<void> addProjectOwner(String userId, String projectId) async {
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        INSERT INTO project_memberships (user_id, project_id, role)
        VALUES (@uid, @pid, 'owner')
        ON CONFLICT DO NOTHING
      '''),
      parameters: {'uid': userId, 'pid': projectId},
    );
  }

  Future<String?> membershipRole(String userId, String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT role FROM project_memberships WHERE user_id = @uid AND project_id = @pid'),
      parameters: {'uid': userId, 'pid': projectId},
    );
    if (rows.isEmpty) return null;
    return rows.first[0] as String;
  }

  Future<Map<String, dynamic>> updateUser({
    required String userId,
    String? globalRole,
    bool? canCreateProjects,
    String? displayName,
  }) async {
    final conn = await db.connect();
    if (globalRole != null) {
      await conn.execute(
        Sql.named('UPDATE dashboard_users SET global_role = @role WHERE id = @id'),
        parameters: {'role': globalRole, 'id': userId},
      );
    }
    if (canCreateProjects != null) {
      await conn.execute(
        Sql.named('UPDATE dashboard_users SET can_create_projects = @v WHERE id = @id'),
        parameters: {'v': canCreateProjects, 'id': userId},
      );
    }
    if (displayName != null) {
      await conn.execute(
        Sql.named('UPDATE dashboard_users SET display_name = @n WHERE id = @id'),
        parameters: {'n': displayName.trim().isEmpty ? null : displayName.trim(), 'id': userId},
      );
    }
    return (await findUserById(userId))!;
  }

  AuthPrincipal toPrincipal(Map<String, dynamic> user) => AuthPrincipal(
        userId: user['id'] as String,
        email: user['email'] as String,
        globalRole: user['globalRole'] as String,
        canCreateProjects: user['canCreateProjects'] as bool,
      );

  Map<String, dynamic> publicUser(Map<String, dynamic> user) => {
        'id': user['id'],
        'email': user['email'],
        'displayName': user['displayName'],
        'globalRole': user['globalRole'],
        'canCreateProjects': user['canCreateProjects'] as bool || user['globalRole'] == 'admin',
        'emailVerified': user['emailVerified'] as bool,
        'createdAt': user['createdAt'],
      };

  Map<String, dynamic> _userRow(ResultRow r) => {
        'id': r[0] as String,
        'email': r[1] as String,
        'passwordHash': r[2] as String,
        'displayName': r[3] as String?,
        'globalRole': r[4] as String,
        'canCreateProjects': r[5] as bool,
        'emailVerified': r[6] != null,
        'emailVerifiedAt': r[6],
        'createdAt': (r[7] as DateTime).toUtc().toIso8601String(),
      };
}
