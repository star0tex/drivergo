import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/socket_service.dart';

class ChatMessage {
  final String senderId;
  final String text;
  final DateTime timestamp;

  ChatMessage({required this.senderId, required this.text, required this.timestamp});
}

class ChatPage extends StatefulWidget {
  final String tripId;
  final String senderId; // The ID of the current user
  final String receiverId; // The ID of the person they are chatting with
  final String receiverName;

  const ChatPage({
    Key? key,
    required this.tripId,
    required this.senderId,
    required this.receiverId,
    required this.receiverName,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final DriverSocketService _socketService = DriverSocketService(); // ✅ Correct class name
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _socketService.on('chat:receive_message', _handleIncomingMessage);
  }

  @override
  void dispose() {
    _socketService.off('chat:receive_message');
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleIncomingMessage(dynamic data) {
    if (!mounted) return;
    
    final message = ChatMessage(
      senderId: data['fromId'],
      text: data['message'],
      timestamp: DateTime.parse(data['timestamp']),
    );
    
    setState(() {
      _messages.add(message);
    });
    _scrollToBottom();
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final message = ChatMessage(
      senderId: widget.senderId,
      text: _controller.text.trim(),
      timestamp: DateTime.now(),
    );

    _socketService.emit('chat:send_message', {
      'tripId': widget.tripId,
      'fromId': widget.senderId,
      'toId': widget.receiverId,
      'message': message.text,
    });
    
    setState(() {
      _messages.add(message);
    });

    _controller.clear();
    _scrollToBottom();
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


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey[100],
      appBar: AppBar(
        title: Text(
          widget.receiverName,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
         backgroundColor: isDark ? const Color(0xFF2A2520) : Colors.white,
         foregroundColor: isDark ? Colors.white : Colors.black87,
         elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message.senderId == widget.senderId;
                return _buildMessageBubble(message, isMe, isDark);
              },
            ),
          ),
          _buildMessageComposer(isDark),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe, bool isDark) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? const Color(0xFFFFA726)
              : (isDark ? const Color(0xFF3A3A3A) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isMe ? const Radius.circular(20) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(20),
          ),
        ),
        child: Text(
          message.text,
          style: GoogleFonts.poppins(
            color: isMe ? Colors.black87 : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageComposer(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2520) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.poppins(color: Colors.grey),
                  border: InputBorder.none,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF3A3A3A) : Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Color(0xFFFFA726)),
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFFFFA726)),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}