import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:prenova/core/constants/api_contants.dart';
import 'package:prenova/core/theme/app_pallete.dart';
import 'package:prenova/core/utils/loader.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:prenova/features/auth/auth_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PregnancyChatScreen extends StatefulWidget {
  final String? sessionId;

  const PregnancyChatScreen({Key? key, this.sessionId}) : super(key: key);

  @override
  _PregnancyChatScreenState createState() => _PregnancyChatScreenState();
}

class _PregnancyChatScreenState extends State<PregnancyChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> allSessions = [];
  int selectedSessionIndex = 0;
  final AuthService _authService = AuthService();
  final SupabaseClient supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _isInitializing = true;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;
  late AnimationController _slideController;

  // Voice features
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  bool _speechEnabled = false;
  bool _isSpeaking = false; // Add this line

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _initializeSpeech();
    fetchChatHistoryFromSupabase(); // Fetch chat history from Supabase on screen load
    debugPrint('=== SENDING GET /chat/history API REQUEST ===');
    fetchChatHistoryFromApi(); // Fetch chat history from API for debugging
    setState(() {
      _isInitializing = false;
    });
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _initializeSpeech() async {
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _speechEnabled = await _speech.initialize();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _initializeChat() async {
    setState(() {
      _isInitializing = false;
    });
    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> fetchChatHistoryFromSupabase() async {
    final session = _authService.currentSession;
    final user = session?.user;
    if (user == null) return;
    final response = await supabase
        .from('chats')
        .select('id, chat_history, created_at')
        .eq('UID', user.id)
        .order('created_at', ascending: false);
    debugPrint('Supabase fetch chat history response: ' + response.toString());
    if (response != null && response is List && response.isNotEmpty) {
      setState(() {
        allSessions = List<Map<String, dynamic>>.from(response);
        // Default to the first session
        messages = List<Map<String, dynamic>>.from(
            allSessions[0]['chat_history'] ?? []);
        selectedSessionIndex = 0;
      });
    } else {
      setState(() {
        allSessions = [];
        messages = [];
        selectedSessionIndex = 0;
      });
    }
  }

  Future<void> saveChatHistoryToSupabase() async {
    final session = _authService.currentSession;
    final user = session?.user;
    if (user == null || allSessions.isEmpty) return;
    final currentSessionId = allSessions[selectedSessionIndex]['id'];
    await supabase.from('chats').update({
      'chat_history': messages,
    }).eq('id', currentSessionId);
    await fetchChatHistoryFromSupabase(); // Refresh sessions
  }

  Future<void> createNewChatSession() async {
    final session = _authService.currentSession;
    final user = session?.user;
    if (user == null) return;
    final response = await supabase.from('chats').insert({
      'UID': user.id,
      'chat_history': [],
    }).select();
    await fetchChatHistoryFromSupabase();
    if (allSessions.isNotEmpty) {
      setState(() {
        selectedSessionIndex = 0;
        messages = [];
      });
    }
  }

  Future<void> fetchChatHistoryFromApi() async {
    final session = _authService.currentSession;
    final token = session?.accessToken;
    final url = "https://prenova.onrender.com/chat/history";
    debugPrint('Fetching chat history from API: $url');
    debugPrint('Using token: $token');
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          "Content-Type": "application/json",
          'Authorization': 'Bearer $token',
        },
      );
      debugPrint('=== RECEIVED RESPONSE FROM GET /chat/history ===');
      debugPrint('Status: \\${response.statusCode}');
      debugPrint('Body: \\${response.body}');
      debugPrint('==============================================');
    } catch (e, st) {
      debugPrint('Error fetching chat history from API: $e');
      debugPrint('Stacktrace: $st');
    }
  }

  void sendMessage(String userMessage) async {
    final session = _authService.currentSession;
    final token = session?.accessToken;
    if (userMessage.trim().isEmpty) return;
    await _flutterTts.stop();
    setState(() {
      messages.add({"role": "user", "content": userMessage.trim()});
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();
    try {
      final response = await http.post(
        Uri.parse("https://prenova.onrender.com/chat/history"),
        headers: {
          "Content-Type": "application/json",
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          "message": userMessage
              .trim()
              .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        }),
      );
      setState(() {
        _isLoading = false;
      });
      debugPrint(
          '================ CHAT HISTORY POST RESPONSE ================');
      debugPrint('Status: \\${response.statusCode}');
      debugPrint('Body: \\${response.body}');
      debugPrint(
          '============================================================');
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        String botResponse = responseData['response'] ?? '';
        setState(() {
          messages.add({
            "role": "assistant",
            "content": botResponse.replaceAll(
                RegExp(r'<think>.*?</think>', dotAll: true), '')
          });
        });
        _scrollToBottom();
        await saveChatHistoryToSupabase();
      } else {
        setState(() {
          messages.add({
            "role": "assistant",
            "content":
                "I'm having trouble responding right now. Please try again."
          });
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        messages.add({
          "role": "assistant",
          "content":
              "Connection error. Please check your internet and try again."
        });
      });
      log('Error sending message: $e');
    }
  }

  void _startListening() async {
    if (!_speechEnabled) return;

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
        });
      },
    );
    setState(() {
      _isListening = true;
    });
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _speak(String text) async {
    setState(() {
      _isSpeaking = true;
    });

    await _flutterTts.speak(text);

    // Listen for completion
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  void _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void selectSession(int index) {
    setState(() {
      selectedSessionIndex = index;
      messages = List<Map<String, dynamic>>.from(
          allSessions[index]['chat_history'] ?? []);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: AppPallete.backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomLoader(
                size: 60,
                color: AppPallete.gradient1,
              ),
              SizedBox(height: 24),
              Text(
                "Initializing NOVA...",
                style: TextStyle(
                  color: AppPallete.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppPallete.backgroundColor,
      appBar: _buildAppBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppPallete.backgroundColor,
              AppPallete.gradient1.withOpacity(0.03),
              AppPallete.backgroundColor,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPallete.gradient1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(Icons.add, color: Colors.white),
                  label: Text('New Chat',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  onPressed: createNewChatSession,
                ),
              ),
            ),
            Expanded(child: _buildMessagesList()),
            _buildInputSection(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: FadeTransition(
        opacity: _fadeController,
        child: Column(
          children: [
            Text(
              'Ayu',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              "Nurturing Online Virtual Assistant",
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppPallete.gradient1, AppPallete.gradient2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
          boxShadow: [
            BoxShadow(
              color: AppPallete.gradient1.withOpacity(0.3),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(LucideIcons.moreVertical, color: Colors.white, size: 20),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          color: Colors.white,
          onSelected: (value) {
            switch (value) {
              case 'chat_history':
                _showChatHistoryBottomSheet();
                break;
              case 'clear_current':
                _clearCurrentChat();
                break;
              case 'stop_speaking':
                _stopSpeaking();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'chat_history',
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppPallete.gradient2.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.history,
                        size: 18,
                        color: AppPallete.gradient2,
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chat History',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppPallete.textColor,
                          ),
                        ),
                        Text(
                          'View previous conversations',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPallete.textColor.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_isSpeaking)
              PopupMenuItem(
                value: 'stop_speaking',
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          LucideIcons.volumeX,
                          size: 18,
                          color: Colors.orange,
                        ),
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stop Speaking',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppPallete.textColor,
                            ),
                          ),
                          Text(
                            'Pause voice response',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppPallete.textColor.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'clear_current',
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.trash2,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clear Chat',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                        Text(
                          'Delete current conversation',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    if (messages.isEmpty && !_isLoading) {
      return _buildWelcomeScreen();
    }

    return FadeTransition(
      opacity: _fadeController,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: messages.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length && _isLoading) {
            return _buildTypingIndicator();
          }

          final message = messages[index];
          final bool isUser = message["role"] == "user";

          return SlideTransition(
            position: Tween<Offset>(
              begin: Offset(isUser ? 1 : -1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _slideController,
              curve: Curves.easeOutBack,
            )),
            child: _buildMessageBubble(message, isUser),
          );
        },
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return FadeTransition(
      opacity: _fadeController,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppPallete.gradient1, AppPallete.gradient2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppPallete.gradient1.withOpacity(0.3),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.health_and_safety,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 24),
              Text(
                "Welcome to Ayu!",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppPallete.gradient1,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                "Nurturing Online Virtual Assistant",
                style: TextStyle(
                    fontSize: 16,
                    color: AppPallete.gradient1,
                    height: 1.5,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                "Your AI pregnancy companion is here to support you throughout your journey. Ask me anything about pregnancy health, symptoms, or general wellness!",
                style: TextStyle(
                  fontSize: 16,
                  color: AppPallete.textColor.withOpacity(0.8),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              _buildSuggestedQuestions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedQuestions() {
    final suggestions = [
      "What should I eat during pregnancy?",
      "How can I manage morning sickness?",
      "What exercises are safe for me?",
      "Tell me about fetal development",
    ];

    return Column(
      children: [
        Text(
          "Try asking:",
          style: TextStyle(
            fontSize: 14,
            color: AppPallete.textColor.withOpacity(0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions
              .map((suggestion) => GestureDetector(
                    onTap: () => sendMessage(suggestion),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppPallete.gradient1.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppPallete.gradient1.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        suggestion,
                        style: TextStyle(
                          color: AppPallete.gradient1,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 8),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppPallete.gradient1,
              child:
                  Icon(Icons.health_and_safety, color: Colors.white, size: 18),
            ),
            SizedBox(width: 12),
            CustomLoader(
              size: 20,
              color: AppPallete.gradient1,
            ),
            SizedBox(width: 12),
            Text(
              "Ayu is thinking...",
              style: TextStyle(
                color: AppPallete.textColor.withOpacity(0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 6),
        padding: EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppPallete.gradient1 : Colors.white,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isUser ? Radius.circular(6) : Radius.circular(20),
            bottomLeft: isUser ? Radius.circular(20) : Radius.circular(6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppPallete.gradient1,
                    child: Icon(Icons.health_and_safety,
                        color: Colors.white, size: 18),
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Ayu",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppPallete.gradient1,
                      fontSize: 14,
                    ),
                  ),
                  Spacer(),
                  Row(
                    children: [
                      if (_isSpeaking)
                        GestureDetector(
                          onTap: _stopSpeaking,
                          child: Container(
                            padding: EdgeInsets.all(6),
                            margin: EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.volumeX,
                                  size: 14,
                                  color: Colors.orange,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Stop',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _speak(message["content"]),
                        child: Container(
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _isSpeaking
                                ? AppPallete.gradient1.withOpacity(0.2)
                                : AppPallete.gradient1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isSpeaking
                                  ? AppPallete.gradient1.withOpacity(0.5)
                                  : AppPallete.gradient1.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isSpeaking
                                    ? LucideIcons.volume2
                                    : LucideIcons.play,
                                size: 14,
                                color: AppPallete.gradient1,
                              ),
                              SizedBox(width: 4),
                              Text(
                                _isSpeaking ? 'Speaking...' : 'Listen',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppPallete.gradient1,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 8),
            ],
            if (message["content"] != null)
              isUser
                  ? Text(
                      message["content"],
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    )
                  : MarkdownBody(
                      data: message["content"],
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          fontSize: 16,
                          color: AppPallete.textColor,
                          height: 1.4,
                        ),
                        h1: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppPallete.gradient1,
                        ),
                        h2: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppPallete.gradient1,
                        ),
                        h3: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppPallete.gradient1,
                        ),
                        listBullet: TextStyle(color: AppPallete.textColor),
                        strong: TextStyle(
                          color: AppPallete.gradient1,
                          fontWeight: FontWeight.bold,
                        ),
                        code: TextStyle(
                          backgroundColor:
                              AppPallete.gradient1.withOpacity(0.1),
                          color: AppPallete.gradient1,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppPallete.backgroundColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: AppPallete.borderColor.withOpacity(0.3),
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: "Ask Ayu about your pregnancy...",
                    hintStyle: TextStyle(
                      color: AppPallete.borderColor.withOpacity(0.7),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  style: TextStyle(
                    color: AppPallete.textColor,
                    fontSize: 16,
                  ),
                  onSubmitted: (text) => sendMessage(text.trim()),
                ),
              ),
            ),
            SizedBox(width: 12),
            if (_speechEnabled)
              GestureDetector(
                onTap: _isListening ? _stopListening : _startListening,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isListening
                        ? AppPallete.gradient2.withOpacity(0.9)
                        : Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isListening ? Colors.red : AppPallete.gradient2)
                                .withOpacity(0.3),
                        blurRadius: 15,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? LucideIcons.mic : LucideIcons.micOff,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            SizedBox(width: 8),
            GestureDetector(
              onTap: () => sendMessage(_controller.text.trim()),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppPallete.gradient1, AppPallete.gradient2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppPallete.gradient1.withOpacity(0.3),
                      blurRadius: 15,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  LucideIcons.send,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearCurrentChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear Chat'),
        content: Text('Are you sure you want to clear this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await createNewChatSession();
            },
            child: Text('Clear & New', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showChatHistoryBottomSheet() {
    int? previewSessionIndex;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chat History',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppPallete.gradient1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Colors.grey[200]),
                    if (allSessions.isEmpty)
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.messageSquare,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No chat sessions found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (previewSessionIndex == null)
                      Expanded(
                        child: ListView.separated(
                          separatorBuilder: (context, idx) => Divider(
                              color: AppPallete.gradient1.withOpacity(0.08),
                              height: 1),
                          itemCount: allSessions.length,
                          padding:
                              EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          itemBuilder: (context, index) {
                            final session = allSessions[index];
                            final chatHistory =
                                session['chat_history'] as List?;
                            final firstUserMsg =
                                chatHistory != null && chatHistory.isNotEmpty
                                    ? (chatHistory.firstWhere(
                                            (m) => m['role'] == 'user',
                                            orElse: () => null)?['content'] ??
                                        '')
                                    : '';
                            final date = session['created_at'] != null
                                ? session['created_at']
                                    .toString()
                                    .split('T')
                                    .first
                                : '';
                            // Session number: 1 is oldest, N is newest
                            final sessionNumber = index + 1;
                            return GestureDetector(
                              onTapDown: (_) => setModalState(() {}),
                              onTap: () => setModalState(() {
                                previewSessionIndex = index;
                              }),
                              child: AnimatedContainer(
                                duration: Duration(milliseconds: 120),
                                curve: Curves.easeInOut,
                                margin: EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppPallete.gradient1
                                          .withOpacity(0.07),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                  border: Border(
                                    left: BorderSide(
                                      color: AppPallete.gradient1,
                                      width: 5,
                                    ),
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        AppPallete.gradient2.withOpacity(0.06)
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                      vertical: 18, horizontal: 18),
                                  child: Row(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: AppPallete.gradient1
                                              .withOpacity(0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        padding: EdgeInsets.all(10),
                                        child: Icon(LucideIcons.history,
                                            color: AppPallete.gradient1,
                                            size: 24),
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Session $sessionNumber',
                                              style: TextStyle(
                                                color: AppPallete.gradient1,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 17,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            if (date.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2.0),
                                                child: Text(date,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: AppPallete
                                                            .textColor
                                                            .withOpacity(0.7),
                                                        fontWeight:
                                                            FontWeight.w500)),
                                              ),
                                            if (firstUserMsg.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4.0),
                                                child: Text(
                                                    'Q: ' + firstUserMsg,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        color: AppPallete
                                                            .textColor
                                                            .withOpacity(0.8),
                                                        fontWeight:
                                                            FontWeight.w500)),
                                              ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4.0),
                                              child: Text(
                                                  'Messages: ${chatHistory?.length ?? 0}',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          AppPallete.gradient2,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios,
                                          color: AppPallete.gradient2,
                                          size: 18),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back,
                                  color: AppPallete.gradient1),
                              onPressed: () => setModalState(() {
                                previewSessionIndex = null;
                              }),
                            ),
                            SizedBox(width: 4),
                            Text('Session ${previewSessionIndex! + 1}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppPallete.gradient1,
                                    fontSize: 16)),
                            SizedBox(width: 8),
                            if (allSessions[previewSessionIndex!]
                                    ['created_at'] !=
                                null)
                              Text(
                                allSessions[previewSessionIndex!]['created_at']
                                    .toString()
                                    .split('T')
                                    .first,
                                style: TextStyle(
                                    color:
                                        AppPallete.textColor.withOpacity(0.7),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                          ],
                        ),
                      ),
                      Divider(color: AppPallete.gradient1.withOpacity(0.08)),
                      Flexible(
                        child: ListView.builder(
                          padding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: (allSessions[previewSessionIndex!]
                                      ['chat_history'] as List?)
                                  ?.length ??
                              0,
                          itemBuilder: (context, msgIdx) {
                            final msg = (allSessions[previewSessionIndex!]
                                ['chat_history'] as List)[msgIdx];
                            final isUser = msg['role'] == 'user';
                            return Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: EdgeInsets.symmetric(vertical: 8),
                                padding: EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 18),
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.75),
                                decoration: BoxDecoration(
                                  color: isUser ? null : Colors.white,
                                  gradient: isUser
                                      ? LinearGradient(
                                          colors: [
                                            AppPallete.gradient1,
                                            AppPallete.gradient2
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  borderRadius:
                                      BorderRadius.circular(18).copyWith(
                                    bottomRight: isUser
                                        ? Radius.circular(8)
                                        : Radius.circular(18),
                                    bottomLeft: isUser
                                        ? Radius.circular(18)
                                        : Radius.circular(8),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppPallete.gradient1
                                          .withOpacity(0.10),
                                      blurRadius: 12,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  msg['content'] ?? '',
                                  style: TextStyle(
                                    color: isUser
                                        ? Colors.white
                                        : AppPallete.textColor,
                                    fontSize: 16,
                                    height: 1.5,
                                    fontWeight: isUser
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppPallete.gradient1,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              padding: EdgeInsets.symmetric(vertical: 14),
                              elevation: 2,
                            ),
                            icon: Icon(Icons.open_in_new, color: Colors.white),
                            label: Text('Load in Main Chat',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            onPressed: () {
                              selectSession(previewSessionIndex!);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
