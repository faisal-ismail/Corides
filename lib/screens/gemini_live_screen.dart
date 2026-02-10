import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:corides/constants.dart';

class GeminiLiveScreen extends StatefulWidget {
  final bool isDriverMode;
  const GeminiLiveScreen({super.key, this.isDriverMode = false});

  @override
  State<GeminiLiveScreen> createState() => _GeminiLiveScreenState();
}

class _GeminiLiveScreenState extends State<GeminiLiveScreen> {
  late GenerativeModel _model;
  late ChatSession _chat;
  late stt.SpeechToText _speech;
  late FlutterTts _tts;

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isLoading = false;

  String _displayText = "Tap the mic and start talking.";

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _initSpeech();
    _initTts();
    _initGemini();
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initPermissions() async {
    await Permission.microphone.request();
  }

  void _initGemini() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: AppConstants.geminiApiKey,
      systemInstruction: Content.system(
        "You are a friendly, fast, conversational AI assistant for a ${widget.isDriverMode ? 'driver' : 'rider'}. "
        "Keep responses under 2 sentences. Speak naturally.",
      ),
    );

    _chat = _model.startChat();
  }

  void _initSpeech() {
    _speech = stt.SpeechToText();
  }

  void _initTts() {
    _tts = FlutterTts();
    _tts.setLanguage("en-US");
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      setState(() => _isSpeaking = true);
    });

    _tts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });

    _tts.setErrorHandler((_) {
      setState(() => _isSpeaking = false);
    });
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize();

    if (!available) {
      setState(() => _displayText = "Microphone unavailable.");
      return;
    }

    setState(() {
      _isListening = true;
      _displayText = "Listening...";
    });

    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _stopListening(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _stopListening(String text) async {
    if (!_isListening) return;
    
    await _speech.stop();
    setState(() => _isListening = false);

    if (text.trim().isEmpty) return;

    setState(() {
      _displayText = text;
    });

    _sendToGemini(text);
  }

  Future<void> _sendToGemini(String text) async {
    setState(() => _isLoading = true);

    try {
      final response = await _chat.sendMessage(Content.text(text));
      final reply = response.text ?? "I didn’t catch that.";

      setState(() {
        _isLoading = false;
        _displayText = reply;
      });

      await _tts.speak(reply.replaceAll('*', ''));
    } catch (e) {
      setState(() {
        _isLoading = false;
        _displayText = "Error: $e";
      });
    }
  }

  void _stopSpeaking() async {
    await _tts.stop();
    setState(() => _isSpeaking = false);
  }

  @override
  Widget build(BuildContext context) {
    Color glowColor = Colors.grey;
    if (_isListening) glowColor = Colors.blueAccent;
    if (_isSpeaking) glowColor = Colors.greenAccent;
    if (_isLoading) glowColor = Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(widget.isDriverMode ? "AI Driver Assistant" : "AI Rider Assistant", style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            AvatarGlow(
              animate: _isListening || _isSpeaking || _isLoading,
              glowColor: glowColor,
              duration: const Duration(milliseconds: 2000),
              repeat: true,
              child: CircleAvatar(
                radius: 70,
                backgroundColor: const Color(0xFF1E1E1E),
                child: Icon(
                  _isListening
                      ? Icons.mic
                      : _isSpeaking
                          ? Icons.volume_up
                          : Icons.mic_none,
                  size: 60,
                  color: glowColor,
                ),
              ),
            ),

            const SizedBox(height: 40),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _displayText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
            ),

            const Spacer(),

            FloatingActionButton.large(
              backgroundColor:
                  _isListening || _isSpeaking ? Colors.red : Colors.white,
              foregroundColor:
                  _isListening || _isSpeaking ? Colors.white : Colors.black,
              onPressed: () {
                if (_isListening) {
                  _speech.stop();
                  setState(() => _isListening = false);
                } else if (_isSpeaking) {
                  _stopSpeaking();
                } else {
                  _startListening();
                }
              },
              child: Icon(
                _isListening || _isSpeaking ? Icons.stop : Icons.mic,
                size: 36,
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
