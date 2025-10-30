// lib/driver/screens/chat_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/socket_service.dart'; // Driver's socket service

const String apiBase = 'https://b23b44ae0c5e.ngrok-free.app';

class ChatMessage {
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isMe;

  ChatMessage({
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.isMe,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String currentUserId) {
    return ChatMessage(
      senderId: json['senderId'] ?? json['fromId'] ?? '',
      text: json['message'] ?? json['text'] ?? '',
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : DateTime.now(),
      isMe: (json['senderId'] ?? json['fromId']) == currentUserId,
    );
  }
}

class ChatPage extends StatefulWidget {
  final String tripId;
  final String senderId;
  final String receiverId;
  final String receiverName;
  final bool isDriver;

  const ChatPage({
    Key? key,
    required this.tripId,
    required this.senderId,
    required this.receiverId,
    required this.receiverName,
    required this.isDriver,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  final DriverSocketService _socketService = DriverSocketService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  void _initializeChat() async {
    print('');
    print('=' * 70);
    print('💬 INITIALIZING CHAT');
    print('   Trip ID: ${widget.tripId}');
    print('   Sender ID (Driver): ${widget.senderId}');
    print('   Receiver ID (Customer): ${widget.receiverId}');
    print('   Is Driver: ${widget.isDriver}');
    print('=' * 70);
    print('');

    // Load previous messages
    await _loadChatHistory();

    // Setup socket listeners
    _setupSocketListeners();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadChatHistory() async {
    try {
      print('📥 Loading chat history for trip: ${widget.tripId}');
      
      final response = await http.get(
        Uri.parse('$apiBase/api/chat/history/${widget.tripId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] && data['messages'] != null) {
          setState(() {
            _messages.clear();
            for (var msg in data['messages']) {
              _messages.add(ChatMessage.fromJson(msg, widget.senderId));
            }
          });
          
          print('✅ Loaded ${_messages.length} previous messages');
          _scrollToBottom();
        }
      } else {
        print('⚠️ Failed to load chat history: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading chat history: $e');
    }
  }

  void _setupSocketListeners() {
    print('🔌 Setting up socket listeners...');
    
    // Check if socket is connected
    if (!_socketService.isConnected) {
      print('⚠️ Socket not connected - chat may not work properly');
    } else {
      print('✅ Socket is connected: ${_socketService.socket.id}');
    }

    // Join the chat room
    _socketService.emit('chat:join', {
      'tripId': widget.tripId,
      'userId': widget.senderId,
      'userType': 'driver',
    });
    
    print('📢 Emitted chat:join for trip: ${widget.tripId}');

    // Listen for incoming messages
    _socketService.on('chat:receive_message', _handleIncomingMessage);
    _socketService.on('chat:new_message', _handleIncomingMessage);
    
    print('👂 Listening for chat messages...');
  }

  void _handleIncomingMessage(dynamic data) {
    if (!mounted) return;
    
    print('');
    print('📨 Received message: $data');
    
    try {
      Map<String, dynamic> messageData;
      if (data is Map<String, dynamic>) {
        messageData = data;
      } else if (data is Map) {
        messageData = Map<String, dynamic>.from(data);
      } else {
        print('❌ Unknown data format: ${data.runtimeType}');
        return;
      }
      
      final senderId = messageData['fromId'] ?? messageData['senderId'] ?? '';
      
      print('   From: $senderId');
      print('   Message: ${messageData['message']}');
      
      // Don't add if it's our own message
      if (senderId == widget.senderId) {
        print('   ⏭️ Skipping own message');
        return;
      }

      final message = ChatMessage(
        senderId: senderId,
        text: messageData['message'] ?? messageData['text'] ?? '',
        timestamp: messageData['timestamp'] != null 
            ? DateTime.parse(messageData['timestamp']) 
            : DateTime.now(),
        isMe: false,
      );
      
      setState(() {
        _messages.add(message);
      });
      
      print('   ✅ Message added to chat');
      _scrollToBottom();
    } catch (e) {
      print('❌ Error handling message: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final messageText = _controller.text.trim();
    _controller.clear();

    print('');
    print('📤 Sending message...');
    print('   Trip ID: ${widget.tripId}');
    print('   From (Driver): ${widget.senderId}');
    print('   To (Customer): ${widget.receiverId}');
    print('   Message: $messageText');

    // Add message to UI immediately
    final message = ChatMessage(
      senderId: widget.senderId,
      text: messageText,
      timestamp: DateTime.now(),
      isMe: true,
    );

    setState(() {
      _messages.add(message);
    });
    _scrollToBottom();

    try {
      // Emit via socket
      if (_socketService.isConnected) {
        _socketService.emit('chat:send_message', {
          'tripId': widget.tripId,
          'fromId': widget.senderId,
          'toId': widget.receiverId,
          'message': messageText,
          'timestamp': DateTime.now().toIso8601String(),
          'senderType': 'driver',
        });
        print('✅ Message emitted via socket');
      } else {
        print('⚠️ Socket not connected - message may not be delivered');
      }

      // Also send to backend for persistence
      final response = await http.post(
        Uri.parse('$apiBase/api/chat/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tripId': widget.tripId,
          'senderId': widget.senderId,
          'receiverId': widget.receiverId,
          'message': messageText,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Message persisted to backend');
      } else {
        print('⚠️ Failed to persist message: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
  void dispose() {
    print('');
    print('🚪 Leaving chat...');
    
    // Leave chat room
    if (_socketService.isConnected) {
      _socketService.emit('chat:leave', {
        'tripId': widget.tripId,
        'userId': widget.senderId,
      });
      print('   ✅ Emitted chat:leave');
    }
    
    // Remove listeners
    _socketService.off('chat:receive_message');
    _socketService.off('chat:new_message');
    
    _controller.dispose();
    _scrollController.dispose();
    
    print('   ✅ Chat disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.grey[100],
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFFA726),
              child: Text(
                widget.receiverName[0].toUpperCase(),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.receiverName,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Customer',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF2A2520) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 1,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: const Color(0xFFFFA726),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey.shade600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start the conversation!',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey.shade500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return _buildMessageBubble(message, isDark);
                          },
                        ),
                ),
                _buildMessageComposer(isDark),
              ],
            ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isDark) {
    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isMe
              ? const Color(0xFFFFA726)
              : (isDark ? const Color(0xFF3A3A3A) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: message.isMe ? const Radius.circular(20) : Radius.zero,
            bottomRight: message.isMe ? Radius.zero : const Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: message.isMe 
              ? CrossAxisAlignment.end 
              : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: GoogleFonts.poppins(
                color: message.isMe 
                    ? Colors.black87 
                    : (isDark ? Colors.white : Colors.black87),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: GoogleFonts.poppins(
                color: message.isMe
                    ? Colors.black54
                    : (isDark ? Colors.white54 : Colors.black45),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
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
            offset: const Offset(0, -2),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, 
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(
                      color: Color(0xFFFFA726),
                      width: 2,
                    ),
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFA726),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}