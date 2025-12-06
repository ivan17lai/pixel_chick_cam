import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

const padding = 20.0;

// 1. 修改全域變數：新增自訂比例的預設值
// 預設比例：4:3, 5:4, 1:1 (自訂預設)
List<double> aspectRatios = [3/4, 4/5, 1.0];
List<String> aspectRatiosText = ["4:3","5:4", "1:1"];
int aspectRatios_index = 1;
String customFolderPath = "/storage/emulated/0/DCIM/PixelChickCam";
// 新增一個全域變數來儲存自訂比例的字串，用於顯示和載入
String customRatioString = "1:1";
bool autoRenameEnabled = false; // 新增開關的全域變數


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

  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  final GlobalKey<_RenameBoxState> _renameBoxKey = GlobalKey<_RenameBoxState>();

  @override
  void initState() {
    super.initState();
    _initializeApp(); // 用 async function 包起來
  }

  // 1.1. 修改 _initializeApp() 以載入自訂比例
  Future<void> _initializeApp() async {
    await _loadSavedFolderPath(); // 等待記憶載入完
    await _loadCustomRatio();     // 載入自訂比例
    await _initCamera();          // 再啟動相機
    if (mounted) setState(() {}); // 重新繪製畫面
    await _loadAutoRenameSetting(); // 新增這行

  }

  Future<void> _loadAutoRenameSetting() async {
    final prefs = await SharedPreferences.getInstance();
    autoRenameEnabled = prefs.getBool('autoRename') ?? false;
  }

  // 載入記憶的資料夾路徑
  Future<void> _loadSavedFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('customFolderPath');
    if (savedPath != null && savedPath.isNotEmpty) {
      setState(() {
        customFolderPath = savedPath;
      });
    }
  }

  // 2. 新增：載入自訂比例的函式
  Future<void> _loadCustomRatio() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRatioString = prefs.getString('customRatio'); // e.g. "16:9"

    if (savedRatioString != null && savedRatioString.isNotEmpty) {
      customRatioString = savedRatioString;

      final parts = customRatioString.split(':');
      if (parts.length == 2) {
        final w = double.tryParse(parts[0]);
        final h = double.tryParse(parts[1]);
        if (w != null && h != null && w > 0 && h > 0) {
          final newRatio = h / w; // Flutter 的比例是 height / width

          // 替換全域變數中的自訂比例 (第三個)
          aspectRatios[2] = newRatio;
          aspectRatiosText[2] = customRatioString;
        }
      }
      if (mounted) setState(() {});
    }
  }


  // 選擇資料夾 + 記憶
  Future<void> _pickFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        customFolderPath = selectedDirectory;
      });

      // 儲存至 SharedPreferences
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

  // 一、拍照函式：只負責拍照與裁切，回傳裁切後的 bytes
  Future<Uint8List?> _captureAndCropImage() async {
    if (!_cameraController.value.isInitialized) return null;

    await Permission.camera.request();

    try {
      // 1拍照
      final XFile file = await _cameraController.takePicture();

      // 讀取原圖 bytes
      final bytes = await File(file.path).readAsBytes();
      final ui.Image original = await decodeImageFromList(bytes);

      // ️設定裁切比例
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

      // 4建立畫布裁切並水平翻轉
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

// 二、儲存函式：負責把 bytes 寫入指定資料夾
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
  Future<void> _showRenameDialog(BuildContext context) async {
    final TextEditingController c1 = TextEditingController();
    final TextEditingController c2 = TextEditingController();
    final TextEditingController c3 = TextEditingController();

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
                controller: c1,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '欄位1',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: c2,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '欄位2',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: c3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '欄位3',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
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
                final c = c1.text.trim();
                final n = c2.text.trim();
                final name = c3.text.trim();
                final newName = "${c}_${n}_$name"
                    .replaceAll(RegExp(r'_+'), '_')
                    .replaceAll(RegExp(r'^_|_$'), '');
                final finalName = newName.isEmpty
                    ? DateTime.now().millisecondsSinceEpoch.toString()
                    : newName;

                setState(() {
                  fileName = finalName;
                  filePath = "$savePath/$finalName.png";
                });

                //通知 RenameBox 更新顯示文字
                _renameBoxKey.currentState?.setState(() {
                  _renameBoxKey.currentState!.fileName = finalName;
                });

                Navigator.pop(ctx);
              },
              child: const Text('確定', style: TextStyle(color: Colors.lightBlue)),
            ),


          ],
        );
      },
    );
  }

// 📸 三、整合：按下拍照按鈕執行
  Future<void> _onCapturePressed() async {
    final croppedBytes = await _captureAndCropImage();
    if (croppedBytes == null) return;

    savePath = customFolderPath;
    filePath = "$savePath/${DateTime.now().millisecondsSinceEpoch}.png";

    setState(() {
      _previewImageBytes = croppedBytes;
      _showPreview = true;
    });

  }



  // 3. 移除 _showNotReadyDialog 並改為導航到設定頁面
  void _openSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(currentRatio: customRatioString),
      ),
    );

    // 接收來自設定頁面的結果
    if (result != null && result is String) {
      await _saveAndApplyCustomRatio(result);
    }
  }

  // 4. 新增：儲存並應用自訂比例的函式
  Future<void> _saveAndApplyCustomRatio(String ratioString) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customRatio', ratioString);

    // 重新載入比例並更新畫面
    await _loadCustomRatio();
    if (mounted) {
      setState(() {
        // 確保如果當前選中是自訂比例，介面能正確更新
        if (aspectRatios_index == aspectRatios.length - 1) {
          // 如果當前是自訂比例，則強制重建 CameraContainer
          _cameraController.value.aspectRatio; // 觸發 State 改變
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 已儲存新的自訂比例：$ratioString')),
      );
    }
  }


  Widget _buildPreviewScreen(double screenWidth, double screenHeight) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        //預覽圖片
        SizedBox(height: padding / 2),
        Container(
          width: screenWidth * 0.9,
          // 注意：此處要用 aspectRatios[aspectRatios_index]，因為它可能不是 4/3
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
              // 注意：這裡的減法也必須使用當前的比例
              (screenWidth * 0.9 * 1 / aspectRatios[aspectRatios_index]) -
              AppBar().preferredSize.height) /
              8,
        ),
        //filename
        RenameBox(
          key: _renameBoxKey, // ✅ 加上 key
          filePath: filePath,
          onNameChanged: (newName) {
            setState(() {
              fileName = newName;
              filePath = "$savePath/$newName.png";
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
                //若開啟自動命名功能，就直接呼叫命名對話框
                if (autoRenameEnabled && mounted) {
                  await Future.delayed(const Duration(milliseconds: 200));
                  await _showRenameDialog(context);
                }
                if (_previewImageBytes == null) return;
                // 注意：這裡的 fileName 應使用全域變數 fileName
                final savePath = customFolderPath ?? "/storage/emulated/0/DCIM/PixelChickCam";
                filePath = "$savePath/$fileName.png";

                final resultPath = await _saveImage(_previewImageBytes!);
                if (resultPath != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✅ 已儲存裁切圖片：$resultPath')),
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
                // 5. 修改：設定按鈕導航到設定頁面
                onTap: _openSettings,
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
              // 注意：這裡的 height 必須使用當前選中的比例
              height: screenWidth * 0.9 * 1 / aspectRatios[aspectRatios_index],
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(25),
              ),
              clipBehavior: Clip.hardEdge,
              child: CameraContainer(
                controller: _cameraController,
                screenWidth: screenWidth,
                // 6. 傳遞當前選中的比例
                aspectRatio: aspectRatios[aspectRatios_index],
              ),
            ),
            SizedBox(
              height: (screenHeight -
                  // 注意：這裡的減法也必須使用當前的比例
                  (screenWidth * 0.9 * 1 / aspectRatios[aspectRatios_index]) -
                  AppBar().preferredSize.height) /
                  8,
            ),
            Container(
              width: screenWidth * 0.9,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      InkWell(
                        // 7. 修改：切換比例的邏輯 (增加到三個選項)
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
                              // 8. 顯示當前比例的文字
                              aspectRatiosText[aspectRatios_index],
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

// 9. 修改 CameraContainer：接受並使用傳入的 aspectRatio
class CameraContainer extends StatelessWidget {
  final CameraController controller;
  final double screenWidth;
  final double aspectRatio; // 新增：傳入的目標比例

  const CameraContainer({
    super.key,
    required this.controller,
    required this.screenWidth,
    required this.aspectRatio, // 必須的參數
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final previewSize = controller.value.previewSize!;
    // final previewAspectRatio = previewSize.height / previewSize.width;

    // final targetAspect = aspectRatios[aspectRatios_index]; // 從參數獲取
    final targetHeight = screenWidth * 1 / aspectRatio;

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
    //  修正：在 initState 中從 filePath 解析 fileName
    // 預設的 filePath 結尾會是 millisecondsSinceEpoch.png，但顯示的應是 img
    // 在 _onCapturePressed 之後，這裡應該取得正確的預設檔名
    final pathParts = widget.filePath.split('/');
    String tempFileName = pathParts.last;
    if (tempFileName.endsWith(".png")) {
      tempFileName = tempFileName.substring(0, tempFileName.length - 4);
    }
    fileName = tempFileName;

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
                  labelText: '欄位1',
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
                  labelText: '欄位2',
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
                  labelText: '欄位3',
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

                // 修正：如果三個欄位都空，則不更新檔名，維持時間戳
                if (c.isEmpty && n.isEmpty && name.isEmpty) {
                  Navigator.pop(ctx);
                  return;
                }

                // 修正：即使部分欄位為空，也使用下劃線連接
                final newName = "${c}_${n}_$name";

                // 移除連續的下劃線，並移除開頭和結尾的下劃線
                final cleanName = newName.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');

                // 如果清理後為空，則使用時間戳
                final finalName = cleanName.isEmpty ?
                DateTime.now().millisecondsSinceEpoch.toString() : cleanName;

                setState(() {
                  fileName = finalName;
                });
                widget.onNameChanged(finalName);

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
            (fileName.length == 13 && int.tryParse(fileName) != null) ? "img" : fileName,
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

// ====================================================================
// 10. 新增：設定頁面 (SettingsPage)
// ====================================================================
class SettingsPage extends StatefulWidget {
  final String currentRatio;

  const SettingsPage({super.key, required this.currentRatio});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _widthController;
  late TextEditingController _heightController;

  String _errorText = '';

  @override
  void initState() {
    super.initState();
    // 將 currentRatio (e.g., "16:9") 分割並設定給控制器
    final parts = widget.currentRatio.split(':');
    final initialW = parts.length == 2 ? parts[0] : '1';
    final initialH = parts.length == 2 ? parts[1] : '1';

    _widthController = TextEditingController(text: initialW);
    _heightController = TextEditingController(text: initialH);
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final wStr = _widthController.text.trim();
    final hStr = _heightController.text.trim();

    final w = int.tryParse(wStr);
    final h = int.tryParse(hStr);

    if (w == null || h == null || w <= 0 || h <= 0) {
      setState(() {
        _errorText = '寬度和高度必須為大於零的整數。';
      });
      return;
    }

    // 檢查最大值 (避免用戶輸入極大的數字導致計算錯誤或溢位)
    if (w > 1000 || h > 1000) {
      setState(() {
        _errorText = '輸入值不應大於 1000。';
      });
      return;
    }

    setState(() {
      _errorText = '';
    });

    final newRatioString = '$wStr:$hStr';
    // 返回到 HomePage 並傳遞新的比例字串
    Navigator.pop(context, newRatioString);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: setColorScheme.background,
        iconTheme: const IconThemeData(color: Colors.white54),
      ),
      backgroundColor: setColorScheme.background,
      body: Padding(
        padding: const EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('每次拍攝後自動詢問檔案名稱', style: TextStyle(color: Colors.white)),
              value: autoRenameEnabled,
              activeColor: Colors.lightBlue,
              onChanged: (value) async {
                setState(() {
                  autoRenameEnabled = value;
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('autoRename', value);
              },
            ),
            const SizedBox(height: 30),

            const Text(
              '自訂裁切比例 (寬:高)',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '高 (H)',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.lightBlue),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(':', style: TextStyle(color: Colors.white, fontSize: 24)),
                ),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: '寬 (W)',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.lightBlue),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_errorText.isNotEmpty)
              Text(
                _errorText,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 30),
            Center(
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                ),
                child: const Text(
                  '儲存比例',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ℹ比例格式為 寬:高，例如 16:9 (橫式) 或 9:16 (直式)。',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}