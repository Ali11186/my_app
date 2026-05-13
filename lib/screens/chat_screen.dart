import 'package:flutter/material.dart';
import '../services/vodafone_service.dart';
import '../services/background_service.dart';
import '../main.dart';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  const ChatScreen({super.key, required this.session});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _service = VodafoneService();
  final List<_Msg> _messages = [];
  bool _connecting = true;
  bool _chatActive = false;
  bool _inBackground = false;
  Timer? _timer;
  int _lastPos = 0;
  String? _chatId;
  Map<String, String>? _headers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startChat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inBackground = state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (_chatActive) {
      if (_inBackground) {
        startBackgroundService();
      } else {
        stopBackgroundService();
      }
    }
  }

  void _add(String text, _MsgType type) {
    setState(() => _messages.add(_Msg(text, type)));
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _startChat() async {
    _add('جاري الاتصال بخدمة العملاء...', _MsgType.system);
    try {
      final r = await _service.startChat(widget.session);
      _chatId = r['chatId'];
      _headers = Map<String, String>.from(r['refreshHeaders']);
      _lastPos = r['lastPosition'];
      setState(() { _connecting = false; _chatActive = true; });
      _add('تم الاتصال! ابدأ المحادثة', _MsgType.system);
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    } catch (e) {
      _add('فشل الاتصال: $e', _MsgType.system);
      setState(() => _connecting = false);
    }
  }

  Future<void> _refresh() async {
    if (!_chatActive || _chatId == null) return;
    try {
      final r = await _service.refreshChat(_chatId!, _lastPos, _headers!);
      if (r['position'] != null) _lastPos = r['position'];
      for (final m in r['messages'] ?? []) {
        _add(m, _MsgType.agent);
        if (_inBackground) {
          sendMessageToBackground(m);
        } else {
          await showNotification('👨‍💼 الموظف: $m');
        }
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || !_chatActive) return;
    _msgCtrl.clear();
    _add(text, _MsgType.user);
    try { await _service.sendMessage(_chatId!, text, _headers!); } catch (_) {}
  }

  Future<void> _endChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('انهاء المحادثة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('هل انت متأكد انك تريد انهاء المحادثة؟', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لا', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE60000), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('انهاء'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    _timer?.cancel();
    stopBackgroundService();
    if (_chatId != null && _headers != null) await _service.disconnect(_chatId!, _headers!);
    setState(() => _chatActive = false);
    _add('تم انهاء المحادثة', _MsgType.system);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appState = MyApp.of(context);
    final name = '${widget.session['first_name']} ${widget.session['last_name']}';
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFE60000), Color(0xFFFF6B6B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Center(child: Icon(Icons.support_agent_rounded, color: Colors.white, size: 22)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('خدمة العملاء', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(name, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.wb_sunny : Icons.nightlight_round, color: Colors.white),
            onPressed: () => appState?.toggleTheme(),
          ),
          if (_chatActive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
                onPressed: _endChat,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_connecting) LinearProgressIndicator(backgroundColor: Colors.grey[200], color: const Color(0xFFE60000)),
          Expanded(
            child: _messages.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 60, color: Colors.grey.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text('جاري الاتصال...', style: TextStyle(color: Colors.grey[400])),
                  ]))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildMessage(_messages[i], isDark),
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _msgCtrl,
                      enabled: _chatActive,
                      textDirection: TextDirection.rtl,
                      maxLines: null,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: _chatActive ? 'اكتب رسالتك...' : 'المحادثة منتهية',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _chatActive ? _send : null,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: _chatActive ? const LinearGradient(colors: [Color(0xFFE60000), Color(0xFFFF4444)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                      color: _chatActive ? null : Colors.grey[300],
                      shape: BoxShape.circle,
                      boxShadow: _chatActive ? [BoxShadow(color: const Color(0xFFE60000).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : null,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(_Msg msg, bool isDark) {
    if (msg.type == _MsgType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(msg.text, style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[600], fontSize: 12)),
          ),
        ),
      );
    }
    final isUser = msg.type == _MsgType.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(radius: 16, backgroundColor: const Color(0xFFE60000).withOpacity(0.1),
                child: const Icon(Icons.support_agent_rounded, color: Color(0xFFE60000), size: 18)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              decoration: BoxDecoration(
                gradient: isUser ? const LinearGradient(colors: [Color(0xFFE60000), Color(0xFFFF4444)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                color: isUser ? null : isDark ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Text(msg.text,
                  style: TextStyle(color: isUser ? Colors.white : isDark ? Colors.white : Colors.black87, fontSize: 15, height: 1.4)),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

enum _MsgType { user, agent, system }
class _Msg { final String text; final _MsgType type; _Msg(this.text, this.type); }
