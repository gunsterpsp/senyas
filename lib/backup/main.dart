import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

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

  Future<void> startCamera() async {
    final frontCamera = cameras!.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras!.first,
    );

    controller = CameraController(frontCamera, ResolutionPreset.medium);
    await controller!.initialize();
    if (!mounted) return;
    setState(() {
      isCameraActive = true;
      prediction = "Detecting...";
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) => captureAndSend());
  }

  Future<void> stopCamera() async {
    timer?.cancel();
    await controller?.dispose();
    setState(() {
      isCameraActive = false;
      controller = null;
      prediction = 'Tap Start to Begin';
      handLandmarks = null;
    });
  }

  Future<void> captureAndSend() async {
    if (isProcessing || controller == null || !controller!.value.isInitialized) return;
    isProcessing = true;

    try {
      final XFile file = await controller!.takePicture();
      Uint8List bytes = await file.readAsBytes();
      String base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('http://212.85.26.238:8000/predict'),
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
      print("Error: $e");
    } finally {
      isProcessing = false;
    }
  }

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
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isCameraActive &&
              controller != null &&
              controller!.value.isInitialized)
            Positioned.fill(child: CameraPreview(controller!)),

          if (isCameraActive &&
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

          if (!isCameraActive)
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

          if (isCameraActive)
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

          if (isCameraActive)
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

          if (isCameraActive && prediction != "Tap Start to Begin")
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
    'assets/signlanguage_logo2.jpg',
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
