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

  Future<RollInfo> postRoll({required String formula, String? flavor}) async {
    try {
      final res = await _dio.post(
        '/roll',
        queryParameters: {'clientId': config.clientId},
        data: {
          'formula': formula,
          if (flavor != null && flavor.isNotEmpty) 'flavor': flavor,
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
