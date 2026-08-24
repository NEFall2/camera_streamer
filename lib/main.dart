void _toggleStream() {
    if (_isStreaming) {
      _controller?.stopImageStream();
      _channel?.sink.close();
      setState(() => _isStreaming = false);
    } else {
      final ip = _ipController.text.trim();
      try {
        _channel = WebSocketChannel.connect(Uri.parse('ws://$ip:8765'));
        setState(() => _isStreaming = true);

        _controller?.startImageStream((image) {
          final now = DateTime.now();
          if (now.difference(_lastFrameSent).inMilliseconds < 50) return; // 20 FPS
          if (_isProcessing || !_isStreaming) return;

          _isProcessing = true;
          _lastFrameSent = now;

          try {
            if (_channel != null) {
              // Fusion de tous les plans mémoire (Y + UV pour iOS)
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
      }
    }
  }