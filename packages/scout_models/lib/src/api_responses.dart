class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdAt,
    this.eventCount = 0,
    this.issueCount = 0,
    this.lastEventAt,
  });

  final String id;
  final String name;
  final String slug;
  final String createdAt;
  final int eventCount;
  final int issueCount;
  final String? lastEventAt;

  factory ProjectSummary.fromJson(Map<String, dynamic> json) => ProjectSummary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        eventCount: json['eventCount'] as int? ?? 0,
        issueCount: json['issueCount'] as int? ?? 0,
        lastEventAt: json['lastEventAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'createdAt': createdAt,
        'eventCount': eventCount,
        'issueCount': issueCount,
        if (lastEventAt != null) 'lastEventAt': lastEventAt,
      };
}

class IssueSummary {
  const IssueSummary({
    required this.id,
    required this.fingerprint,
    required this.type,
    required this.title,
    required this.status,
    required this.eventCount,
    required this.affectedUsers,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.topCountry,
  });

  final String id;
  final String fingerprint;
  final String type;
  final String title;
  final String status;
  final int eventCount;
  final int affectedUsers;
  final String firstSeenAt;
  final String lastSeenAt;
  final String? topCountry;

  factory IssueSummary.fromJson(Map<String, dynamic> json) => IssueSummary(
        id: json['id'] as String? ?? '',
        fingerprint: json['fingerprint'] as String? ?? '',
        type: json['type'] as String? ?? 'error',
        title: json['title'] as String? ?? 'Unknown',
        status: json['status'] as String? ?? 'open',
        eventCount: json['eventCount'] as int? ?? 0,
        affectedUsers: json['affectedUsers'] as int? ?? 0,
        firstSeenAt: json['firstSeenAt'] as String? ?? '',
        lastSeenAt: json['lastSeenAt'] as String? ?? '',
        topCountry: json['topCountry'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'type': type,
        'title': title,
        'status': status,
        'eventCount': eventCount,
        'affectedUsers': affectedUsers,
        'firstSeenAt': firstSeenAt,
        'lastSeenAt': lastSeenAt,
        if (topCountry != null) 'topCountry': topCountry,
      };
}

class EventSummary {
  const EventSummary({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.issueId,
    this.userId,
    this.release,
    this.country,
    this.message,
  });

  final String id;
  final String type;
  final String occurredAt;
  final String? issueId;
  final String? userId;
  final String? release;
  final String? country;
  final String? message;

  factory EventSummary.fromJson(Map<String, dynamic> json) => EventSummary(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        occurredAt: json['occurredAt'] as String? ?? '',
        issueId: json['issueId'] as String?,
        userId: json['userId'] as String?,
        release: json['release'] as String?,
        country: json['country'] as String?,
        message: json['message'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'occurredAt': occurredAt,
        if (issueId != null) 'issueId': issueId,
        if (userId != null) 'userId': userId,
        if (release != null) 'release': release,
        if (country != null) 'country': country,
        if (message != null) 'message': message,
      };
}

class GeoBucket {
  const GeoBucket({required this.country, required this.count, this.countryName});

  final String country;
  final int count;
  final String? countryName;

  factory GeoBucket.fromJson(Map<String, dynamic> json) => GeoBucket(
        country: json['country'] as String? ?? '??',
        count: json['count'] as int? ?? 0,
        countryName: json['countryName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'country': country,
        'count': count,
        if (countryName != null) 'countryName': countryName,
      };
}

class ProjectOverview {
  const ProjectOverview({
    required this.project,
    required this.eventsToday,
    required this.errorsToday,
    required this.crashesToday,
    required this.openIssues,
    required this.uniqueUsersToday,
    required this.topCountries,
    required this.byRelease,
  });

  final ProjectSummary project;
  final int eventsToday;
  final int errorsToday;
  final int crashesToday;
  final int openIssues;
  final int uniqueUsersToday;
  final List<GeoBucket> topCountries;
  final List<Map<String, dynamic>> byRelease;

  factory ProjectOverview.fromJson(Map<String, dynamic> json) {
    final countries = (json['topCountries'] as List? ?? [])
        .map((e) => GeoBucket.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return ProjectOverview(
      project: ProjectSummary.fromJson(Map<String, dynamic>.from(json['project'] as Map? ?? {})),
      eventsToday: json['eventsToday'] as int? ?? 0,
      errorsToday: json['errorsToday'] as int? ?? 0,
      crashesToday: json['crashesToday'] as int? ?? 0,
      openIssues: json['openIssues'] as int? ?? 0,
      uniqueUsersToday: json['uniqueUsersToday'] as int? ?? 0,
      topCountries: countries,
      byRelease: (json['byRelease'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
