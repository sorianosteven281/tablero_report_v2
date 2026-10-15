import 'dart:async';
import 'package:geolocator/geolocator.dart';

enum GpsQuality {
  liveFix,         // Satélite real en vivo (alta precisión)
  freshCache,      // Coordenada fresca reciente (< 3 minutos)
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

    // Verificar si el servicio GPS está activado
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

    // Verificar permisos
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

    // 1. Intentar obtener posición satelital con timeout corto (2.5s)
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(milliseconds: 2500),
      );

      return GpsResult(
        latitude: position.latitude,
        longitude: position.longitude,
        quality: GpsQuality.liveFix,
        label: 'Satélite en vivo (±${position.accuracy.toStringAsFixed(1)}m)',
      );
    } catch (_) {
      // Timeout o sin satélite
    }

    // 2. Comprobar última posición conocida con filtro anti-oficina (< 3 min)
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes <= 3 && lastKnown.accuracy <= 50.0) {
          return GpsResult(
            latitude: lastKnown.latitude,
            longitude: lastKnown.longitude,
            quality: GpsQuality.freshCache,
            label: 'Caché reciente (${age.inSeconds}s atrás)',
          );
        }
      }
    } catch (_) {}

    // 3. Fallback seguro
    return GpsResult(
      quality: GpsQuality.indoorNoSignal,
      label: 'Sin señal satelital (Sala/Túnel)',
    );
  }
}
