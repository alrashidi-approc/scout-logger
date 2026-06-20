/// Transport type — how the server routes and stores the event.
const kEventTypes = {'error', 'crash', 'network', 'span', 'session', 'log'};

/// Severity shown in dashboard (error, info, warning, success).
const kEventLevels = {'error', 'info', 'warning', 'success'};

/// Error grouping — network, system, crashing, etc.
const kErrorCategories = {'network', 'system', 'crashing', 'logic', 'ui'};

const kIssueTypes = {'error', 'crash', 'network'};

bool isKnownEventType(String type) => kEventTypes.contains(type);

bool groupsIntoIssue(String type) => kIssueTypes.contains(type);

bool isKnownEventLevel(String level) => kEventLevels.contains(level);

bool isKnownErrorCategory(String category) => kErrorCategories.contains(category);

/// Maps level + category to ingest transport type.
String ingestTypeFor({required String level, String? category}) {
  if (level == 'error' && category == 'crashing') return 'crash';
  if (level == 'error' && category == 'network') return 'network';
  if (level == 'error') return 'error';
  return 'log';
}
