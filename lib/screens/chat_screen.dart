import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/relay_config.dart';
import '../models/relay_models.dart';
import '../services/relay_client.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _LiveStatus { connecting, live, disconnected }

class _ChatScreenState extends State<ChatScreen> {
  late final RelayClient _client;
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<ChatSseEvent>? _subscription;
  _LiveStatus _status = _LiveStatus.connecting;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _client = RelayClient(context.read<RelayConfig>());
    _init();
  }

  Future<void> _init() async {
    try {
      final history = await _client.getRecentChat(limit: 30);
      if (!mounted) return;
      setState(() => _messages.addAll(history));
      _scrollToBottom();
    } on RelayException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
    _subscribe();
  }

  void _subscribe() {
    setState(() => _status = _LiveStatus.connecting);
    _subscription?.cancel();
    _subscription = _client.subscribeChat().listen(
      (event) {
        if (!mounted) return;
        if (event.type == 'connected') {
          setState(() => _status = _LiveStatus.live);
          return;
        }

        final (opType, payload) = _unwrapChatEvent(event.data);
        if (payload == null) return;

        switch (opType) {
          case 'create':
            final msg = ChatMessage.fromJson(payload);
            setState(() {
              _messages.removeWhere((m) => m.id == msg.id);
              _messages.add(msg);
            });
            _scrollToBottom();
          case 'update':
            final msg = ChatMessage.fromJson(payload);
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == msg.id);
              if (idx >= 0) {
                _messages[idx] = msg;
              } else {
                _messages.add(msg);
              }
            });
          case 'delete':
            final id = payload['id']?.toString();
            if (id != null) setState(() => _messages.removeWhere((m) => m.id == id));
        }
      },
      onError: (_) {
        if (mounted) setState(() => _status = _LiveStatus.disconnected);
      },
      onDone: () {
        if (mounted) setState(() => _status = _LiveStatus.disconnected);
      },
    );
  }

  /// Unwraps one `/chat/subscribe` SSE frame's JSON body.
  ///
  /// Verified against the live relay (not the repo's own
  /// `test-examples/sse-chat-subscribe.ts`, which turned out to describe an
  /// older/different envelope): every chat event currently arrives on the
  /// wire as `event: chat-create` regardless of the actual operation, with
  /// the real shape `{"data": {"data": (message or {"id": ...}), "eventType":
  /// "create"|"update"|"delete"}, "type": "chat-event"}`. So the operation
  /// must be read from the inner `eventType`, not the SSE event name, and
  /// the payload is one level deeper than the fixture assumed.
  (String, Map<String, dynamic>?) _unwrapChatEvent(Map<String, dynamic> data) {
    final inner = data['data'];
    if (inner is Map<String, dynamic> && inner['eventType'] is String) {
      final payload = inner['data'];
      return (inner['eventType'] as String, payload is Map<String, dynamic> ? payload : null);
    }
    // Fall back to a flat shape in case the relay is fixed upstream.
    return ('create', data);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _client.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatlog (live)'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: _statusChip()),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadError != null)
            Container(
              width: double.infinity,
              color: Colors.red.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(8),
              child: Text(_loadError!, style: const TextStyle(color: Colors.red)),
            ),
          if (_status == _LiveStatus.disconnected)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Expanded(child: Text('Live-verbinding verbroken.')),
                  TextButton(onPressed: _subscribe, child: const Text('Opnieuw verbinden')),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Nog geen chatberichten.'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _ChatBubble(message: _messages[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    final (color, label) = switch (_status) {
      _LiveStatus.connecting => (Colors.orange, 'verbinden…'),
      _LiveStatus.live => (Colors.green, 'live'),
      _LiveStatus.disconnected => (Colors.red, 'offline'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: message.isRoll ? scheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.speakerName.isEmpty ? '(onbekend)' : message.speakerName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            if (message.flavor.isNotEmpty)
              Text(message.flavor, style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[700])),
            const SizedBox(height: 2),
            if (message.content.isNotEmpty)
              Text(message.content.replaceAll(RegExp(r'<[^>]*>'), '')),
            for (final roll in message.rolls)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.casino, size: 16),
                    const SizedBox(width: 4),
                    Text('${roll.formula} = ${roll.total}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (roll.isCritical) const Text('  CRIT!', style: TextStyle(color: Colors.green)),
                    if (roll.isFumble) const Text('  FUMBLE!', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
