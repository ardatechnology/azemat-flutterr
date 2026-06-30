// Video Looper — موزه شهر شیراز
// نسخه اندروید · همان دیزاین موزه‌ای · خواندن خودکار از پوشه مشخص
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ── رنگ‌های موزه‌ای (دقیقاً مطابق نسخه دسکتاپ) ──
const cBG    = Color(0xFFf5f0e8);
const cBG2   = Color(0xFFede6d6);
const cINK   = Color(0xFF1a1610);
const cINK2  = Color(0xFF3d3628);
const cINK3  = Color(0xFF7a6e58);
const cGOLD  = Color(0xFF8a6d20);
const cGOLD2 = Color(0xFFb8962e);
const cGOLDL = Color(0xFFf0dfa0);
const cCARD  = Color(0xFFfffcf5);
const cLINE  = Color(0xFFd4c49a);
const cVBG   = Color(0xFF0a0804);

// ── رمز ورود به حالت خروج (همینجا تغییر دهید) ──
const String adminPassword = "123";

// ── نام پوشه‌ای که ویدیوها از آن خوانده می‌شوند ──
// مسیر کامل: /storage/emulated/0/MuseumVideos
const String videoFolderName = "MuseumVideos";

const Set<String> videoExtensions = {
  '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts'
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MuseumApp());
}

class MuseumApp extends StatelessWidget {
  const MuseumApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'موزه شهر شیراز',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Vazirmatn',
        scaffoldBackgroundColor: cVBG,
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: const VideoLooperScreen(),
      ),
    );
  }
}

class VideoLooperScreen extends StatefulWidget {
  const VideoLooperScreen({super.key});
  @override
  State<VideoLooperScreen> createState() => _VideoLooperScreenState();
}

class _VideoLooperScreenState extends State<VideoLooperScreen> {
  VideoPlayerController? _controller;
  List<String> _playlist = [];
  int _currentIndex = -1;
  int _loopCount = 0;
  bool _panelVisible = false;
  bool _isPlaying = false;
  String _status = "آماده";
  Color _statusColor = cGOLD;
  String _folderPath = "";

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _init();
  }

  Future<void> _init() async {
    await _ensurePermission();
    await _resolveFolder();
    await _scanFolder();
    if (_playlist.isNotEmpty) {
      _playIndex(0);
    }
  }

  Future<void> _ensurePermission() async {
    // اندروید ۱۳+ از مجوزهای ویدیویی استفاده می‌کند، نسخه‌های قدیمی‌تر storage
    if (await Permission.videos.isGranted ||
        await Permission.storage.isGranted) {
      return;
    }
    await Permission.videos.request();
    await Permission.storage.request();
    // برای دسترسی کامل به همه فایل‌ها (اندروید ۱۱+)
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  Future<void> _resolveFolder() async {
    // مسیر استاندارد حافظه داخلی اندروید
    final candidates = [
      "/storage/emulated/0/$videoFolderName",
      "/sdcard/$videoFolderName",
    ];
    for (final c in candidates) {
      final dir = Directory(c);
      if (await dir.exists()) {
        _folderPath = c;
        return;
      }
    }
    // اگر پوشه نبود، بسازش
    try {
      final dir = Directory(candidates.first);
      await dir.create(recursive: true);
      _folderPath = candidates.first;
    } catch (_) {
      _folderPath = candidates.first;
    }
  }

  Future<void> _scanFolder() async {
    final found = <String>[];
    try {
      final dir = Directory(_folderPath);
      if (await dir.exists()) {
        final entries = dir.listSync();
        for (final e in entries) {
          if (e is File) {
            final lower = e.path.toLowerCase();
            if (videoExtensions.any((ext) => lower.endsWith(ext))) {
              found.add(e.path);
            }
          }
        }
        found.sort(); // ترتیب الفبایی
      }
    } catch (_) {}
    setState(() => _playlist = found);
  }

  Future<void> _playIndex(int idx) async {
    if (_playlist.isEmpty) return;
    idx = idx % _playlist.length;
    _currentIndex = idx;
    _loopCount = 1;
    _advancing = false;

    await _controller?.dispose();
    final ctrl = VideoPlayerController.file(File(_playlist[idx]));
    _controller = ctrl;
    try {
      await ctrl.initialize();
      await ctrl.setLooping(false);
      ctrl.addListener(_onTick);
      await ctrl.play();
      setState(() {
        _isPlaying = true;
        _status = "در حال پخش  ◉";
        _statusColor = const Color(0xFF2a7a2a);
      });
    } catch (_) {
      // فایل خراب → برو بعدی
      if (_playlist.length > 1) {
        _playIndex(idx + 1);
      }
    }
  }

  bool _advancing = false;

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur <= Duration.zero) return;

    final reachedEnd = !c.value.isPlaying &&
        pos >= dur - const Duration(milliseconds: 300);

    if (reachedEnd && !_advancing) {
      _advancing = true;
      if (_playlist.length > 1) {
        _playIndex((_currentIndex + 1) % _playlist.length);
      } else {
        // تک‌ویدیو: از ابتدا پخش کن (لوپ)
        c.seekTo(Duration.zero).then((_) {
          c.play();
          if (mounted) setState(() => _loopCount++);
          _advancing = false;
        });
      }
    } else if (!reachedEnd) {
      _advancing = false;
    }
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
      setState(() {
        _isPlaying = false;
        _status = "مکث  ‖";
        _statusColor = cGOLD;
      });
    } else {
      c.play();
      setState(() {
        _isPlaying = true;
        _status = "در حال پخش  ◉";
        _statusColor = const Color(0xFF2a7a2a);
      });
    }
  }

  void _playNext() {
    if (_playlist.length > 1) _playIndex((_currentIndex + 1) % _playlist.length);
  }

  void _playPrev() {
    if (_playlist.length > 1) {
      _playIndex((_currentIndex - 1 + _playlist.length) % _playlist.length);
    }
  }

  void _restart() {
    if (_currentIndex >= 0) {
      _loopCount = 1;
      _controller?.seekTo(Duration.zero);
      _controller?.play();
      setState(() {});
    }
  }

  void _stop() {
    _controller?.pause();
    _controller?.seekTo(Duration.zero);
    setState(() {
      _isPlaying = false;
      _status = "متوقف  ■";
      _statusColor = cINK3;
    });
  }

  // ── خروج با رمز ──
  void _requestExit() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _PasswordDialog(
          onSuccess: () {
            Navigator.pop(context);
            _confirmExit();
          },
        ),
      ),
    );
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: cCARD,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: cGOLD2),
          ),
          title: const Text("خروج از برنامه؟",
              style: TextStyle(color: cGOLD, fontWeight: FontWeight.bold, fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("انصراف", style: TextStyle(color: cINK2)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cGOLD),
              onPressed: () => SystemNavigator.pop(),
              child: const Text("خروج", style: TextStyle(color: cBG)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVBG,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Stack(
              children: [
                _buildVideoArea(),
                if (_panelVisible) _buildFloatingPanel(),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── هدر طلایی ──
  Widget _buildHeader() {
    return Container(
      color: cBG,
      child: Column(
        children: [
          Container(height: 3, color: cGOLD2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              children: [
                // راست: دکمه داشبورد
                Column(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _panelVisible = !_panelVisible),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: cBG2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text("داشبورد  ☰",
                            style: TextStyle(color: cGOLD, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
                // مرکز: عنوان
                Expanded(
                  child: Column(
                    children: [
                      const Text("Shiraz Baladieh Museum",
                          style: TextStyle(color: cINK3, fontSize: 9, fontFamily: 'monospace')),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(width: 40, height: 1, color: cGOLD2),
                          const SizedBox(width: 6),
                          const Text("◆", style: TextStyle(color: cGOLD2, fontSize: 7)),
                          const Text("◈", style: TextStyle(color: cGOLD2, fontSize: 10)),
                          const Text("◆", style: TextStyle(color: cGOLD2, fontSize: 7)),
                          const SizedBox(width: 6),
                          Container(width: 40, height: 1, color: cGOLD2),
                        ],
                      ),
                      const Text("پخش حلقه‌ای ویدیو",
                          style: TextStyle(color: cINK, fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text("نمایش مستمر · موزه شهر شیراز",
                          style: TextStyle(color: cINK3, fontSize: 9)),
                    ],
                  ),
                ),
                // چپ: وضعیت
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFf0e8d0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(_status,
                          style: TextStyle(color: _statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    if (_loopCount > 0)
                      Text("loop: $_loopCount",
                          style: const TextStyle(color: cINK3, fontSize: 8, fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: cGOLD2),
        ],
      ),
    );
  }

  // ── ناحیه ویدیو ──
  Widget _buildVideoArea() {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      return Container(
        color: cVBG,
        child: Center(
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),
      );
    }
    return Container(
      color: cVBG,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("◈", style: TextStyle(color: cGOLD2, fontSize: 40)),
            const SizedBox(height: 20),
            Text(
              _folderPath.isEmpty
                  ? "در حال آماده‌سازی..."
                  : "پلی‌لیستی موجود نیست\n\nویدیوها را در این پوشه قرار دهید:\n$videoFolderName\n\nسپس «بازخوانی پوشه» را بزنید",
              textAlign: TextAlign.center,
              style: const TextStyle(color: cGOLD2, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  // ── نوار پایین ──
  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 28,
        color: cVBG.withOpacity(0.85),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_loopCount > 0 ? "loop: $_loopCount" : "",
                style: const TextStyle(color: cGOLD, fontSize: 9, fontFamily: 'monospace')),
            const Text("موزه شهر شیراز",
                style: TextStyle(color: cGOLD2, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  // ── داشبورد شناور ──
  Widget _buildFloatingPanel() {
    return Positioned(
      top: 16,
      left: 16,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: cCARD,
          border: Border.all(color: cGOLD2),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 2, color: cGOLD2),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _panelVisible = false),
                        child: const Icon(Icons.close, size: 18, color: cINK3),
                      ),
                      const Text("داشبورد",
                          style: TextStyle(color: cGOLD, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: cLINE),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text("پلی‌لیست",
                        style: TextStyle(color: cINK2, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  // لیست ویدیوها
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: const Color(0xFFfffefb),
                      border: Border.all(color: cLINE),
                    ),
                    child: _playlist.isEmpty
                        ? const Center(
                            child: Text("خالی", style: TextStyle(color: cINK3, fontSize: 11)))
                        : ListView.builder(
                            itemCount: _playlist.length,
                            itemBuilder: (_, i) {
                              final name = _playlist[i].split('/').last;
                              final isCurrent = i == _currentIndex;
                              return InkWell(
                                onTap: () => _playIndex(i),
                                child: Container(
                                  color: isCurrent ? cGOLDL : null,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: Text(
                                    "${isCurrent ? '▶ ' : ''}${i + 1}. $name",
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(color: cINK2, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  _panelBtn("بازخوانی پوشه  ↻", _scanFolder, primary: true),
                  const SizedBox(height: 12),
                  Container(height: 1, color: cLINE),
                  const SizedBox(height: 12),
                  _panelBtn("پخش / مکث  ‖", _togglePlay),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _panelBtn("◂ قبلی", _playPrev)),
                      const SizedBox(width: 6),
                      Expanded(child: _panelBtn("بعدی ▸", _playNext)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _panelBtn("شروع مجدد  ↺", _restart),
                  const SizedBox(height: 6),
                  _panelBtn("توقف  ■", _stop),
                  const SizedBox(height: 12),
                  Container(height: 1, color: cLINE),
                  const SizedBox(height: 8),
                  const Text("v2.0 · Shiraz Museum",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cINK3, fontSize: 8, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelBtn(String text, VoidCallback onTap, {bool primary = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: primary ? cGOLD : cBG2,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(text,
            style: TextStyle(
              color: primary ? cBG : cINK2,
              fontSize: 12,
              fontWeight: primary ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }
}

// ── دیالوگ رمز عبور ──
class _PasswordDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const _PasswordDialog({required this.onSuccess});
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();
  String _error = "";

  void _submit() {
    if (_ctrl.text == adminPassword) {
      widget.onSuccess();
    } else {
      setState(() => _error = "رمز نادرست است، دوباره تلاش کنید");
      _ctrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: cCARD,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: cGOLD2),
      ),
      title: const Text("رمز عبور را وارد کنید",
          style: TextStyle(color: cGOLD, fontWeight: FontWeight.bold, fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: cLINE),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: cGOLD2),
              ),
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error,
                  style: const TextStyle(color: Color(0xFFa02020), fontSize: 11)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("انصراف", style: TextStyle(color: cINK2)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: cGOLD),
          onPressed: _submit,
          child: const Text("تأیید", style: TextStyle(color: cBG)),
        ),
      ],
    );
  }
}
