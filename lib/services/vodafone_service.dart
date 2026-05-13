import 'dart:convert';
import 'package:http/http.dart' as http;

class VodafoneService {
  static const _baseAuth = 'https://mobile.vodafone.com.eg/auth/realms/vf-realm/protocol/openid-connect/token';
  static const _chatBase = 'https://chat.vodafone.com.eg/genesys/1/service';

  Map<String, String> _deviceHeaders({String? msisdn}) {
    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Connection': 'keep-alive',
      'silentLogin': 'true',
      'clientId': 'AnaVodafoneAndroid',
      'Accept-Language': 'ar',
      'x-agent-version': '2026.4.1',
      'x-agent-device': 'Samsung SM-G998B',
      'Content-Type': 'application/x-www-form-urlencoded',
      'Host': 'mobile.vodafone.com.eg',
      'User-Agent': 'okhttp/4.12.0',
    };
    if (msisdn != null) headers['msisdn'] = msisdn;
    return headers;
  }

  Future<Map<String, dynamic>> login(String phone, String password) async {
    final response = await http.post(
      Uri.parse(_baseAuth),
      headers: _deviceHeaders(msisdn: phone),
      body: {
        'username': phone,
        'password': password,
        'grant_type': 'password',
        'client_secret': 'dca0pbLUWXVhXR266Gw1iT5rqwvvJQoN',
        'client_id': 'AnaVF',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('فشل تسجيل الدخول - تأكد من الرقم والباسورد');
    }

    final data = json.decode(response.body);
    final token = data['access_token'];
    final parts = token.split('.');
    final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final userInfo = payload['userInfo'] ?? {};

    return {
      'token': token,
      'phone': phone,
      'first_name': userInfo['firstName'] ?? 'مستخدم',
      'last_name': userInfo['lastName'] ?? '',
      'tariff': userInfo['tariffModelName'] ?? 'غير محدد',
    };
  }

  Future<Map<String, dynamic>> startChat(Map<String, dynamic> session) async {
    final chatHeaders = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Xiaomi Build/SKQ1.210216.001) AppleWebKit/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Origin': 'https://web.vodafone.com.eg',
      'Referer': 'https://web.vodafone.com.eg/',
      'Accept-Language': 'ar,ar-EG;q=0.9',
    };

    final initRes = await http.get(Uri.parse('$_chatBase/Chat2'), headers: chatHeaders);
    final chatId = json.decode(initRes.body)['_id'];

    final startHeaders = {...chatHeaders, 'Content-Type': 'application/json'};
    await http.post(
      Uri.parse('$_chatBase/$chatId/ixn/chat'),
      headers: startHeaders,
      body: json.encode({
        'subject': 'ES_1_mobile_es',
        'FirstName': session['first_name'],
        'LastName': session['last_name'],
        'EmailAddress': '',
        'LoggedIn': 'True',
        'message': 'hi',
        'TopicSelected': 'Chat_Contactus_ar',
        'MSISDN': session['phone'],
        '_verbose': 'True',
        'Language': 'ar',
        'RatePlan': session['tariff'],
        'Channel_name': 'app',
        'Source': 'FlexBot',
      }),
    );

    int lastPosition = 0;
    bool agentJoined = false;
    int tries = 0;

    while (!agentJoined && tries < 30) {
      await Future.delayed(const Duration(seconds: 2));
      tries++;
      final refreshRes = await http.post(
        Uri.parse('$_chatBase/$chatId/ixn/chat/refresh?transcriptPosition=$lastPosition'),
        headers: startHeaders,
        body: json.encode({}),
      );
      final data = json.decode(refreshRes.body);
      if (data['transcriptPosition'] != null) lastPosition = data['transcriptPosition'];
      for (final msg in data['transcriptToShow'] ?? []) {
        if (msg[0] == 'Notice.Joined') {
          agentJoined = true;
          break;
        }
      }
    }

    return {
      'chatId': chatId,
      'lastPosition': lastPosition,
      'refreshHeaders': startHeaders,
    };
  }

  Future<Map<String, dynamic>> refreshChat(
      String chatId, int lastPosition, Map<String, String> headers) async {
    final res = await http.post(
      Uri.parse('$_chatBase/$chatId/ixn/chat/refresh?transcriptPosition=$lastPosition'),
      headers: headers,
      body: json.encode({}),
    );
    final data = json.decode(res.body);
    final messages = <String>[];
    for (final msg in data['transcriptToShow'] ?? []) {
      if (msg.length >= 5 && msg[0] == 'Message.Text' && msg[4] == 'AGENT') {
        messages.add(msg[2]);
      }
    }
    return {'position': data['transcriptPosition'], 'messages': messages};
  }

  Future<void> sendMessage(String chatId, String message, Map<String, String> headers) async {
    await http.post(
      Uri.parse('$_chatBase/$chatId/ixn/chat/send'),
      headers: headers,
      body: json.encode({'message': message}),
    );
  }

  Future<void> disconnect(String chatId, Map<String, String> headers) async {
    try {
      await http.post(
        Uri.parse('$_chatBase/$chatId/ixn/chat/disconnect'),
        headers: headers,
        body: json.encode({'_verbose': 'True'}),
      );
    } catch (_) {}
  }
}
