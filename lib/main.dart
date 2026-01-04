import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img; 
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';

// Import FFmpeg Kit New
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

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

class _NokiaAndroidCameraState extends State<NokiaAndroidCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isProcessing = false;
  String _mode = 'FOTO'; 
  int _camIdx = 0;
  Size _selectedRes = const Size(320, 240);
  
  // Variabel untuk Timer Video
  Timer? _timer;
  int _recordDuration = 0; // dalam detik

  String? _lastMediaPath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCam();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // Format detik ke 00:00
  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$remainingSeconds";
  }

  Future<void> _initCam() async {
    await [Permission.camera, Permission.microphone, Permission.photos, Permission.videos].request();
    if (_controller != null) await _controller!.dispose();
    
    CameraDescription selectedCamera = widget.cameras[0];
    for(var cam in widget.cameras) {
      if(_camIdx == 0 && cam.lensDirection == CameraLensDirection.back) {
        selectedCamera = cam; break;
      }
      if(_camIdx == 1 && cam.lensDirection == CameraLensDirection.front) {
        selectedCamera = cam; break;
      }
    }

    _controller = CameraController(
      selectedCamera, 
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (mounted) setState(() {});
    } catch (e) { _showMsg("Kamera Error: $e"); }
  }

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _openGallery() async {
    final XFile? file = await _picker.pickMedia(); 
    if (file != null) debugPrint("Media dibuka: ${file.path}");
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.green)));
    }

    return RotatedBox(
      quarterTurns: MediaQuery.of(context).orientation == Orientation.landscape ? 1 : 0,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Viewfinder (Preview) - FIX MIRROR
            Positioned.fill(
              child: Center(
                child: CameraPreview(
                  _controller!,
                  child: LayoutBuilder(builder: (context, constraints) {
                    bool isFrontCam = _controller!.description.lensDirection == CameraLensDirection.front;
                    return Transform.scale(
                      scaleX: isFrontCam ? -1.0 : 1.0,
                      alignment: Alignment.center,
                      child: const SizedBox(),
                    );
                  }),
                ),
              ),
            ),

            // 2. Timer Overlay (Hanya muncul saat rekam)
            if (_isRecording)
              Positioned(
                top: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, color: Colors.red, size: 12),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(_recordDuration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 3. UI Overlay
            _buildUIOverlay(),
            
            if (_isProcessing) 
              Container(
                color: Colors.black87,
                child: const Center(child: CircularProgressIndicator(color: Colors.green)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUIOverlay() {
    return Column(
      children: [
        // Top Bar (Resolusi)
        Padding(
          padding: const EdgeInsets.only(top: 50),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _resChip("120p", const Size(160, 120)),
              _resChip("240p", const Size(320, 240)),
            ],
          ),
        ),
        const Spacer(),
        // Bottom Bar (Kontrol)
        Container(
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildGalleryThumbnail(),
                  _shutterBtn(),
                  IconButton(
                    icon: Icon(Icons.flip_camera_android, 
                          color: (_isRecording || _isProcessing) ? Colors.grey : Colors.green, 
                          size: 30),
                    onPressed: (_isRecording || _isProcessing) 
                        ? null 
                        : () { 
                            _camIdx = (_camIdx + 1) % 2; 
                            _initCam(); 
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryThumbnail() {
    return GestureDetector(
      onTap: _openGallery,
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: _lastMediaPath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _lastMediaPath!.endsWith('.jpg') 
                    ? Image.file(File(_lastMediaPath!), fit: BoxFit.cover)
                    : const Center(child: Icon(Icons.videocam, color: Colors.white, size: 30)),
              )
            : const Icon(Icons.photo_library, color: Colors.white),
      ),
    );
  }

  Widget _resChip(String label, Size size) {
    bool isSel = _selectedRes == size;
    return GestureDetector(
      onTap: () => setState(() => _selectedRes = size),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? Colors.green : Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _modeTab(String m) => GestureDetector(
    onTap: () => setState(() => _mode = m),
    child: Text(m, style: TextStyle(color: _mode == m ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
  );

  Widget _shutterBtn() => GestureDetector(
    onTap: _mode == 'FOTO' ? _takePhoto : _toggleVideo,
    child: Container(
      width: 80, height: 80,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
      child: Center(
        child: Container(
          width: 65, height: 65,
          decoration: BoxDecoration(color: (_isRecording || _isProcessing) ? Colors.red : Colors.white, shape: BoxShape.circle),
          child: Icon(_mode == 'FOTO' ? Icons.camera_alt : (_isRecording ? Icons.stop : Icons.videocam), color: Colors.black),
        ),
      ),
    ),
  );

  // --- LOGIKA FOTO ---
  Future<void> _takePhoto() async {
    if(_isProcessing) return;
    setState(() => _isProcessing = true);
    bool isFrontCam = _controller!.description.lensDirection == CameraLensDirection.front;
    try {
      final photo = await _controller!.takePicture();
      final bytes = await File(photo.path).readAsBytes();
      img.Image? original = img.decodeImage(bytes);
      if (original != null) {
        original = img.bakeOrientation(original);
        if (isFrontCam) original = img.flipHorizontal(original);
        img.Image resized = img.copyResize(original, width: _selectedRes.width.toInt(), height: _selectedRes.height.toInt(), interpolation: img.Interpolation.nearest);
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/NOKIA_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(path).writeAsBytes(img.encodeJpg(resized, quality: 90));
        await Gal.putImage(path);
        _showMsg("Foto Tersimpan!");
        setState(() { _lastMediaPath = path; }); 
      }
    } catch (e) { _showMsg("Gagal Foto: $e"); }
    finally { setState(() => _isProcessing = false); }
  }

  // --- LOGIKA VIDEO (DENGAN TIMER) ---
  Future<void> _toggleVideo() async {
    if (_isProcessing) return;

    if (_isRecording) {
      // STOP
      try {
        _timer?.cancel(); // Stop timer
        setState(() => _isProcessing = true);
        final recorded = await _controller!.stopVideoRecording();
        setState(() { 
          _isRecording = false; 
          _recordDuration = 0; // Reset durasi
        });

        final String inputPath = recorded.path;
        final dir = await getApplicationDocumentsDirectory();
        final String outputPath = '${dir.path}/VID_${DateTime.now().millisecondsSinceEpoch}.mp4';
        bool isFrontCam = _controller!.description.lensDirection == CameraLensDirection.front;
        
        String videoFilter = "scale=${_selectedRes.width}:${_selectedRes.height}:flags=neighbor,fps=15";
        if (isFrontCam) videoFilter = "hflip,$videoFilter";

        final String ffmpegCommand = "-y -i $inputPath -vf \"$videoFilter\" -c:v libx264 -preset ultrafast -crf 28 -c:a aac $outputPath";

        await FFmpegKit.execute(ffmpegCommand).then((session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            await Gal.putVideo(outputPath);
            _showMsg("Video Burik Tersimpan!");
            setState(() { _lastMediaPath = outputPath; });
          }
          if (await File(inputPath).exists()) await File(inputPath).delete();
          if (await File(outputPath).exists()) await File(outputPath).delete();
        });
      } catch (e) { _showMsg("Error: $e"); }
      finally { setState(() => _isProcessing = false); }
    } else {
      // START
      try {
        await _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
          _recordDuration = 0; // Mulai dari nol
        });
        // Jalankan Timer tiap 1 detik
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordDuration++;
          });
        });
      } catch (e) { _showMsg("Gagal mulai rekam"); }
    }
  }
}