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
  bool ttsAttempted = false; // New flag to track if TTS was attempted for this message

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
  bool _isMounted = true; // Track if the widget is mounted
  bool _ttsServiceAvailable = true; // Track if TTS service is available
  int _ttsFailedAttempts = 0; // Track failed TTS attempts
  static const int _maxTtsFailedAttempts = 3; // Max failed attempts before disabling TTS

  @override
  void initState() {
    super.initState();
    _isMounted = true;

    Logger.info(_tag, 'Initializing conversation screen');

    if (widget.initialPrompt.isNotEmpty) {
      Logger.info(_tag, 'Starting conversation with initial prompt: ${widget.initialPrompt}');
      // Add slight delay to ensure screen is built
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_isMounted) {
          _sendMessage(widget.initialPrompt);
        }
      });
    }

    // Set up audio player state listener
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!_isMounted) return;

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

    // Check if TTS is globally enabled in the OpenAIService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted) return;

      final openAIService = Provider.of<OpenAIService>(context, listen: false);
      _ttsServiceAvailable = openAIService.isTTSEnabled;

      if (!_ttsServiceAvailable && _isSpeechToSpeechEnabled) {
        // If TTS is globally disabled but enabled in the UI, update the UI
        setState(() {
          _isSpeechToSpeechEnabled = false;
        });

        // Show message to user
        if (_isMounted) {
          _showSnackBar('Text-to-speech is not available with the current API configuration.', isError: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _isMounted = false;
    _textController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    Logger.info(_tag, 'Conversation screen disposed');
    super.dispose();
  }

  // Safe setState that checks if the widget is still mounted
  void _safeSetState(VoidCallback fn) {
    if (_isMounted && mounted) {
      setState(fn);
    } else {
      Logger.warning(_tag, 'Attempted to setState after dispose');
    }
  }

  // Show a snackbar with custom styling
  void _showSnackBar(String message, {bool isError = false, int durationSeconds = 4}) {
    if (!_isMounted || !mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars(); // Clear any existing snackbars

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.teal,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: durationSeconds),
        action: isError ? SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ) : null,
      ),
    );
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
    if (!_isMounted) return;

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

        _safeSetState(() {
          _isRecording = true;
        });

        Logger.info(_tag, 'Voice recording started');
      } else {
        Logger.error(_tag, 'Microphone permission denied');
        if (_isMounted) {
          _showSnackBar('Microphone permission denied', isError: true);
        }
      }
    } catch (e) {
      Logger.error(_tag, 'Error starting recording: $e');
      if (_isMounted) {
        _showSnackBar('Failed to start recording: Please check microphone permissions', isError: true);
      }
    }
  }

  // Stop voice recording and process audio
  Future<void> _stopRecording() async {
    if (!_isMounted) return;

    Logger.info(_tag, 'Stopping voice recording');

    try {
      final path = await _recorder.stop();

      _safeSetState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      if (path == null) {
        Logger.error(_tag, 'Recording failed: No path returned');
        _safeSetState(() {
          _isProcessing = false;
        });

        if (_isMounted) {
          _showSnackBar('Recording failed. Please try again', isError: true);
        }
        return;
      }

      Logger.info(_tag, 'Recording stopped, processing audio...');

      // Get the OpenAI service
      final openAIService = Provider.of<OpenAIService>(context, listen: false);

      // Transcribe the audio
      try {
        final transcription = await openAIService.transcribeAudio(path);
        Logger.info(_tag, 'Audio transcribed: $transcription');

        if (!_isMounted) return;

        // Add user message with transcription
        _addMessage(transcription, true);

        // Now get AI response
        await _getAIResponse(transcription);
      } catch (e) {
        Logger.error(_tag, 'Error transcribing audio: $e');
        if (_isMounted) {
          _showSnackBar('Could not understand audio. Please try speaking more clearly or typing your message', isError: true);
        }
      }

      _safeSetState(() {
        _isProcessing = false;
      });
    } catch (e) {
      Logger.error(_tag, 'Error processing recording: $e');
      if (_isMounted) {
        _showSnackBar('Failed to process recording: $e', isError: true);
      }

      _safeSetState(() {
        _isProcessing = false;
      });
    }
  }

  // Send a text message
  Future<void> _sendMessage(String text) async {
    if (!_isMounted) return;
    if (text.trim().isEmpty) return;

    Logger.info(_tag, 'Sending message: $text');

    _safeSetState(() {
      _isSending = true;
    });

    // Add user message to the conversation
    _addMessage(text, true);

    // Clear the text input
    _textController.clear();

    // Get AI response
    await _getAIResponse(text);

    _safeSetState(() {
      _isSending = false;
    });
  }

  // Get response from OpenAI
  Future<void> _getAIResponse(String userMessage) async {
    if (!_isMounted) return;

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

      if (!_isMounted) return;

      Logger.info(_tag, 'AI response received');

      // Add AI message to the conversation
      final message = _addMessage(response, false);

      // Convert to speech if enabled and service is available
      if (_isSpeechToSpeechEnabled && _ttsServiceAvailable) {
        await _generateAndPlaySpeech(message, openAIService);
      }
    } catch (e) {
      if (!_isMounted) return;

      Logger.error(_tag, 'Error getting AI response: $e');

      // Add error message
      _addMessage('Sorry, I had trouble connecting. Please try again.', false);

      if (_isMounted) {
        _showSnackBar('Error communicating with AI service. Please check your internet connection.', isError: true);
      }
    }
  }

  // Generate speech for a message and play it
  Future<void> _generateAndPlaySpeech(Message message, OpenAIService openAIService) async {
    if (!_isMounted) return;

    Logger.info(_tag, 'Converting AI response to speech');

    // Mark that TTS was attempted for this message
    message.ttsAttempted = true;

    try {
      // First check if TTS is still enabled in the service
      if (!openAIService.isTTSEnabled) {
        if (_isMounted && _isSpeechToSpeechEnabled) {
          _safeSetState(() {
            _ttsServiceAvailable = false;
            _isSpeechToSpeechEnabled = false;
          });
          _showSnackBar('Text-to-speech service is not available', isError: true);
        }
        return;
      }

      // Try to generate speech with standard quality first
      final speechFile = await openAIService.textToSpeech(
        message.text,
        useHighQuality: false, // Use standard quality for reliability
      );

      if (!_isMounted) return;

      if (speechFile != null) {
        // Reset failed attempts counter on success
        _ttsFailedAttempts = 0;

        message.audioFile = speechFile;
        Logger.info(_tag, 'Speech generated successfully');

        // Auto-play the response if still mounted
        if (_isMounted) {
          _playMessageAudio(message);
        }
      } else {
        // If null was returned but no exception occurred
        Logger.warning(_tag, 'Speech generation returned null without error');
        _handleTtsFailure('Failed to generate speech. Using text-only mode.');
      }
    } on OpenAIServiceException catch (e) {
      if (!_isMounted) return;

      Logger.error(_tag, 'OpenAI service error generating speech: ${e.code} - ${e.message}');

      // Check for non-recoverable errors related to TTS availability
      if (!e.isRecoverable || e.code == 'tts_not_available') {
        Logger.error(_tag, 'TTS is not available, disabling speech-to-speech feature');

        // Disable TTS in the UI
        _safeSetState(() {
          _ttsServiceAvailable = false;
          _isSpeechToSpeechEnabled = false;
        });

        _showSnackBar('Text-to-speech service is not available with your API configuration', isError: true);
      } else {
        // For recoverable errors, increment failed attempts
        _handleTtsFailure('Failed to generate speech. We\'ll try again next time.');
      }
    } catch (e) {
      if (!_isMounted) return;

      Logger.error(_tag, 'Error generating speech: $e');
      _handleTtsFailure('Failed to generate speech. Please check your internet connection.');
    }
  }

  // Handle TTS failure with proper UI updates
  void _handleTtsFailure(String message) {
    if (!_isMounted) return;

    _ttsFailedAttempts++;
    Logger.warning(_tag, 'TTS failed attempt: $_ttsFailedAttempts of $_maxTtsFailedAttempts');

    // If we've reached the max failed attempts, disable TTS to avoid further failures
    if (_ttsFailedAttempts >= _maxTtsFailedAttempts) {
      _safeSetState(() {
        _isSpeechToSpeechEnabled = false;
      });
      _showSnackBar('Voice responses have been temporarily disabled due to connection issues', isError: true);
    } else {
      _showSnackBar(message, isError: true);
    }
  }

  // Add a message to the conversation
  Message _addMessage(String text, bool isUser) {
    if (!_isMounted) {
      // Return a dummy message if not mounted (should not happen)
      return Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        isUser: isUser,
        text: text,
        timestamp: DateTime.now(),
      );
    }

    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      isUser: isUser,
      text: text,
      timestamp: DateTime.now(),
    );

    _safeSetState(() {
      _messages.add(message);
    });

    // Scroll to the bottom after adding message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isMounted) {
        _scrollToBottom();
      }
    });

    return message;
  }

  // Play audio for a message
  Future<void> _playMessageAudio(Message message) async {
    if (!_isMounted) return;
    if (message.audioFile == null) return;

    Logger.info(_tag, 'Playing audio for message: ${message.id}');

    // Stop any currently playing audio
    for (final msg in _messages) {
      if (msg.isPlaying) {
        _safeSetState(() {
          msg.isPlaying = false;
        });
      }
    }

    // Play this message's audio
    _safeSetState(() {
      message.isPlaying = true;
    });

    try {
      await _audioPlayer.stop(); // Ensure previous audio is stopped
      await _audioPlayer.play(DeviceFileSource(message.audioFile!.path));

      // Listen for completion to update state
      _audioPlayer.onPlayerComplete.listen((_) {
        if (_isMounted) {
          _safeSetState(() {
            message.isPlaying = false;
          });
        }
      });
    } catch (e) {
      Logger.error(_tag, 'Error playing audio: $e');
      _safeSetState(() {
        message.isPlaying = false;
      });

      if (_isMounted) {
        _showSnackBar('Error playing audio: Please try again', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Handle back button press
        if (_isRecording) {
          // If recording, stop it first
          await _stopRecording();
          return false; // Don't navigate back yet
        }
        return true; // Allow back navigation
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ask Milo'),
          actions: [
            // Toggle speech-to-speech button (disabled if service not available)
            IconButton(
              icon: Icon(_isSpeechToSpeechEnabled
                  ? Icons.volume_up
                  : Icons.volume_off),
              onPressed: _ttsServiceAvailable ? () {
                _safeSetState(() {
                  _isSpeechToSpeechEnabled = !_isSpeechToSpeechEnabled;
                });
                Logger.info(_tag, 'Speech-to-speech ${_isSpeechToSpeechEnabled ? 'enabled' : 'disabled'}');

                _showSnackBar(
                  _isSpeechToSpeechEnabled
                      ? 'Voice responses enabled'
                      : 'Voice responses disabled',
                  isError: false,
                  durationSeconds: 2,
                );
              } : null, // Disabled if TTS service is not available
              tooltip: _ttsServiceAvailable
                  ? (_isSpeechToSpeechEnabled
                  ? 'Disable voice responses'
                  : 'Enable voice responses')
                  : 'Voice responses unavailable',
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

            // Show "Voice unavailable" indicator when TTS was attempted but failed
            if (!isUser && message.ttsAttempted && message.audioFile == null && _isSpeechToSpeechEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.volume_off,
                      color: Colors.grey.shade500,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Voice unavailable',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
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
            onPressed: _isProcessing || _isSending
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
                // Force UI update to enable/disable send button
                setState(() {});
              },
              enabled: !_isRecording && !_isProcessing && !_isSending,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) {
                if (!_isRecording && !_isProcessing && !_isSending && _textController.text.trim().isNotEmpty) {
                  _sendMessage(_textController.text);
                }
              },
            ),
          ),

          // Send button
          IconButton(
            icon: const Icon(Icons.send),
            color: Colors.teal,
            onPressed: (_isRecording || _isProcessing || _isSending || _textController.text.trim().isEmpty)
                ? null // Disable the button when text is empty or still busy
                : () => _sendMessage(_textController.text),
          ),
        ],
      ),
    );
  }
}