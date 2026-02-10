import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/models/message_model.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/models/ride_model.dart';

class PeersChatScreen extends StatefulWidget {
  final UserModel otherUser;
  final RideModel ride;

  const PeersChatScreen({
    super.key,
    required this.otherUser,
    required this.ride,
  });

  @override
  State<PeersChatScreen> createState() => _PeersChatScreenState();
}

class _PeersChatScreenState extends State<PeersChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();

    if (!auth.isAuthenticated) return;

    final newMessage = MessageModel(
      userId: auth.user!.uid, // Required by model, but we use sender/receiver
      senderId: auth.user!.uid,
      receiverId: widget.otherUser.uid,
      rideId: widget.ride.id,
      timestamp: DateTime.now(),
      isUserMessage: true,
      content: text,
      role: widget.ride.type == 'offer' ? 'rider' : 'driver', // Default assumptions
    );

    _messageController.clear();
    await firestore.sendPeerMessage(newMessage);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherUser.name, style: const TextStyle(fontSize: 16)),
            Text("Ref: ${widget.ride.originAddress.split(',')[0]} to ${widget.ride.destinationAddress.split(',')[0]}", 
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show ride details dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Ride Details"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("From: ${widget.ride.originAddress}"),
                      Text("To: ${widget.ride.destinationAddress}"),
                      Text("Price: \$${widget.ride.negotiatedPrice}"),
                      Text("Time: ${widget.ride.departureTime.toString().split('.')[0]}"),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: firestore.getPeerChatMessages(auth.user!.uid, widget.otherUser.uid, widget.ride.id ?? ''),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                
                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == auth.user!.uid;
                    
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blueAccent : Colors.grey[200],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          msg.content,
                          style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
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
              controller: _messageController,
              decoration: InputDecoration(
                hintText: "Type a message...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blueAccent,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
