import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../core/cover_crop.dart';

class CoverCropScreen extends StatefulWidget {
  const CoverCropScreen({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  ui.Image? _image;
  String? _error;
  bool _saving = false;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Size _frame = Size.zero;
  double _startZoom = 1;
  Offset _sourceFocus = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final ratio = math.min(
        1.0,
        2400 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * ratio).round()),
        targetHeight: math.max(1, (descriptor.height * ratio).round()),
      );
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取这张图片，请选择其他图片');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Size get _imageSize =>
      Size(_image!.width.toDouble(), _image!.height.toDouble());

  double get _minimumZoom {
    final x = CoverFrame.aspectRatio / _imageSize.width;
    final y = 1 / _imageSize.height;
    return (math.min(x, y) / math.max(x, y)).clamp(.05, 1.0);
  }

  Offset _clampPan(Offset pan, double zoom) {
    final base = math.max(
      _frame.width / _imageSize.width,
      _frame.height / _imageSize.height,
    );
    final x = math.max(
      0.0,
      (_imageSize.width * base * zoom - _frame.width) / 2,
    );
    final y = math.max(
      0.0,
      (_imageSize.height * base * zoom - _frame.height) / 2,
    );
    return Offset(pan.dx.clamp(-x, x), pan.dy.clamp(-y, y));
  }

  Future<void> _save() async {
    if (_image == null || _saving || _frame.isEmpty) return;
    setState(() => _saving = true);
    ui.Picture? picture;
    ui.Image? output;
    try {
      final source = CoverFrame.sourceRect(_imageSize, _frame, _zoom, _pan);
      // Avoid enlarging small sources, and cap the encoded cover size.
      final width = math.max(1, math.min(1200, source.width.round()));
      final height = math.max(1, (width / CoverFrame.aspectRatio).round());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xFFEFF1EC), BlendMode.src);
      canvas.scale(width / source.width, height / source.height);
      canvas.translate(-source.left, -source.top);
      canvas.drawImage(
        _image!,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
      picture = recorder.endRecording();
      output = await picture.toImage(width, height);
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('No image bytes');
      if (mounted) {
        setState(() => _saving = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, data.buffer.asUint8List());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('封面生成失败，请重试')));
        setState(() => _saving = false);
      }
    } finally {
      output?.dispose();
      picture?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Uint8List>(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('调整封面')),
      body: _image == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(
                    padding: AppSpacing.page,
                    children: [
                      const Text('拖动图片，双指或滑动下方滑块缩放'),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, bounds) {
                          _frame = Size(
                            bounds.maxWidth,
                            bounds.maxWidth / CoverFrame.aspectRatio,
                          );
                          return Semantics(
                            label: '封面取景框，可拖动并双指缩放',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              key: const ValueKey('cover-crop-frame'),
                              onScaleStart: _saving
                                  ? null
                                  : (details) {
                                      _startZoom = _zoom;
                                      _sourceFocus =
                                          (details.localFocalPoint -
                                              _frame.center(Offset.zero) -
                                              _pan) /
                                          _zoom;
                                    },
                              onScaleUpdate: _saving
                                  ? null
                                  : (details) => setState(() {
                                      _zoom = (_startZoom * details.scale)
                                          .clamp(_minimumZoom, 6.0);
                                      _pan = _clampPan(
                                        details.localFocalPoint -
                                            _frame.center(Offset.zero) -
                                            _sourceFocus * _zoom,
                                        _zoom,
                                      );
                                    }),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.card,
                                ),
                                child: SizedBox.fromSize(
                                  size: _frame,
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _CropPainter(
                                        _image!,
                                        CoverFrame.sourceRect(
                                          _imageSize,
                                          _frame,
                                          _zoom,
                                          _pan,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.zoom_out_rounded),
                          Expanded(
                            child: Slider(
                              semanticFormatterCallback: (value) =>
                                  '${value.toStringAsFixed(1)} 倍',
                              value: _zoom,
                              min: _minimumZoom,
                              max: 6,
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() {
                                      _pan = _clampPan(
                                        _pan * (value / _zoom),
                                        value,
                                      );
                                      _zoom = value;
                                    }),
                            ),
                          ),
                          const Icon(Icons.zoom_in_rounded),
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _zoom = 1;
                                    _pan = Offset.zero;
                                  }),
                            child: const Text('重置'),
                          ),
                        ],
                      ),
                      const Text(
                        '选框内的内容会完整展示；不同卡片尺寸可能留有少量边距。',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(_saving ? '正在生成封面…' : '使用此封面'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.source);
  final ui.Image image;
  final Rect source;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFEFF1EC), BlendMode.src);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / source.width, size.height / source.height);
    canvas.translate(-source.left, -source.top);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .5)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(size.width * i / 3, 0),
        Offset(size.width * i / 3, size.height),
        line,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.source != source;
}
