import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';




const padding = 20.0;

const List<double> aspectRatios = [3/4, 4/5];
const List<String> aspectRatiosText = ["4:3","5:4"];
int aspectRatios_index = 0;
String customFolderPath = "/storage/emulated/0/DCIM/PixelChickCam";

Uint8List? _previewImageBytes;
bool _showPreview = false;
String filePath = "";
String savePath = "";
String fileName = "img";

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras(); // 取得可用相機清單
  print(cameras);
  runApp(const App());
}

class setColorScheme {
  static const background = Colors.black;
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PixelChickCam',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(title: 'Pixel ChickCam'),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _counter = 0;

  late CameraController _cameraController;
  bool _isCameraInitialized = false;

  void initState() {
    super.initState();
    _initializeApp(); // 用 async function 包起來
  }
  Future<void> _initializeApp() async {
    await _loadSavedFolderPath(); // 等待記憶載入完
    await _initCamera();          // 再啟動相機
    if (mounted) setState(() {}); // 重新繪製畫面
  }

  // ✅ 載入記憶的資料夾路徑
  Future<void> _loadSavedFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('customFolderPath');
    if (savedPath != null && savedPath.isNotEmpty) {
      setState(() {
        customFolderPath = savedPath;
      });
    }
  }

  // ✅ 選擇資料夾 + 記憶
  Future<void> _pickFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        customFolderPath = selectedDirectory;
      });

      // ✅ 儲存至 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('customFolderPath', selectedDirectory);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📂 已選擇資料夾：$selectedDirectory')),
      );
    } else {
      debugPrint("❌ 使用者未選擇資料夾");
    }
  }



  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController.initialize();
    setState(() {
      _isCameraInitialized = true;
    });
  }

  // 📸 一、拍照函式：只負責拍照與裁切，回傳裁切後的 bytes
  Future<Uint8List?> _captureAndCropImage() async {
    if (!_cameraController.value.isInitialized) return null;

    await Permission.camera.request();

    try {
      // 1️⃣ 拍照
      final XFile file = await _cameraController.takePicture();

      // 2️⃣ 讀取原圖 bytes
      final bytes = await File(file.path).readAsBytes();
      final ui.Image original = await decodeImageFromList(bytes);

      // 3️⃣ 設定裁切比例
      final double targetAspect = aspectRatios[aspectRatios_index];
      double srcW = original.width.toDouble();
      double srcH = original.height.toDouble();

      double newW = srcW;
      double newH = srcW / targetAspect;
      if (newH > srcH) {
        newH = srcH;
        newW = srcH * targetAspect;
      }

      final left = (srcW - newW) / 2;
      final top = (srcH - newH) / 2;

      // 4️⃣ 建立畫布裁切並水平翻轉
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint();
      // canvas.translate(newW, 0);
      // canvas.scale(-1, 1);
      canvas.drawImageRect(
        original,
        Rect.fromLTWH(left, top, newW, newH),
        Rect.fromLTWH(0, 0, newW, newH),
        paint,
      );

      final picture = recorder.endRecording();
      final img = await picture.toImage(newW.toInt(), newH.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("拍照錯誤：$e");
      return null;
    }
  }

// 💾 二、儲存函式：負責把 bytes 寫入指定資料夾
  Future<String?> _saveImage(Uint8List bytes) async {
    await Permission.storage.request();
    await Permission.photos.request();

    try {

      await Directory(savePath).create(recursive: true);

      if(filePath.split('.').last == "png"){
        filePath = filePath.replaceAll(".png.png", ".png");
      }

      await File(filePath).writeAsBytes(bytes);

      return filePath;
    } catch (e) {
      debugPrint("儲存圖片錯誤：$e");
      return null;
    }
  }

  // 📸 三、整合：按下拍照按鈕執行
  Future<void> _onCapturePressed() async {
    final croppedBytes = await _captureAndCropImage();
    if (croppedBytes == null) return;

    savePath = customFolderPath ?? "/storage/emulated/0/DCIM/PixelChickCam";
    filePath = "$savePath/${DateTime.now().millisecondsSinceEpoch}.png";

    setState(() {
      _previewImageBytes = croppedBytes;
      _showPreview = true; // 顯示預覽畫面
    });
  }

  void _showNotReadyDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text('提示', style: TextStyle(color: Colors.white)),
          content: const Text('這個還沒用，不要點 🙈', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了', style: TextStyle(color: Colors.lightBlue)),
            ),
          ],
        );
      },
    );
  }


  Widget _buildPreviewScreen(double screenWidth, double screenHeight) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ✅ 預覽圖片
        SizedBox(height: padding / 2),
        Container(
          width: screenWidth * 0.9,
          height: screenWidth * 0.9 * 1 / aspectRatios[aspectRatios_index],
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            color: Colors.black,
          ),
          clipBehavior: Clip.hardEdge,
          child: _previewImageBytes != null
              ? Image.memory(_previewImageBytes!, fit: BoxFit.contain)
              : const SizedBox(),
        ),
        SizedBox(
          height: (screenHeight -
              (screenWidth * 0.9 * 4 / 3) -
              AppBar().preferredSize.height) /
              8,
        ),
        //filename
        RenameBox(
          filePath: filePath,
          onNameChanged: (newName) {
            setState(() {
              fileName = newName;
              filePath = "$savePath/$newName.png"; // ✅ 同步全域
            });
          },
        ),

        SizedBox(
          height: padding * 1.5,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _showPreview = false;
                  _previewImageBytes = null;
                });
              },
              icon: const Icon(Icons.refresh, color: Colors.white),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800],
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              onPressed: () async {
                if (_previewImageBytes == null) return;
                final filePath = await _saveImage(_previewImageBytes!);
                if (filePath != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ 已儲存裁切圖片：$filePath')),
                  );
                  setState(() {
                    _showPreview = false;
                    _previewImageBytes = null;
                  });
                }
              },
              icon: const Icon(Icons.check, color: Colors.white),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
              ),
            ),
          ],
        ),
      ],
    );
  }





  @override
  Widget build(BuildContext context) {

    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: setColorScheme.background,
        centerTitle: true,
        title: Center(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              InkWell(
                onTap: _pickFolder,
                child: Container(
                  width: 160,
                  height: 35,
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white24,
                  ),
                  child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.folder_open_outlined,
                            color: Colors.white54,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            (customFolderPath.length > 10)
                                ? '...${customFolderPath.substring(customFolderPath.length - 10)}'
                                : customFolderPath,
                            style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white54,
                                fontWeight: FontWeight.w600
                            ),
                          ),
                        ],
                      )

                  ),
                ),
              ),
              SizedBox(
                width: padding,
              ),
              InkWell(
                onTap: (){
                  _showNotReadyDialog();
                },
                child: Container(
                  width: 35,
                  height: 35,
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white24,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.settings,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      backgroundColor: setColorScheme.background,
      body: Center(
        child: _showPreview
            ? _buildPreviewScreen(screenWidth, screenHeight)
            : Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(height: padding / 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: screenWidth * 0.9,
              height: screenWidth * 0.9 * 1 / aspectRatios[aspectRatios_index],
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(25),
              ),
              clipBehavior: Clip.hardEdge,
              child: CameraContainer(
                controller: _cameraController,
                screenWidth: screenWidth,
              ),
            ),
            SizedBox(
              height: (screenHeight -
                  (screenWidth * 0.9 * 4 / 3) -
                  AppBar().preferredSize.height) /
                  8,
            ),
            Container(
              width: screenWidth * 0.9,
              child: Column(
                children: [
                  // 原本 scale / zoom UI
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            aspectRatios_index =
                                (aspectRatios_index + 1) % aspectRatios.length;
                          });
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("scale",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 18)),
                            Text(
                              "${aspectRatiosText[aspectRatios_index]}",
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20),
                            ),
                          ],
                        ),
                      ),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("zoom",
                              style: TextStyle(
                                  color: Colors.white, fontSize: 18)),
                          Text("1x",
                              style: TextStyle(
                                  color: Colors.white, fontSize: 20)),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: padding * 1.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: _onCapturePressed,
                        child: Container(
                          width: 75,
                          height: 75,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey,
                              width: 6,
                            ),
                          ),
                        ),
                      )
                    ],
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


class CameraContainer extends StatelessWidget {
  final CameraController controller;
  final double screenWidth;

  const CameraContainer({
    super.key,
    required this.controller,
    required this.screenWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final previewSize = controller.value.previewSize!;
    final previewAspectRatio = previewSize.height / previewSize.width;

    final targetAspect = aspectRatios[aspectRatios_index];
    final targetHeight = screenWidth * 1 / targetAspect;

    return Container(
      width: screenWidth,
      height: targetHeight,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
      ),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}


class RenameBox extends StatefulWidget {
  const RenameBox({
    super.key,
    required this.filePath,
    required this.onNameChanged,
  });

  final String filePath;
  final Function(String newFileName) onNameChanged;

  @override
  State<RenameBox> createState() => _RenameBoxState();
}

class _RenameBoxState extends State<RenameBox>
    with SingleTickerProviderStateMixin {
  late String fileName;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  // 三個輸入欄位控制器
  final TextEditingController _classController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fileName = widget.filePath.split('/').last;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      lowerBound: 0.95,
      upperBound: 1.0,
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _controller.reverse();
    });

    _scaleAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _controller.dispose();
    _classController.dispose();
    _numberController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _renameFileDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text('設定檔案名稱', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _classController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '班級',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '座號',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '姓名',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                final c = _classController.text.trim();
                final n = _numberController.text.trim();
                final name = _nameController.text.trim();


                // if (c.isNotEmpty && n.isNotEmpty && name.isNotEmpty) {
                //   final newName = "${c}_${n}_$name";
                //   setState(() {
                //     fileName = newName;
                //   });
                //   widget.onNameChanged(newName);
                // } else {
                //   ScaffoldMessenger.of(context).showSnackBar(
                //     const SnackBar(content: Text('⚠️ 請填寫完整三個欄位')),
                //   );
                // }

                final newName = "${c}_${n}_$name";
                setState(() {
                  fileName = newName;
                });
                widget.onNameChanged(newName);

                Navigator.pop(ctx);
              },
              child: const Text('確定', style: TextStyle(color: Colors.lightBlue)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: InkWell(
        onTap: () async {
          _controller.forward();
          await _renameFileDialog();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: Colors.white24,
          ),
          child: Text(
            fileName,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
