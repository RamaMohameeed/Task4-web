import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GPTService {
  final String _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';

  // Use gpt-3.5-turbo or gpt-4 depending on your access and cost constraints.
  final String model = "gpt-3.5-turbo";

  Future<Map<String, dynamic>> sendMessage(String message) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    final start = DateTime.now();
    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $_apiKey",
      },
      body: jsonEncode({
        "model": model,
        "messages": [
          {"role": "user", "content": message}
        ],
        "max_tokens": 500,
        "temperature": 0.7,
      }),
    );
    final end = DateTime.now();
    final durationMs = end.difference(start).inMilliseconds;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final reply = data['choices'][0]['message']['content'] as String? ?? '';
      return {'reply': reply.trim(), 'durationMs': durationMs};
    } else {
      throw Exception('OpenAI API error (${response.statusCode}): ${response.body}');
    }
  }
}
