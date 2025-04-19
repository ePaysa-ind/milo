// lib/widgets/openai_check_wrapper.dart
import 'package:flutter/material.dart';
import '../utils/config.dart';
import '../utils/logger.dart';
import '../screens/api_key_screen.dart';

class OpenAICheckWrapper extends StatefulWidget {
  final Widget child;
  final bool requiresKey;

  const OpenAICheckWrapper({
    Key? key,
    required this.child,
    this.requiresKey = true,
  }) : super(key: key);

  @override
  _OpenAICheckWrapperState createState() => _OpenAICheckWrapperState();
}

class _OpenAICheckWrapperState extends State<OpenAICheckWrapper> {
  static const String _tag = 'OpenAIWrapper';
  bool _isChecking = true;
  bool _isKeyConfigured = false;

  @override
  void initState() {
    super.initState();
    _checkApiKey();
  }

  Future<void> _checkApiKey() async {
    final isConfigured = AppConfig().isOpenAIConfigured;
    Logger.info(_tag, 'Checking if OpenAI API key is configured: $isConfigured');

    if (mounted) {
      setState(() {
        _isKeyConfigured = isConfigured;
        _isChecking = false;
      });
    }
  }

  Future<void> _setupApiKey() async {
    Logger.info(_tag, 'Navigating to API key setup screen');

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const ApiKeySetupScreen(),
      ),
    );

    if (result == true) {
      // API key was configured successfully
      Logger.info(_tag, 'API key was configured successfully');
      if (mounted) {
        setState(() {
          _isKeyConfigured = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we're still checking, show a loading indicator
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // If the key is configured or not required, show the child widget
    if (_isKeyConfigured || !widget.requiresKey) {
      return widget.child;
    }

    // If the key is required but not configured, show a setup screen
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Key Required'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.key_off,
              size: 64,
              color: Colors.orange,
            ),
            const SizedBox(height: 24),
            const Text(
              'OpenAI API Key Required',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'To use AI features like memory transcription and summarization, '
                  'you need to configure an OpenAI API key.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _setupApiKey,
              child: const Text('Set Up API Key'),
            ),
            if (!widget.requiresKey) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isKeyConfigured = true; // Pretend it's configured to proceed
                  });
                },
                child: const Text('Continue Without AI Features'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}