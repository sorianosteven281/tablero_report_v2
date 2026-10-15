import 'dart:async';
import 'package:geolocator/geolocator.dart';

enum GpsQuality {
  liveFix,         // Satélite real en vivo (< 45m de precisión)
  freshCache,      // Coordenada fresca reciente (< 3 minutos, < 40m)
  indoorNoSignal,  // Sin satélite (Sala eléctrica, búnker o túnel)
  disabled,        // GPS apagado en el teléfono
  skipped          // Omitido voluntariamente por el usuario
}

class GpsResult {
  final double? latitude;
  final double? longitude;
  final GpsQuality quality;
  final String label;

  GpsResult({
    this.latitude,
    this.longitude,
    required this.quality,
    required this.label,
  });

  bool get hasValidFix =>
      latitude != null &&
      longitude != null &&
      quality != GpsQuality.indoorNoSignal &&
      quality != GpsQuality.disabled &&
      quality != GpsQuality.skipped;

  String get watermarkText {
    if (quality == GpsQuality.skipped) {
      return 'GPS: Omitido (No requerido)';
    }
    if (hasValidFix) {
      return 'GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
    }
    return 'GPS: Sin señal (Sala blindada/Túnel)';
  }

  String get displayCoords {
    if (quality == GpsQuality.skipped) {
      return 'GPS Omitido';
    }
    if (hasValidFix) {
      return '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
    }
    return 'Sin señal satelital';
  }
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Future<GpsResult> getLocation({bool allowGps = true}) async {
    if (!allowGps) {
      return GpsResult(
        quality: GpsQuality.skipped,
        label: 'GPS desactivado (opcional)',
      );
    }

    bool serviceEnabled;
    LocationPermission permission;

    // 1. Verificar si el GPS está encendido
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return GpsResult(
          quality: GpsQuality.disabled,
          label: 'GPS apagado en el celular',
        );
      }
    } catch (_) {
      return GpsResult(
        quality: GpsQuality.disabled,
        label: 'GPS no disponible',
      );
    }

    // 2. Verificar permisos
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return GpsResult(
            quality: GpsQuality.disabled,
            label: 'Permiso de ubicación denegado',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return GpsResult(
          quality: GpsQuality.disabled,
          label: 'Permiso de ubicación bloqueado',
        );
      }
    } catch (_) {
      return GpsResult(
        quality: GpsQuality.disabled,
        label: 'Permiso no disponible',
      );
    }

    // 3. Intentar obtener posición satelital real con alta precisión y timeout de 3s
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(milliseconds: 3000),
      );

      // FILTRO DE CALIDAD ESTRICTO:
      // Si la precisión es mayor a 45m (ej. 600m), es una antena celular o estimación tosca,
      // NO es satélite GPS real. No lo aceptamos como fix de panel eléctrico.
      if (position.accuracy <= 45.0) {
        return GpsResult(
          latitude: position.latitude,
          longitude: position.longitude,
          quality: GpsQuality.liveFix,
          label: 'Satélite en vivo (±${position.accuracy.toStringAsFixed(0)}m)',
        );
      }
    } catch (_) {
      // Timeout o sin cobertura de satélites
    }

    // 4. Comprobar última posición conocida reciente (< 3 min y precisión <= 35m)
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes <= 3 && lastKnown.accuracy <= 35.0) {
          return GpsResult(
            latitude: lastKnown.latitude,
            longitude: lastKnown.longitude,
            quality: GpsQuality.freshCache,
            label: 'Caché reciente (${age.inSeconds}s atrás, ±${lastKnown.accuracy.toStringAsFixed(0)}m)',
          );
        }
      }
    } catch (_) {}

    // 5. Fallback honesto: reportar sin señal (sala blindada / túnel)
    return GpsResult(
      quality: GpsQuality.indoorNoSignal,
      label: 'Sin señal satelital (Sala/Túnel)',
    );
  }
}
