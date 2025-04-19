// lib/screens/conversation_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../services/openai_service.dart';
import '../utils/logger.dart';

class Message {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  File? audioFile;
  bool isPlaying = false;

  Message({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.audioFile,
  });
}

class ConversationScreen extends StatefulWidget {
  final String? memoryId; // Optional - if linked to a specific memory
  final String initialPrompt; // Optional - to start the conversation

  const ConversationScreen({
    Key? key,
    this.memoryId,
    this.initialPrompt = '',
  }) : super(key: key);

  @override
  _ConversationScreenState createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const String _tag = 'ConversationScreen';

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  final Record _recorder = Record();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  bool _isSending = false;
  bool _isProcessing = false;
  String _recordingPath = '';
  bool _isSpeechToSpeechEnabled = true; // Default true enabled

  @override
  void initState() {
    super.initState();

    Logger.info(_tag, 'Initializing conversation screen');

    if (widget.initialPrompt.isNotEmpty) {
      Logger.info(_tag, 'Starting conversation with initial prompt: ${widget.initialPrompt}');
      // Add slight delay to ensure screen is built
      Future.delayed(const Duration(milliseconds: 300), () {
        _sendMessage(widget.initialPrompt);
      });
    }

    // Set up audio player state listener
    _audioPlayer.onPlayerStateChanged.listen((state) {
      Logger.debug(_tag, 'Audio player state changed: $state');

      // Find the currently playing message and update its state
      for (final message in _messages) {
        if (message.isPlaying && state != PlayerState.playing) {
          setState(() {
            message.isPlaying = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    Logger.info(_tag, 'Conversation screen disposed');
    super.dispose();
  }

  // Scroll to bottom of the conversation
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Start voice recording
  Future<void> _startRecording() async {
    Logger.info(_tag, 'Starting voice recording');

    try {
      // Check if microphone permission is granted
      if (await _recorder.hasPermission()) {
        // Get temp directory for storing recording
        final tempDir = await getTemporaryDirectory();
        _recordingPath = '${tempDir.path}/audio_message_${DateTime.now().millisecondsSinceEpoch}.m4a';

        Logger.debug(_tag, 'Recording to path: $_recordingPath');

        // Configure recording settings
        await _recorder.start(
          path: _recordingPath,
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          samplingRate: 44100,
        );

        setState(() {
          _isRecording = true;
        });

        Logger.info(_tag, 'Voice recording started');
      } else {
        Logger.error(_tag, 'Microphone permission denied');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
    } catch (e) {
      Logger.error(_tag, 'Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: $e')),
      );
    }
  }

  // Stop voice recording and process audio
  Future<void> _stopRecording() async {
    Logger.info(_tag, 'Stopping voice recording');

    try {
      final path = await _recorder.stop();

      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      if (path == null) {
        Logger.error(_tag, 'Recording failed: No path returned');
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      Logger.info(_tag, 'Recording stopped, processing audio...');

      // Get the OpenAI service
      final openAIService = Provider.of<OpenAIService>(context, listen: false);

      // Transcribe the audio
      final transcription = await openAIService.transcribeAudio(path);
      Logger.info(_tag, 'Audio transcribed: $transcription');

      // Add user message with transcription
      _addMessage(transcription, true);

      // Now get AI response
      await _getAIResponse(transcription);

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      Logger.error(_tag, 'Error processing recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process recording: $e')),
      );
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Send a text message
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    Logger.info(_tag, 'Sending message: $text');

    setState(() {
      _isSending = true;
    });

    // Add user message to the conversation
    _addMessage(text, true);

    // Clear the text input
    _textController.clear();

    // Get AI response
    await _getAIResponse(text);

    setState(() {
      _isSending = false;
    });
  }

  // Get response from OpenAI
  Future<void> _getAIResponse(String userMessage) async {
    Logger.info(_tag, 'Getting AI response for: $userMessage');

    try {
      final openAIService = Provider.of<OpenAIService>(context, listen: false);

      // Format conversation history
      final conversationHistory = _messages.map((msg) => {
        'role': msg.isUser ? 'user' : 'assistant',
        'content': msg.text,
      }).toList();

      // Get response from GPT
      final response = await openAIService.chatWithGPT(
        prompt: userMessage,
        conversation: conversationHistory,
      );

      Logger.info(_tag, 'AI response received');

      // Add AI message to the conversation
      final message = _addMessage(response, false);

      // Convert to speech if enabled
      if (_isSpeechToSpeechEnabled) {
        Logger.info(_tag, 'Converting AI response to speech');

        try {
          final speechFile = await openAIService.textToSpeech(response);
          message.audioFile = speechFile;
          Logger.info(_tag, 'Speech generated successfully');

          // Auto-play the response
          _playMessageAudio(message);
        } catch (e) {
          Logger.error(_tag, 'Error generating speech: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate speech')),
          );
        }
      }
    } catch (e) {
      Logger.error(_tag, 'Error getting AI response: $e');

      // Add error message
      _addMessage('Sorry, I had trouble connecting. Please try again.', false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Add a message to the conversation
  Message _addMessage(String text, bool isUser) {
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      isUser: isUser,
      text: text,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(message);
    });

    // Scroll to the bottom after adding message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    return message;
  }

  // Play audio for a message
  Future<void> _playMessageAudio(Message message) async {
    if (message.audioFile == null) return;

    Logger.info(_tag, 'Playing audio for message: ${message.id}');

    // Stop any currently playing audio
    for (final msg in _messages) {
      if (msg.isPlaying) {
        setState(() {
          msg.isPlaying = false;
        });
      }
    }

    // Play this message's audio
    setState(() {
      message.isPlaying = true;
    });

    try {
      await _audioPlayer.play(DeviceFileSource(message.audioFile!.path));

      _audioPlayer.onPlayerComplete.listen((_) {
        setState(() {
          message.isPlaying = false;
        });
      });
    } catch (e) {
      Logger.error(_tag, 'Error playing audio: $e');
      setState(() {
        message.isPlaying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask Milo'),
        actions: [
          // Toggle speech-to-speech button
          IconButton(
            icon: Icon(_isSpeechToSpeechEnabled
                ? Icons.volume_up
                : Icons.volume_off),
            onPressed: () {
              setState(() {
                _isSpeechToSpeechEnabled = !_isSpeechToSpeechEnabled;
              });
              Logger.info(_tag, 'Speech-to-speech ${_isSpeechToSpeechEnabled ? 'enabled' : 'disabled'}');
            },
            tooltip: _isSpeechToSpeechEnabled
                ? 'Disable voice responses'
                : 'Enable voice responses',
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcomeView()
                : _buildMessagesList(),
          ),

          // Status indicator
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Processing audio...'),
                ],
              ),
            ),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  // Welcome view when no messages
  Widget _buildWelcomeView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.teal,
          ),
          const SizedBox(height: 24),
          const Text(
            'Ask me anything!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'Type your question or tap the microphone to speak.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            icon: const Icon(Icons.mic),
            label: const Text('Start Speaking'),
            onPressed: _startRecording,
          ),
        ],
      ),
    );
  }

  // Messages list view
  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16.0),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  // Individual message bubble
  Widget _buildMessageBubble(Message message) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.teal : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Message text
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black,
                  fontSize: 16.0,
                ),
              ),
            ),

            // Audio controls for assistant messages
            if (!isUser && message.audioFile != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: InkWell(
                  onTap: () => _playMessageAudio(message),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        message.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.teal,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        message.isPlaying ? 'Playing...' : 'Play voice',
                        style: const TextStyle(
                          color: Colors.teal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Input area with text field and buttons
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Microphone/stop button
          IconButton(
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            color: _isRecording ? Colors.red : null,
            onPressed: _isProcessing
                ? null
                : (_isRecording ? _stopRecording : _startRecording),
          ),

          // Text input field
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Type your message...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
              ),
              onChanged: (text){
                // Add logging here where it's safe to do so
                print('Text: "${_textController.text}", isEmpty: ${_textController.text.trim().isEmpty}');
                print('States: isRecording: $_isRecording, isProcessing: $_isProcessing, isSending: $_isSending');

                setState(() {});
              },
              // commented out enabled: !_isRecording && !_isProcessing,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) {
                _sendMessage(_textController.text);
              },
            ),
          ),

          // Send button
          IconButton(
            icon: const Icon(Icons.send),
            color: Colors.teal,
            onPressed: (_isRecording || _isProcessing || _isSending || _textController.text.trim().isEmpty)
                ? null //disables the button when text is empty
                : () => _sendMessage(_textController.text), //enables button when text is input
          ),
        ],
      ),
    );
  }
}