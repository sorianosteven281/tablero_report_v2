import 'dart:async';
import 'package:geolocator/geolocator.dart';

enum GpsQuality {
  liveFix,         // Satélite real en vivo (alta precisión, < 40m)
  freshCache,      // Coordenada fresca reciente / precisión aceptable (< 150m)
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
    if (hasValidFix) {
      return 'GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
    }
    return ''; // Si no hay GPS o está omitido, queda completamente en blanco
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

    // 3. Revisar última posición conocida (instantáneo en 0.05s)
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        // Si tiene menos de 15 minutos y precisión realista (< 150m)
        if (age.inMinutes <= 15 && lastKnown.accuracy <= 150.0) {
          final isHighAcc = lastKnown.accuracy <= 40.0;
          return GpsResult(
            latitude: lastKnown.latitude,
            longitude: lastKnown.longitude,
            quality: isHighAcc ? GpsQuality.liveFix : GpsQuality.freshCache,
            label: isHighAcc
                ? 'Satélite en vivo (±${lastKnown.accuracy.toStringAsFixed(0)}m)'
                : 'GPS detectado (±${lastKnown.accuracy.toStringAsFixed(0)}m)',
          );
        }
      }
    } catch (_) {}

    // 4. Intentar lectura satelital fresca con timeout de 5 segundos
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      // Descartar solo si es antena celular muy tosca (> 180m, como el salto de 600m)
      if (position.accuracy <= 180.0) {
        final isHighAcc = position.accuracy <= 40.0;
        return GpsResult(
          latitude: position.latitude,
          longitude: position.longitude,
          quality: isHighAcc ? GpsQuality.liveFix : GpsQuality.freshCache,
          label: isHighAcc
              ? 'Satélite en vivo (±${position.accuracy.toStringAsFixed(0)}m)'
              : 'GPS detectado (±${position.accuracy.toStringAsFixed(0)}m)',
        );
      }
    } catch (_) {
      // Timeout o sin cobertura directa
    }

    // 5. Fallback honesto: reportar sin señal (sala blindada / túnel)
    return GpsResult(
      quality: GpsQuality.indoorNoSignal,
      label: 'Sin señal satelital (Sala/Túnel)',
    );
  }
}
