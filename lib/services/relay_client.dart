import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/relay_config.dart';
import '../models/relay_models.dart';

class RelayException implements Exception {
  final String message;
  RelayException(this.message);

  @override
  String toString() => message;
}

/// Thin REST + SSE client for the self-hosted `foundryvtt-rest-api-relay`.
///
/// Route shapes (paths, params, envelopes) were read straight from the
/// relay's own Go source and its `docs/examples/*.json` fixtures rather than
/// guessed — see README.md for the exact files consulted. Two things worth
/// calling out because they deviate from a naive reading of the module name:
///  - There is no `/api` prefix: routes are mounted at the server root
///    (`GET {baseUrl}/get`, `POST {baseUrl}/roll`, ...).
///  - "Live chat" is Server-Sent Events on `GET /chat/subscribe`, not a
///    client-facing WebSocket — the WebSocket in this system only connects
///    the Foundry module to the relay, not this app to the relay.
///  - Writes ([updateField], [adjustAttribute], effect toggling) deliberately
///    use the generic `/update`, `/increase`, `/decrease`, `/effects*`
///    routes and never the D&D-5e-specific `/dnd5e/*` router the relay also
///    exposes — those would work for this test world but break the whole
///    point of a system-agnostic renderer for anything else.
class RelayClient {
  final RelayConfig config;
  final Dio _dio;

  RelayClient(this.config)
      : _dio = Dio(BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'x-api-key': config.apiKey},
        ));

  Map<String, dynamic> _requireData(Response res) {
    final body = res.data;
    if (body is! Map<String, dynamic>) {
      throw RelayException('Onverwacht antwoord van de relay (geen JSON-object).');
    }
    if (body.containsKey('error')) {
      throw RelayException(body['error'].toString());
    }
    if (body['success'] == false) {
      throw RelayException(body['error']?.toString() ?? 'Relay meldde een fout.');
    }
    return body;
  }

  Never _rethrow(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      throw RelayException(data['error'].toString());
    }
    if (e.response != null) {
      throw RelayException('Relay antwoordde met status ${e.response!.statusCode}.');
    }
    throw RelayException('Kan geen verbinding maken met de relay: ${e.message}');
  }

  Future<List<FoundryClientInfo>> getClients() async {
    try {
      final res = await _dio.get('/clients');
      final body = res.data as Map<String, dynamic>;
      final clients = (body['clients'] as List? ?? [])
          .map((e) => FoundryClientInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      return clients;
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<SearchResult>> searchActors() async {
    try {
      final res = await _dio.get('/search', queryParameters: {
        'clientId': config.clientId,
        'filter': 'documentType:Actor',
        'excludeCompendiums': true,
        'limit': 100,
      });
      final body = _requireData(res);
      final results = (body['results'] as List? ?? [])
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
      return results;
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Fetches the raw actor document — no field mapping, this is exactly the
  /// JSON Foundry stores for the entity. The dynamic sheet renderer walks
  /// this generically so it works for any game system, not just D&D 5e.
  Future<Map<String, dynamic>> getEntity(String uuid) async {
    try {
      final res = await _dio.get('/get', queryParameters: {
        'clientId': config.clientId,
        'uuid': uuid,
      });
      final body = _requireData(res);
      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        throw RelayException('Relay gaf geen entity-data terug voor $uuid.');
      }
      return data;
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// [speaker], when given the rolling actor's UUID, makes the roll show up
  /// in Foundry's chat log attributed to that actor (alias + portrait)
  /// instead of the API user generically — confirmed live: the relay
  /// resolves a bare actor UUID string into the proper
  /// `{actor, alias, ...}` speaker object on the resulting chat message.
  Future<RollInfo> postRoll({required String formula, String? flavor, String? speaker}) async {
    try {
      final res = await _dio.post(
        '/roll',
        queryParameters: {'clientId': config.clientId},
        data: {
          'formula': formula,
          if (flavor != null && flavor.isNotEmpty) 'flavor': flavor,
          if (speaker != null && speaker.isNotEmpty) 'speaker': speaker,
          'createChatMessage': true,
        },
      );
      final body = _requireData(res);
      final data = body['data'] as Map<String, dynamic>?;
      final roll = data?['roll'] as Map<String, dynamic>?;
      if (roll == null) {
        throw RelayException('Relay gaf geen rollresultaat terug.');
      }
      return RollInfo.fromJson(roll);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Patches a single field on an entity using Foundry's native flattened
  /// dot-notation update keys (e.g. `system.attributes.hp.value`) — standard
  /// `Document#update()` behavior in Foundry core, not something the relay
  /// special-cases. Works for any field at any path, on any system, which is
  /// what lets the dynamic sheet stay generic instead of needing per-system
  /// edit screens.
  Future<void> updateField(String uuid, String path, dynamic value) async {
    try {
      final res = await _dio.put(
        '/update',
        queryParameters: {'clientId': config.clientId, 'uuid': uuid},
        data: {
          'data': {path: value},
        },
      );
      _requireData(res);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Increments or decrements a numeric field by [delta] via the relay's
  /// dedicated `/increase`/`/decrease` endpoints. [attribute] is the same
  /// dot-path `DynamicJsonView` already computes per numeric leaf, so this
  /// covers HP, resources, spell slots, item quantities, etc. identically
  /// without any system-specific code here.
  Future<num?> adjustAttribute(String uuid, String attribute, num delta) async {
    final endpoint = delta >= 0 ? '/increase' : '/decrease';
    try {
      final res = await _dio.post(
        endpoint,
        queryParameters: {'clientId': config.clientId, 'uuid': uuid},
        data: {'attribute': attribute, 'amount': delta.abs()},
      );
      final body = _requireData(res);
      final results = body['results'] as List?;
      if (results != null && results.isNotEmpty) {
        return (results.first as Map<String, dynamic>)['newValue'] as num?;
      }
      return null;
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Status conditions this world's game system knows about (e.g.
  /// "poisoned", "prone") — driven entirely by `GET /effects/list`, so this
  /// works for whatever system the connected world runs, not just dnd5e.
  Future<List<EffectDefinition>> getAvailableEffects() async {
    try {
      final res = await _dio.get('/effects/list', queryParameters: {'clientId': config.clientId});
      final body = _requireData(res);
      final data = body['data'] as Map<String, dynamic>?;
      return ((data?['effects'] as List?) ?? [])
          .map((e) => EffectDefinition.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<ActiveEffectInfo>> getActiveEffects(String uuid) async {
    try {
      final res = await _dio.get('/effects', queryParameters: {'clientId': config.clientId, 'uuid': uuid});
      final body = _requireData(res);
      final data = body['data'] as Map<String, dynamic>?;
      return ((data?['effects'] as List?) ?? [])
          .map((e) => ActiveEffectInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> addEffect(String uuid, String statusId) async {
    try {
      final res = await _dio.post(
        '/effects',
        queryParameters: {'clientId': config.clientId},
        data: {'uuid': uuid, 'statusId': statusId},
      );
      _requireData(res);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> removeEffect(String uuid, String effectId) async {
    try {
      final res = await _dio.delete(
        '/effects',
        queryParameters: {'clientId': config.clientId},
        data: {'uuid': uuid, 'effectId': effectId},
      );
      _requireData(res);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<List<ChatMessage>> getRecentChat({int limit = 20}) async {
    try {
      final res = await _dio.get('/chat', queryParameters: {
        'clientId': config.clientId,
        'limit': limit,
      });
      final body = _requireData(res);
      final data = body['data'] as Map<String, dynamic>?;
      final messages = (data?['messages'] as List? ?? [])
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      // Relay returns newest-first; we want oldest-first for a chat list.
      return messages.reversed.toList();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Opens the `/chat/subscribe` SSE stream and yields parsed events.
  /// The stream stays open until cancelled by the caller; on a network
  /// hiccup it simply ends (caller decides whether/when to resubscribe).
  Stream<ChatSseEvent> subscribeChat() {
    final controller = StreamController<ChatSseEvent>();
    final cancelToken = CancelToken();

    () async {
      try {
        final res = await _dio.get<ResponseBody>(
          '/chat/subscribe',
          queryParameters: {'clientId': config.clientId},
          options: Options(
            responseType: ResponseType.stream,
            headers: {'Accept': 'text/event-stream'},
            // The base client's 15s receiveTimeout is for ordinary REST
            // calls. It must not apply here: the relay's own SSE keepalive
            // ticker also fires every 15s (go-relay/internal/handler/sse.go),
            // so with the timeout left on, the stream would race its own
            // keepalive and silently die — confirmed against the live relay,
            // where the connection dropped a few keepalive cycles in even
            // though the server kept sending them.
            receiveTimeout: Duration.zero,
          ),
          cancelToken: cancelToken,
        );

        final stream = res.data!.stream;
        String buffer = '';
        String? eventType;
        final dataLines = <String>[];

        await for (final Uint8List chunk in stream) {
          buffer += utf8.decode(chunk, allowMalformed: true);
          while (true) {
            final sep = buffer.indexOf('\n');
            if (sep == -1) break;
            final line = buffer.substring(0, sep).replaceAll('\r', '');
            buffer = buffer.substring(sep + 1);

            if (line.isEmpty) {
              // End of one SSE event block.
              if (eventType != null && dataLines.isNotEmpty) {
                final raw = dataLines.join('\n');
                try {
                  final parsed = jsonDecode(raw);
                  if (parsed is Map<String, dynamic>) {
                    controller.add(ChatSseEvent(type: eventType, data: parsed));
                  }
                } catch (_) {
                  // Ignore malformed keepalive/data frames.
                }
              }
              eventType = null;
              dataLines.clear();
              continue;
            }
            if (line.startsWith(':')) continue; // keepalive comment
            if (line.startsWith('event:')) {
              eventType = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              dataLines.add(line.substring(5).trim());
            }
          }
        }
        await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(RelayException('Chat-stream verbroken: $e'));
          await controller.close();
        }
      }
    }();

    controller.onCancel = () {
      cancelToken.cancel();
    };

    return controller.stream;
  }

  void dispose() {
    _dio.close(force: true);
  }
}
