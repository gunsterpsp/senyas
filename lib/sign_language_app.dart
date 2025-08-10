import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'globals.dart';
import 'package:flutter/foundation.dart';

class MyApp extends StatefulWidget {
  final String role;
  const MyApp({super.key, required this.role});

  @override
  _Sign2TextAppState createState() => _Sign2TextAppState();
}

class _Sign2TextAppState extends State<MyApp> {
  CameraController? controller;
  String prediction = 'Tap Start to Begin';
  Timer? timer;
  List<dynamic>? handLandmarks;
  bool isProcessing = false;
  bool isCameraActive = false;
  final FlutterTts flutterTts = FlutterTts();
  bool get isAdmin => widget.role == 'admin';
  Timer? fetchTimer;
  Uint8List? latestImage;

  @override
  void initState() {
    super.initState();
    if (!isAdmin) {
      fetchTimer = Timer.periodic(
        Duration(milliseconds: 300),
        (_) => fetchLatestImage(),
      );
    }
  }

  void startStreamLoop() {
    isProcessing = false;
    prediction = "Detecting...";
    isCameraActive = true;
    if (!mounted) return;

    Future.doWhile(() async {
      if (!mounted || !isCameraActive || controller == null) return false;
      await captureAndSend();
      await Future.delayed(Duration(milliseconds: 100));
      return true;
    });
  }

  // Inside _Sign2TextAppState

  int selectedCameraIndex = 0;

  Future<void> switchCamera() async {
    if (cameras == null || cameras!.isEmpty) return;

    selectedCameraIndex = (selectedCameraIndex + 1) % cameras!.length;
    final newCamera = cameras![selectedCameraIndex];

    await controller?.dispose();
    controller = CameraController(newCamera, ResolutionPreset.low);
    await controller!.initialize();

    if (mounted) {
      setState(() {});
      startStreamLoop();
    }
  }

  Future<void> startCamera() async {
    if (cameras == null || cameras!.isEmpty) {
      print("No camera found.");
      return;
    }

    selectedCameraIndex = cameras!.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    if (selectedCameraIndex == -1) selectedCameraIndex = 0;

    controller = CameraController(
      cameras![selectedCameraIndex],
      ResolutionPreset.low,
    );
    await controller!.initialize();

    setState(() {
      isCameraActive = true;
    });

    startStreamLoop();
  }

  // Future<void> startCamera() async {
  //   if (cameras == null || cameras!.isEmpty) {
  //     print("No camera found.");
  //     return;
  //   }

  //   final frontCamera = cameras!.firstWhere(
  //     (camera) => camera.lensDirection == CameraLensDirection.front,
  //     orElse: () => cameras!.first,
  //   );

  //   controller = CameraController(frontCamera, ResolutionPreset.low);
  //   await controller!.initialize();
  //   setState(() {
  //     isCameraActive = true;
  //   });

  //   startStreamLoop();
  // }

  Future<void> stopCamera() async {
    setState(() {
      isCameraActive = false;
      prediction = 'Tap Start to Begin';
      handLandmarks = null;
    });
    await controller?.dispose();
    controller = null;
    // 🔥 Add this block
    if (isAdmin) {
      try {
        await http.post(Uri.parse('http://148.230.96.114:8000/delete_latest'));
      } catch (e) {
        if (kDebugMode) print("Failed to delete latest image: $e");
      }
    }
  }

  Future<void> captureAndSend() async {
    if (isProcessing || controller == null || !controller!.value.isInitialized)
      return;
    isProcessing = true;

    try {
      final XFile file = await controller!.takePicture();
      Uint8List bytes = await file.readAsBytes();
      String base64Image = base64Encode(bytes);

      await http.post(
        Uri.parse('http://148.230.96.114:8000/upload_frame'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      final response = await http.post(
        Uri.parse('http://148.230.96.114:8000/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      final result = jsonDecode(response.body);
      setState(() {
        prediction =
            "${result['prediction']} (${(result['confidence'] * 100).toStringAsFixed(2)}%)";
        handLandmarks = result['landmarks'];
      });
    } catch (e) {
      // print("Error: $e");
    } finally {
      isProcessing = false;
    }
  }

  Future<void> fetchLatestImage() async {
    try {
      final response = await http.get(
        Uri.parse('http://148.230.96.114:8000/static/latest.jpg'),
      );

      if (response.statusCode == 200) {
        if (latestImage == null ||
            !listEquals(response.bodyBytes, latestImage)) {
          setState(() {
            latestImage = response.bodyBytes;
          });

          // 🔥 Call predict endpoint to get label for this image
          final base64Image = base64Encode(response.bodyBytes);
          final predictResponse = await http.post(
            Uri.parse('http://148.230.96.114:8000/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': base64Image}),
          );

          final result = jsonDecode(predictResponse.body);
          setState(() {
            prediction =
                "${result['prediction']} (${(result['confidence'] * 100).toStringAsFixed(2)}%)";
          });
        }
      }
    } catch (e) {
      print("Error fetching latest image or prediction: $e");
    }
  }

  // Future<void> fetchLatestImage() async {
  //   try {
  //     final response = await http.get(
  //       Uri.parse('http://148.230.96.114:8000/static/latest.jpg'),
  //     );
  //     if (response.statusCode == 200) {
  //       if (latestImage == null ||
  //           !listEquals(response.bodyBytes, latestImage)) {
  //         setState(() {
  //           latestImage = response.bodyBytes;
  //         });
  //       }
  //     }
  //   } catch (e) {
  //     print("Error fetching latest image: $e");
  //   }
  // }

  Future<void> speakText() async {
    if (prediction.isNotEmpty &&
        prediction != 'Loading...' &&
        prediction != 'Tap Start to Begin' &&
        prediction != 'Detecting...') {
      String labelOnly = prediction.split(' (').first;
      await flutterTts.speak(labelOnly);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    timer?.cancel();
    fetchTimer?.cancel();
    flutterTts.stop();
    if (isAdmin) {
      http.post(Uri.parse('http://148.230.96.114:8000/delete_latest'));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isAdmin &&
              isCameraActive &&
              controller != null &&
              controller!.value.isInitialized)
            Positioned.fill(child: CameraPreview(controller!)),

          if (isAdmin &&
              isCameraActive &&
              controller != null &&
              controller!.value.isInitialized)
            Positioned.fill(
              child: CustomPaint(
                painter: HandPainter(
                  landmarks: handLandmarks,
                  imageSize: Size(
                    controller!.value.previewSize!.height,
                    controller!.value.previewSize!.width,
                  ),
                ),
              ),
            ),

          if (!isAdmin && latestImage != null)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(latestImage),
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: MemoryImage(latestImage!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          if (!isCameraActive && isAdmin)
            const Center(
              child: Text(
                "Camera not active",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
            ),

          if (!isAdmin && latestImage == null)
            const Center(
              child: Text(
                "No live streamer available",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
            ),

          if (isAdmin)
            Positioned(
              bottom: 150,
              left: 16,
              child: ElevatedButton.icon(
                onPressed: speakText,
                icon: const Icon(Icons.volume_up),
                label: const Text("Speak"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          if (isAdmin)
            Positioned(
              bottom: 150,
              right: 16,
              child: ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const InstructionCarousel(),
                  );
                },
                icon: const Icon(Icons.info_outline),
                label: const Text("Info"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withOpacity(0.8),
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          if (isAdmin)
            Positioned(
              bottom: 90,
              left: 16,
              child: ElevatedButton.icon(
                onPressed: isCameraActive ? stopCamera : startCamera,
                icon: Icon(isCameraActive ? Icons.stop : Icons.play_arrow),
                label: Text(isCameraActive ? "Stop Camera" : "Start Camera"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.8),
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          if (isAdmin)
            Positioned(
              bottom: 90,
              right: 16,
              child: ElevatedButton.icon(
                onPressed: switchCamera,
                icon: const Icon(Icons.cameraswitch),
                label: const Text("Switch Camera"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withOpacity(0.8),
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          if (isAdmin && isCameraActive && prediction != "Tap Start to Begin")
            Positioned(
              bottom: 32,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black.withOpacity(0.5),
                child: Text(
                  prediction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (!isAdmin && prediction != "Tap Start to Begin")
            Positioned(
              bottom: 32,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black.withOpacity(0.5),
                child: Text(
                  prediction,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              tooltip: "Logout",
              onPressed: () {
                stopCamera();
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class HandPainter extends CustomPainter {
  final List<dynamic>? landmarks;
  final Size imageSize;

  HandPainter({this.landmarks, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks == null) return;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3;

    for (var hand in landmarks!) {
      for (var point in hand) {
        double x = point['x'] * size.width;
        double y = point['y'] * size.height;
        canvas.drawCircle(Offset(x, y), 4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class InstructionCarousel extends StatefulWidget {
  const InstructionCarousel({super.key});

  @override
  State<InstructionCarousel> createState() => _InstructionCarouselState();
}

class _InstructionCarouselState extends State<InstructionCarousel> {
  int _index = 0;
  final List<String> _images = [
    'assets/signlanguage_logo1.png',
    'assets/signlanguage_logo2.png',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Instructions"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(_images[_index], height: 150),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _index = (_index - 1 + _images.length) % _images.length;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () {
                  setState(() {
                    _index = (_index + 1) % _images.length;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Use sign language clearly in front of the camera."),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }
}
