import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CameraStreamApp(),
  ));
}

class CameraStreamApp extends StatefulWidget {
  const CameraStreamApp({super.key});

  @override
  State<CameraStreamApp> createState() => _CameraStreamAppState();
}

class _CameraStreamAppState extends State<CameraStreamApp> {
  CameraController? _controller;
  WebSocketChannel? _channel;
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.XX");
  
  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _isInitializing = true;
  DateTime _lastFrameSent = DateTime.now();

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(
          cameras.first,
          ResolutionPreset.veryHigh, // Mode 1080p (1920x1080)
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.bgra8888, // Stabilité iOS
        );
        await _controller!.initialize();
      }
    } catch (e) {
      debugPrint("Erreur caméra : $e");
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _toggleStream() {
    if (_isStreaming) {
      _controller?.stopImageStream();
      _channel?.sink.close();
      setState(() => _isStreaming = false);
    } else {
      final ip = _ipController.text.trim();
      if (ip.isEmpty) return;

      try {
        _channel = WebSocketChannel.connect(Uri.parse('ws://$ip:8765'));
        setState(() => _isStreaming = true);

        _controller?.startImageStream((CameraImage image) {
          final now = DateTime.now();
          // Limite à 1 image toutes les 50ms (20 FPS max) pour protéger la mémoire en 1080p
          if (now.difference(_lastFrameSent).inMilliseconds < 50) return;
          if (_isProcessing || !_isStreaming) return;

          _isProcessing = true;
          _lastFrameSent = now;

          try {
            if (_channel != null) {
              final WriteBuffer allBytes = WriteBuffer();
              for (final Plane plane in image.planes) {
                allBytes.putUint8List(plane.bytes);
              }
              _channel!.sink.add(allBytes.done().buffer.asUint8List());
            }
          } catch (e) {
            debugPrint("Erreur envoi WebSocket : $e");
          } finally {
            _isProcessing = false;
          }
        });
      } catch (e) {
        setState(() => _isStreaming = false);
        debugPrint("Erreur connexion WebSocket : $e");
      }
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _channel?.sink.close();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: Text("Erreur d'initialisation de la caméra")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Cam Streamer 1080p'),
        backgroundColor: Colors.blueGrey,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: CameraPreview(_controller!),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Adresse IP du PC',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.datetime,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _toggleStream,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    backgroundColor: _isStreaming ? Colors.red : Colors.green,
                  ),
                  child: Text(
                    _isStreaming ? 'STOP' : 'START',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}