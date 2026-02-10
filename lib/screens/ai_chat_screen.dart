import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:corides/screens/gemini_live_screen.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/services/gemini_service.dart';
import 'package:corides/models/message_model.dart';
import 'package:corides/models/ride_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AIChatScreen extends StatefulWidget {
  final bool isDriverMode;
  const AIChatScreen({super.key, required this.isDriverMode});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleTextSubmit(String text) async {
    if (text.trim().isEmpty) return;
    
    final auth = Provider.of<AuthService>(context, listen: false);
    final firestore = Provider.of<FirestoreService>(context, listen: false);
    final gemini = Provider.of<GeminiService>(context, listen: false);

    setState(() => isProcessing = true);
    _textController.clear();

    try {
      await firestore.saveMessage(MessageModel(
        userId: auth.user!.uid,
        timestamp: DateTime.now(),
        isUserMessage: true,
        content: text,
        role: widget.isDriverMode ? 'driver' : 'rider',
      ));
      
      _scrollToBottom();
      await gemini.sendMessage(
        auth.user!.uid, 
        text, 
        role: widget.isDriverMode ? 'driver' : 'rider'
      );
    } finally {
      setState(() => isProcessing = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final firestore = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.isDriverMode ? "AI Coordinator (Driver)" : "AI Coordinator (Rider)"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.mic, color: Colors.blue),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GeminiLiveScreen(isDriverMode: widget.isDriverMode),
                ),
              );
            },
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: firestore.getUserMessages(auth.user!.uid, role: widget.isDriverMode ? 'driver' : 'rider'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data!.reversed.toList();
                
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _buildChatBubble(msg);
                  },
                );
              },
            ),
          ),
          if (isProcessing)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("AI is thinking...", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(MessageModel msg) {
    return Align(
      alignment: msg.isUserMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isUserMessage ? Colors.blueAccent : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          msg.content,
          style: TextStyle(color: msg.isUserMessage ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: "Type a message...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: _handleTextSubmit,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blueAccent),
            onPressed: () => _handleTextSubmit(_textController.text),
          ),
        ],
      ),
    );
  }
}
