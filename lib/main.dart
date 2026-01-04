import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img; 
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';

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
    _controller = CameraController(widget.cameras[_camIdx], ResolutionPreset.low);
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Viewfinder
          Positioned.fill(child: CameraPreview(_controller!)),
          
          // Top Bar: Resolusi
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

          // Bottom UI (Android Camera Style)
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
                        icon: const Icon(Icons.flip_camera_android),
                        onPressed: () { _camIdx = _camIdx == 0 ? 1 : 0; _initCam(); },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing) const Center(child: CircularProgressIndicator(color: Colors.green)),
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

  // --- LOGIKA VIDEO (FIXED: COPY FILE METHOD) ---
  Future<void> _toggleVideo() async {
    if (_isRecording) {
      try {
        final recorded = await _controller!.stopVideoRecording();
        setState(() {
          _isRecording = false;
          _isProcessing = true;
        });

        // 1. Delay singkat agar kamera melepas resource
        await Future.delayed(const Duration(milliseconds: 800));

        // 2. COPY file ke lokasi AMAN (Application Documents)
        final dir = await getApplicationDocumentsDirectory();
        final safePath = '${dir.path}/NOKIA_VIDEO_${DateTime.now().millisecondsSinceEpoch}.mp4';

        final safeFile = await File(recorded.path).copy(safePath);

        // 3. SIMPAN KE GALERI dari file yang sudah di-copy
        await Gal.putVideo(safeFile.path);

        _showMsg("Video Nokia Tersimpan!");
        
        // Bersihkan file sementara setelah berhasil disimpan ke galeri
        await File(safeFile.path).delete();
      } catch (e) {
        _showMsg("Gagal simpan video: $e");
      } finally {
        setState(() => _isProcessing = false);
      }
    } else {
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }
}