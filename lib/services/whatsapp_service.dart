import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../models/inspection.dart';

class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  String formatReportText(Inspection inspection) {
    return '''
REPORTE DE MANTENIMIENTO TÉCNICO
----------------------------------------
Cuadrilla: ${inspection.crew}
Responsable: ${inspection.responsible}
Equipo/Tablero: ${inspection.panelTag}
Ubicación: ${inspection.panelLoc}
Tipo: ${inspection.panelType}
Fecha y Hora: ${inspection.date}
----------------------------------------
Observaciones:
${inspection.observations.isEmpty ? 'Limpieza general, operativo.' : inspection.observations}
----------------------------------------
Estado Final: ${inspection.finalStatus}
'''.trim();
  }

  Future<void> shareInspection(Inspection inspection) async {
    final text = formatReportText(inspection);
    final allPhotoPaths = [
      ...inspection.photosBefore,
      ...inspection.photosObs,
      ...inspection.photosAfter,
    ];

    // Filtrar estrictamente solo los archivos que existen físicamente en disco
    final validPhotos = allPhotoPaths
        .where((p) => p.isNotEmpty && File(p).existsSync())
        .toList();

    try {
      if (validPhotos.isNotEmpty) {
        final xFiles = validPhotos.map((p) => XFile(p)).toList();
        await Share.shareXFiles(
          xFiles,
          text: text,
          subject: 'Reporte: ${inspection.panelTag}',
        );
      } else {
        await Share.share(
          text,
          subject: 'Reporte: ${inspection.panelTag}',
        );
      }
    } catch (e) {
      // Fallback seguro: si falla compartir con imágenes (ej. permisos de caché),
      // compartir al menos el texto del reporte para no bloquear al técnico.
      try {
        await Share.share(
          text,
          subject: 'Reporte: ${inspection.panelTag}',
        );
      } catch (_) {}
    }
  }
}
