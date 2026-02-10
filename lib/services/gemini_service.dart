import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:corides/models/message_model.dart';

class GeminiService {
  final String apiKey;
  late final GenerativeModel _model;
  late final ChatSession _chat;

  GeminiService(this.apiKey) {
    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: apiKey,
      systemInstruction: Content.system('''
You are a ride coordinator for CoRides. Your goal is to help users book or offer rides.
You MUST extract the following information from the conversation:
- origin (e.g., "F6")
- destination (e.g., "E11")
- time (e.g., "6pm")
- price (e.g., "500")

If any information is missing, ask the user for it politely.
Once you have ALL FOUR pieces of information, output a JSON block at the end of your response like this:
{
  "complete": true,
  "origin": "...",
  "destination": "...",
  "time": "...",
  "price": 500
}
Otherwise, set "complete": false.
Keep your responses concise and friendly.
'''),
    );
    _chat = _model.startChat();
  }

  Future<MessageModel> sendMessage(String userId, String text, {String role = "rider"}) async {
    final response = await _chat.sendMessage(Content.text("User Role: $role. Message: $text"));
    final content = response.text ?? "I'm sorry, I didn't understand that.";
    
    // Extract JSON if present
    Map<String, dynamic>? intent;
    try {
      final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(content);
      if (jsonMatch != null) {
        intent = json.decode(jsonMatch.group(0)!);
      }
    } catch (e) {
      // Ignore parsing errors
    }

    return MessageModel(
      userId: userId,
      timestamp: DateTime.now(),
      isUserMessage: false,
      content: content.split('{').first.trim(), // Hide JSON from UI
      intentExtracted: intent,
    );
  }
}
