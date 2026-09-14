/// Data models matching the JSON shapes of the self-hosted
/// `foundryvtt-rest-api-relay` (Go rewrite). Shapes were confirmed against
/// the relay's own source (go-relay/internal/handler) and its documented
/// examples (docs/examples/*.json), not guessed — see README.md for links.
library;

class FoundryClientInfo {
  final String clientId;
  final String worldTitle;
  final String systemTitle;
  final String? systemId;
  final bool isOnline;

  FoundryClientInfo({
    required this.clientId,
    required this.worldTitle,
    required this.systemTitle,
    required this.systemId,
    required this.isOnline,
  });

  factory FoundryClientInfo.fromJson(Map<String, dynamic> json) {
    return FoundryClientInfo(
      clientId: json['clientId'] as String? ?? '',
      worldTitle: json['worldTitle'] as String? ?? json['worldId'] as String? ?? 'Onbekende wereld',
      systemTitle: json['systemTitle'] as String? ?? json['systemId'] as String? ?? '',
      systemId: json['systemId'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }
}

class SearchResult {
  final String uuid;
  final String id;
  final String name;
  final String documentType;
  final String? subType;

  SearchResult({
    required this.uuid,
    required this.id,
    required this.name,
    required this.documentType,
    required this.subType,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      uuid: json['uuid'] as String? ?? '',
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '(zonder naam)',
      documentType: json['documentType'] as String? ?? '',
      subType: json['subType'] as String?,
    );
  }
}

class DieResult {
  final int result;
  final bool active;

  DieResult({required this.result, required this.active});

  factory DieResult.fromJson(Map<String, dynamic> json) {
    return DieResult(
      result: (json['result'] as num?)?.toInt() ?? 0,
      active: json['active'] as bool? ?? true,
    );
  }
}

class RollDie {
  final int faces;
  final List<DieResult> results;

  RollDie({required this.faces, required this.results});

  factory RollDie.fromJson(Map<String, dynamic> json) {
    return RollDie(
      faces: (json['faces'] as num?)?.toInt() ?? 0,
      results: ((json['results'] as List?) ?? [])
          .map((e) => DieResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RollInfo {
  final String formula;
  final num total;
  final bool isCritical;
  final bool isFumble;
  final List<RollDie> dice;

  RollInfo({
    required this.formula,
    required this.total,
    required this.isCritical,
    required this.isFumble,
    required this.dice,
  });

  factory RollInfo.fromJson(Map<String, dynamic> json) {
    return RollInfo(
      formula: json['formula'] as String? ?? '',
      total: json['total'] as num? ?? 0,
      isCritical: json['isCritical'] as bool? ?? false,
      isFumble: json['isFumble'] as bool? ?? false,
      dice: ((json['dice'] as List?) ?? [])
          .map((e) => RollDie.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChatMessage {
  final String id;
  final String content;
  final String authorName;
  final String? speakerAlias;
  final int timestamp;
  final String flavor;
  final bool isRoll;
  final List<RollInfo> rolls;

  ChatMessage({
    required this.id,
    required this.content,
    required this.authorName,
    required this.speakerAlias,
    required this.timestamp,
    required this.flavor,
    required this.isRoll,
    required this.rolls,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    final speaker = json['speaker'] as Map<String, dynamic>?;
    return ChatMessage(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      authorName: author?['name'] as String? ?? '',
      speakerAlias: speaker?['alias'] as String?,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      flavor: json['flavor'] as String? ?? '',
      isRoll: json['isRoll'] as bool? ?? false,
      rolls: ((json['rolls'] as List?) ?? [])
          .map((e) => RollInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  String get speakerName =>
      (speakerAlias != null && speakerAlias!.isNotEmpty) ? speakerAlias! : authorName;
}

/// One event off the `/chat/subscribe` SSE stream.
class ChatSseEvent {
  final String type; // connected | chat-create | chat-update | chat-delete
  final Map<String, dynamic> data;

  ChatSseEvent({required this.type, required this.data});
}

/// One entry from `GET /effects/list` — a status condition this world's
/// game system knows about (e.g. "poisoned", "prone"). System-driven, not
/// hardcoded here, so this list differs per world/system.
class EffectDefinition {
  final String id;
  final String name;
  final String? icon;

  EffectDefinition({required this.id, required this.name, required this.icon});

  factory EffectDefinition.fromJson(Map<String, dynamic> json) {
    return EffectDefinition(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
      icon: json['icon'] as String?,
    );
  }
}

/// One ActiveEffect currently applied to an actor, from `GET /effects`.
class ActiveEffectInfo {
  final String id;
  final String name;
  final String? icon;
  final List<String> statuses;

  ActiveEffectInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.statuses,
  });

  factory ActiveEffectInfo.fromJson(Map<String, dynamic> json) {
    return ActiveEffectInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      statuses: ((json['statuses'] as List?) ?? []).map((e) => e.toString()).toList(),
    );
  }
}
