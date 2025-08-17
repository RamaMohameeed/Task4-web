import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import 'services/gpt_service.dart';
import 'widgets/chat_bubble.dart';
import 'models/metrics_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MetricsProvider(),
      child: MaterialApp(
        title: 'Voice GPT Chat',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const ChatScreen(),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GPTService _gpt = GPTService();
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;

  final FlutterTts _tts = FlutterTts();
  bool _ttsEnabled = true;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initPermissions();
    _initTts();
  }

  Future<void> _initPermissions() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _initTts() async {
    await _tts.setSharedInstance(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (!mounted) return;
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
      },
    );

    if (available) {
      if (!mounted) return;
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _controller.text = result.recognizedWords;
          });
          if (result.finalResult) {
            _sendMessage(override: result.recognizedWords);
            _speech.stop();
            setState(() => _isListening = false);
          }
        },
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );
    } else {
      if (!mounted) return;
      setState(() {
        _isListening = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Speech recognition not available")),
      );
    }
  }

  void _stopListening() {
    _speech.stop();
    if (!mounted) return;
    setState(() => _isListening = false);
  }

  Future<void> _speak(String text) async {
    if (!_ttsEnabled) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _sendMessage({String? override}) async {
    final text = (override ?? _controller.text).trim();
    if (text.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _controller.clear();
      _loading = true;
    });

    try {
      final result = await _gpt.sendMessage(text);

      if (!mounted) return;
      Provider.of<MetricsProvider>(context, listen: false).addDuration(result['durationMs']);

      setState(() {
        _messages.add({'role': 'assistant', 'text': result['reply']});
        _loading = false;
      });

      await _speak(result['reply']);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _messages.add({'role': 'assistant', 'text': 'Error: $e'});
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _controller.dispose();
    super.dispose();
  }

  PreferredSizeWidget _buildHeader() {
    return AppBar(
      title: const Text('Voice GPT Chat'),
      actions: [
        IconButton(
          tooltip: 'Toggle TTS',
          icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off),
          onPressed: () {
            if (!mounted) return;
            setState(() => _ttsEnabled = !_ttsEnabled);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = Provider.of<MetricsProvider>(context);
    return Scaffold(
      appBar: _buildHeader(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final m = _messages[index];
                  final isUser = m['role'] == 'user';
                  return ChatBubble(text: m['text'] as String, isUser: isUser);
                },
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    onPressed: () {
                      if (_isListening) {
                        _stopListening();
                      } else {
                        _startListening();
                      }
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: "Type or press mic to speak...",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _sendMessage(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Row(
                children: [
                  Text('Requests: ${metrics.durations.length}'),
                  const SizedBox(width: 16),
                  Text('Avg: ${metrics.averageMs.toStringAsFixed(1)} ms'),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      if (!mounted) return;
                      setState(() => _messages.clear());
                      metrics.clear();
                    },
                    child: const Text('Clear'),
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
