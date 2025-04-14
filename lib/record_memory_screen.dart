import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:milo/services/audio_input_service.dart';
import 'package:milo/services/storage_service.dart';

class RecordMemoryScreen extends StatefulWidget {
  const RecordMemoryScreen({super.key});

  @override
  State<RecordMemoryScreen> createState() => _RecordMemoryScreenState();
}

class _RecordMemoryScreenState extends State<RecordMemoryScreen> {
  FlutterSoundRecorder? _recorder;
  final StorageService _storageService = StorageService();

  bool _isRecording = false;
  String? _filePath;
  Timer? _timer;
  int _recordDuration = 0;
  int _memoryCount = 1; // For naming memories
  bool _isUploading = false;
  bool _isTestingUpload = false;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await _recorder!.openRecorder();
    await Permission.microphone.request();
    await Permission.storage.request();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder?.closeRecorder();
    super.dispose();
  }

  Future<String> _getFilePath(String title) async {
    final dir = await getTemporaryDirectory();
    String timestamp = DateFormat('MMMM_d_yyyy').format(DateTime.now());
    return '${dir.path}/${title}_$timestamp.aac';
  }

  void _startRecording() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync().where((f) => f.path.endsWith('.aac')).toList();
    _memoryCount = files.length + 1;

    String defaultTitle = "Memory $_memoryCount";
    _filePath = await _getFilePath(defaultTitle);

    await _recorder!.startRecorder(
      toFile: _filePath,
      codec: Codec.aacADTS,
    );

    setState(() {
      _isRecording = true;
      _recordDuration = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      setState(() {
        _recordDuration++;
      });

      if (_recordDuration >= 30) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() async {
    await _recorder!.stopRecorder();
    _timer?.cancel();
    setState(() {
      _isRecording = false;
    });

    _showSavePrompt();
  }

  void _showSavePrompt() {
    String initialTitle = "Memory $_memoryCount";
    TextEditingController controller = TextEditingController(text: initialTitle);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Save Memory?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Enter memory title'),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await File(_filePath!).delete();
              } catch (e) {
                print("Error deleting file: $e");
              }
              Navigator.pop(context);
            },
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () async {
              print("Yes button pressed");

              Navigator.pop(context);

              setState(() {
                _isUploading = true;
              });

              String enteredTitle = controller.text.trim();
              if (enteredTitle.isEmpty) {
                enteredTitle = "Memory $_memoryCount";
              }

              try {
                File audioFile = File(_filePath!);
                bool exists = await audioFile.exists();
                print("File exists: $exists");

                if (!exists) {
                  throw Exception("Recording file not found");
                }

                print("Calling StorageService.uploadAudio...");

                // Updated to match StorageService implementation (2 parameters only)
                final downloadUrl = await _storageService.uploadAudio(
                  audioFile,
                  enteredTitle,
                ).timeout(
                  const Duration(seconds: 60),
                  onTimeout: () {
                    print("⚠️ Upload timeout after 60 seconds");
                    throw TimeoutException('Upload timed out after 60 seconds');
                  },
                );

                print("Upload completed, download URL: $downloadUrl");

                // First check if still mounted
                if (!mounted) return;

                // Then update state and show feedback
                setState(() {
                  _isUploading = false;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Memory saved to cloud!')),
                );

                // Add a small delay before navigation
                await Future.delayed(const Duration(milliseconds: 100));

                //check mounted again before navigation
                if (!mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
                Navigator.pushNamed(context, '/memories');
              } catch (e) {
                print("Error in upload process: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error saving memory: $e')),
                  );
                  setState(() {
                    _isUploading = false;
                  });
                }
              }
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _testUpload() async {
    setState(() {
      _isTestingUpload = true;
    });

    try {
      final result = await _storageService.testUpload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result ? 'Test upload successful!' : 'Test upload failed!')),
        );
      }
    } catch (e) {
      print("Test upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test upload error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingUpload = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record a Memory'),
        backgroundColor: Colors.teal,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isUploading || _isTestingUpload)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(_isTestingUpload ? 'Testing upload...' : 'Uploading to cloud...'),
                ],
              )
            else
              Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                size: 100,
                color: _isRecording ? Colors.red : Colors.teal,
              ),
            const SizedBox(height: 20),
            Text(
              _formatDuration(_recordDuration),
              style: const TextStyle(fontSize: 30),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isUploading || _isTestingUpload ? null : (_isRecording ? _stopRecording : _startRecording),
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isUploading || _isTestingUpload || _isRecording ? null : _testUpload,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
              ),
              child: const Text('Test Upload'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}