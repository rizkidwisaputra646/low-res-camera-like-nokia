import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img; 
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

// Import FFmpeg Kit New
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: NokiaAndroidCamera(cameras: cameras),
  ));
}

class NokiaAndroidCamera extends StatefulWidget {
  final List<CameraDescription> cameras;
  const NokiaAndroidCamera({super.key, required this.cameras});

  @override
  State<NokiaAndroidCamera> createState() => _NokiaAndroidCameraState();
}

class _NokiaAndroidCameraState extends State<NokiaAndroidCamera> {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isProcessing = false;
  String _mode = 'FOTO'; 
  int _camIdx = 0;
  Size _selectedRes = const Size(320, 240);

  @override
  void initState() {
    super.initState();
    _initCam();
  }

  Future<void> _initCam() async {
    await [Permission.camera, Permission.microphone, Permission.photos, Permission.videos].request();
    if (_controller != null) await _controller!.dispose();
    
    _controller = CameraController(
      widget.cameras[_camIdx], 
      ResolutionPreset.low, // Dasar resolusi rendah
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) { _showMsg("Kamera Error"); }
  }

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.green)));
    }

    // Logika Mirror untuk kamera depan
    bool isFrontCam = widget.cameras[_camIdx].lensDirection == CameraLensDirection.front;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Viewfinder dengan fitur MIRROR
          Positioned.fill(
            child: Transform(
              alignment: Alignment.center,
              transform: isFrontCam ? Matrix4.rotationY(math.pi) : Matrix4.identity(),
              child: CameraPreview(_controller!),
            ),
          ),

          // 2. Top Bar: Resolusi
          Positioned(
            top: 50, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _resTab("120p", const Size(160, 120)),
                _resTab("240p", const Size(320, 240)),
              ],
            ),
          ),

          // 3. Bottom UI (Android Camera Style)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              color: Colors.black.withOpacity(0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _modeTab("FOTO"),
                      const SizedBox(width: 40),
                      _modeTab("VIDEO"),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const Icon(Icons.photo_library, size: 28),
                      _shutter(),
                      IconButton(
                        icon: const Icon(Icons.flip_camera_android, color: Colors.green),
                        onPressed: () { _camIdx = _camIdx == 0 ? 1 : 0; _initCam(); },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Loader saat FFmpeg sedang bekerja
          if (_isProcessing) 
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(color: Colors.green),
                    SizedBox(height: 15),
                    Text("MENGOLAH VIDEO BURIK...", style: TextStyle(fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resTab(String label, Size size) => GestureDetector(
    onTap: () => setState(() => _selectedRes = size),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _selectedRes == size ? Colors.green : Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _modeTab(String m) => GestureDetector(
    onTap: () => setState(() => _mode = m),
    child: Text(m, style: TextStyle(color: _mode == m ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
  );

  Widget _shutter() => GestureDetector(
    onTap: _mode == 'FOTO' ? _takePhoto : _toggleVideo,
    child: Container(
      width: 80, height: 80,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
      child: Center(
        child: Container(
          width: 65, height: 65,
          decoration: BoxDecoration(color: _isRecording ? Colors.red : Colors.white, shape: BoxShape.circle),
          child: Icon(_mode == 'FOTO' ? Icons.camera_alt : (_isRecording ? Icons.stop : Icons.videocam), color: Colors.black),
        ),
      ),
    ),
  );

  // --- LOGIKA FOTO ---
  Future<void> _takePhoto() async {
    setState(() => _isProcessing = true);
    try {
      final photo = await _controller!.takePicture();
      final bytes = await File(photo.path).readAsBytes();
      img.Image? original = img.decodeImage(bytes);
      if (original != null) {
        img.Image resized = img.copyResize(original, width: _selectedRes.width.toInt(), height: _selectedRes.height.toInt(), interpolation: img.Interpolation.nearest);
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/NOKIA_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(path).writeAsBytes(img.encodeJpg(resized, quality: 40));
        await Gal.putImage(path);
        _showMsg("Foto Nokia Tersimpan!");
      }
    } catch (e) { _showMsg("Gagal Simpan Foto"); }
    finally { setState(() => _isProcessing = false); }
  }

  // --- LOGIKA VIDEO DENGAN FFMPEG NEW (PIXELATED RENDER) ---
  Future<void> _toggleVideo() async {
    if (_isRecording) {
      try {
        final recorded = await _controller!.stopVideoRecording();
        setState(() {
          _isRecording = false;
          _isProcessing = true;
        });

        // 1. Path Input & Output
        final String inputPath = recorded.path;
        final dir = await getApplicationDocumentsDirectory();
        final String outputPath = '${dir.path}/BURIK_VID_${DateTime.now().millisecondsSinceEpoch}.mp4';

        // 2. FFMPEG COMMAND
        // flags=neighbor: Kunci agar video pixelated/kotak-kotak (tidak smooth)
        // fps=15: Membuat video agak patah-patah ala HP jadul
        final String ffmpegCommand = 
          "-y -i $inputPath -vf \"scale=${_selectedRes.width}:${_selectedRes.height}:flags=neighbor,fps=15\" -c:v libx264 -preset ultrafast -crf 28 -c:a aac $outputPath";

        // 3. Eksekusi FFmpeg
        await FFmpegKit.execute(ffmpegCommand).then((session) async {
          final returnCode = await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            // 4. Simpan hasil render burik ke galeri
            await Gal.putVideo(outputPath);
            _showMsg("Video Burik Nokia Tersimpan!");
          } else {
            _showMsg("Gagal Render Video Burik");
          }
          
          // Bersihkan cache
          if (await File(outputPath).exists()) await File(outputPath).delete();
        });

      } catch (e) {
        _showMsg("Error FFmpeg: $e");
      } finally {
        setState(() => _isProcessing = false);
      }
    } else {
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }
}