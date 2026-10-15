import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageWatermarkService {
  static final ImageWatermarkService _instance = ImageWatermarkService._internal();
  factory ImageWatermarkService() => _instance;
  ImageWatermarkService._internal();

  img.Image? _cachedLogo;

  Future<img.Image?> _loadLogo() async {
    if (_cachedLogo != null) return _cachedLogo;
    try {
      final byteData = await rootBundle.load('assets/images/photo_logo.png');
      _cachedLogo = img.decodeImage(byteData.buffer.asUint8List());
    } catch (_) {}
    return _cachedLogo;
  }

  Future<String> watermarkImage({
    required String imagePath,
    required String phase, // ANTES, OBSERVACION, DESPUES
    required String tag,
    required String location,
    required String dateStr,
    required String gpsText,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return imagePath;

    // Dimensiones
    final width = original.width;
    final height = original.height;

    // Altura del banner: 10% de la altura total (mínimo 110px)
    final bannerHeight = (height * 0.10).clamp(110, 220).toInt();
    final bannerY = height - bannerHeight;

    // Fondo del banner: azul oscuro semitransparente / opaco
    final bannerColor = img.ColorRgba8(11, 17, 32, 230); // #0b1120 con opacidad
    img.fillRect(
      original,
      x1: 0,
      y1: bannerY,
      x2: width,
      y2: height,
      color: bannerColor,
    );

    // Línea superior decorativa
    img.drawLine(
      original,
      x1: 0,
      y1: bannerY,
      x2: width,
      y2: bannerY + 2,
      color: img.ColorRgba8(56, 189, 248, 255), // Celeste acento
    );

    // Texto del banner
    final titleLine = '[$phase] $tag - $location';
    final infoLine = '$dateStr | $gpsText';

    // Usar fuente de img
    final font = bannerHeight > 140 ? img.arial24 : img.arial14;
    final textY1 = bannerY + (bannerHeight * 0.22).toInt();
    final textY2 = bannerY + (bannerHeight * 0.58).toInt();

    img.drawString(
      original,
      titleLine,
      font: font,
      x: 20,
      y: textY1,
      color: img.ColorRgba8(255, 255, 255, 255),
    );

    img.drawString(
      original,
      infoLine,
      font: font,
      x: 20,
      y: textY2,
      color: img.ColorRgba8(203, 213, 225, 255), // slate-300
    );

    // Dibujar logo a la derecha si está disponible
    final logo = await _loadLogo();
    if (logo != null) {
      final logoH = (bannerHeight * 0.70).toInt();
      final logoW = (logo.width * (logoH / logo.height)).toInt();
      final logoX = width - logoW - 20;
      final logoY = bannerY + ((bannerHeight - logoH) / 2).toInt();

      final scaledLogo = img.copyResize(logo, width: logoW, height: logoH);
      img.compositeImage(
        original,
        scaledLogo,
        dstX: logoX,
        dstY: logoY,
      );
    }

    // Guardar imagen procesada
    final appDir = await getApplicationDocumentsDirectory();
    final fotosDir = Directory(p.join(appDir.path, 'TablerosReport_Fotos'));
    if (!fotosDir.existsSync()) {
      fotosDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanTag = tag.replaceAll(RegExp(r'[^\w\-]'), '_');
    final outPath = p.join(fotosDir.path, '${cleanTag}_${phase}_$timestamp.jpg');

    final jpgBytes = img.encodeJpg(original, quality: 85);
    await File(outPath).writeAsBytes(jpgBytes);

    return outPath;
  }
}
