import 'package:avatar_glow/avatar_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const GeminiLiveApp());
}

class GeminiLiveApp extends StatelessWidget {
  const GeminiLiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gemini Live Antigravity',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF131314), // Dark Grey
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD7E5FF), // Light Blue
          secondary: Color(0xFFC4EED0), // Light Green
        ),
      ),
      home: const VoiceChatScreen(),
    );
  }
}

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  // ---------------------------------------------------------------------------
  // 1. API KEY CONFIGURATION
  // ---------------------------------------------------------------------------
  // TODO: Replace this with your actual API Key from aistudio.google.com
  final String _apiKey = 'YOUR_GEMINI_API_KEY_HERE';

  // ---------------------------------------------------------------------------
  // VARIABLES
  // ---------------------------------------------------------------------------
  late final GenerativeModel _model;
  late final ChatSession _chat;
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isLoading = false;
  String _textDisplay = "Press the mic and say:\n'Tell me about Antigravity'";

  @override
  void initState() {
    super.initState();
    _initGemini();
    _initSpeech();
    _initTts();
  }

  // ---------------------------------------------------------------------------
  // INITIALIZATION LOGIC
  // ---------------------------------------------------------------------------
  
  void _initGemini() {
    // We set up the model. 
    // You can customize safety settings here if needed.
    _model = GenerativeModel(
      model: 'gemini-pro',
      apiKey: _apiKey,
    );
    
    // Initialize the chat history
    _chat = _model.startChat();
  }

  void _initSpeech() async {
    _speech = stt.SpeechToText();
    // Request permissions immediately
    await Permission.microphone.request();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    
    // iOS/Android specific settings for better voice
    _flutterTts.setLanguage("en-US");
    _flutterTts.setPitch(1.0);
    _flutterTts.setSpeechRate(0.5);

    // Handle when the bot stops speaking
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  // ---------------------------------------------------------------------------
  // CORE FUNCTIONS
  // ---------------------------------------------------------------------------

  /// 1. Start Listening to Microphone
  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
        _textDisplay = "Listening...";
      });

      _speech.listen(
        onResult: (result) {
          setState(() {
            _textDisplay = result.recognizedWords;
          });
        },
      );
    } else {
      setState(() => _textDisplay = "Microphone denied or unavailable.");
    }
  }

  /// 2. Stop Listening and Send to Gemini
  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      _isLoading = true;
    });

    final userMessage = _speech.lastRecognizedWords;
    if (userMessage.isEmpty) {
      setState(() {
        _isLoading = false;
        _textDisplay = "I didn't hear anything. Try again.";
      });
      return;
    }

    _sendMessageToGemini(userMessage);
  }

  /// 3. Send API Request
  Future<void> _sendMessageToGemini(String message) async {
    try {
      final response = await _chat.sendMessage(
        Content.text(message),
      );
      
      final botText = response.text;

      setState(() {
        _isLoading = false;
        _textDisplay = botText ?? "No response from AI.";
      });

      if (botText != null) {
        _speakResponse(botText);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _textDisplay = "Error: Please check your API Key.\n\nDetails: $e";
      });
    }
  }

  /// 4. Text to Speech
  void _speakResponse(String text) async {
    setState(() {
      _isSpeaking = true;
    });
    // Strip asterisks (markdown) so the voice doesn't read them weirdly
    String cleanText = text.replaceAll('*', ''); 
    await _flutterTts.speak(cleanText);
  }

  void _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
    });
  }

  // ---------------------------------------------------------------------------
  // UI BUILDER
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Determine the color of the glow based on state
    Color glowColor = Colors.grey;
    if (_isListening) glowColor = Colors.blueAccent;
    if (_isLoading) glowColor = Colors.white;
    if (_isSpeaking) glowColor = const Color(0xFF34A853); // Gemini Green

    return Scaffold(
      appBar: AppBar(
        title: const Text("Gemini Live Demo"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            
            // --- THE VISUALIZER (ORB) ---
            AvatarGlow(
              animate: _isListening || _isSpeaking || _isLoading,
              glowColor: glowColor,
              duration: const Duration(milliseconds: 2000),
              repeat: true,
              child: Material(
                elevation: 8.0,
                shape: const CircleBorder(),
                color: Colors.transparent,
                child: CircleAvatar(
                  backgroundColor: const Color(0xFF1E1E1E),
                  radius: 60.0,
                  child: Icon(
                    _isListening ? Icons.mic : (_isSpeaking ? Icons.volume_up : Icons.mic_none),
                    size: 50,
                    color: glowColor,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 50),

            // --- TEXT DISPLAY ---
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _textDisplay,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.4,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),

            // --- CONTROLS ---
            Container(
              padding: const EdgeInsets.all(30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Button Logic:
                  // If Speaking -> Show Stop Button
                  // If Listening -> Show Stop Button
                  // If Idle -> Show Mic Button
                  
                  FloatingActionButton.large(
                    backgroundColor: _isListening || _isSpeaking 
                        ? Colors.redAccent 
                        : Colors.white,
                    foregroundColor: _isListening || _isSpeaking 
                        ? Colors.white 
                        : Colors.black,
                    onPressed: () {
                      if (_isListening) {
                        _stopListening(); // Stop mic, send to API
                      } else if (_isSpeaking) {
                        _stopSpeaking(); // Interrupt AI
                      } else {
                        _startListening(); // Start mic
                      }
                    },
                    child: Icon(
                      _isListening ? Icons.stop : (_isSpeaking ? Icons.stop : Icons.mic),
                      size: 40,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}