import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageWatermarkService {
  static final ImageWatermarkService _instance = ImageWatermarkService._internal();
  factory ImageWatermarkService() => _instance;
  ImageWatermarkService._internal();

  Uint8List? _cachedLogoBytes;

  Future<Uint8List?> _loadLogoBytes() async {
    if (_cachedLogoBytes != null) return _cachedLogoBytes;
    try {
      final byteData = await rootBundle.load('assets/images/photo_logo.png');
      _cachedLogoBytes = byteData.buffer.asUint8List();
    } catch (_) {}
    return _cachedLogoBytes;
  }

  Future<String> watermarkImage({
    required String imagePath,
    required String phase, // ANTES, OBSERVACION, DESPUES
    required String tag,
    required String location,
    required String dateStr,
    required String gpsText,
  }) async {
    final logoBytes = await _loadLogoBytes();

    final appDir = await getApplicationDocumentsDirectory();
    final fotosDir = Directory(p.join(appDir.path, 'TablerosReport_Fotos'));
    if (!fotosDir.existsSync()) {
      fotosDir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cleanTag = tag.replaceAll(RegExp(r'[^\w\-]'), '_');
    final outPath = p.join(fotosDir.path, '${cleanTag}_${phase}_$timestamp.jpg');

    try {
      // Ejecutar procesamiento pesado en segundo plano (Isolate separado)
      // para mantener la interfaz de usuario fluida y receptiva.
      return await Isolate.run(() => _processWatermark(
        imagePath: imagePath,
        outPath: outPath,
        phase: phase,
        tag: tag,
        location: location,
        dateStr: dateStr,
        gpsText: gpsText,
        logoBytes: logoBytes,
      ));
    } catch (e) {
      // Fallback seguro: si falla el procesamiento gráfico, devolver la imagen original
      return imagePath;
    }
  }

  static Future<String> _processWatermark({
    required String imagePath,
    required String outPath,
    required String phase,
    required String tag,
    required String location,
    required String dateStr,
    required String gpsText,
    required Uint8List? logoBytes,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return imagePath;

    final width = original.width;
    final height = original.height;

    // Altura del banner: 10% de la altura total (mínimo 110px)
    final bannerHeight = (height * 0.10).clamp(110, 220).toInt();
    final bannerY = height - bannerHeight;

    // Fondo del banner: azul oscuro semitransparente / opaco
    final bannerColor = img.ColorRgba8(11, 17, 32, 235);
    img.fillRect(
      original,
      x1: 0,
      y1: bannerY,
      x2: width,
      y2: height,
      color: bannerColor,
    );

    // Línea superior decorativa (celeste brillante)
    img.drawLine(
      original,
      x1: 0,
      y1: bannerY,
      x2: width,
      y2: bannerY + 2,
      color: img.ColorRgba8(56, 189, 248, 255),
    );

    // Texto del banner
    final titleLine = '[$phase] $tag - $location';
    final infoLine = '$dateStr | $gpsText';

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
      color: img.ColorRgba8(203, 213, 225, 255),
    );

    // Dibujar logo institucional a la derecha
    if (logoBytes != null) {
      try {
        final logo = img.decodeImage(logoBytes);
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
      } catch (_) {}
    }

    // Codificar en JPEG con calidad 85 optimizada
    final jpgBytes = img.encodeJpg(original, quality: 85);
    await File(outPath).writeAsBytes(jpgBytes);

    return outPath;
  }
}
