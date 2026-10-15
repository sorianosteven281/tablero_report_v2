import 'dart:async';
import 'package:geolocator/geolocator.dart';

enum GpsQuality {
  liveFix,         // Satélite real en vivo (alta precisión)
  freshCache,      // Coordenada fresca reciente (< 3 minutos)
  indoorNoSignal,  // Sin satélite (Sala eléctrica, búnker o túnel)
  disabled         // GPS apagado en el teléfono
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

  bool get hasValidFix => latitude != null && longitude != null && quality != GpsQuality.indoorNoSignal && quality != GpsQuality.disabled;

  String get watermarkText {
    if (hasValidFix) {
      return 'GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
    }
    return 'GPS: Sin señal (Sala blindada/Túnel)';
  }

  String get displayCoords {
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

  Future<GpsResult> getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Verificar si el servicio GPS está activado
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return GpsResult(
        quality: GpsQuality.disabled,
        label: 'GPS desactivado en el celular',
      );
    }

    // Verificar permisos
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

    // 1. Intentar obtener posición satelital viva con timeout estricto (6 segundos)
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );

      return GpsResult(
        latitude: position.latitude,
        longitude: position.longitude,
        quality: GpsQuality.liveFix,
        label: 'Satélite en vivo (±${position.accuracy.toStringAsFixed(1)}m)',
      );
    } catch (_) {
      // Si timeout o error (ej. bajo techo de sala eléctrica o túnel)
    }

    // 2. Comprobar última posición conocida con FILTRO ANTI-OFICINA
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);

        // Si la coordenada tiene más de 3 minutos de antigüedad, la descartamos
        // porque es muy probable que sea la oficina/taller antes de caminar a planta.
        if (age.inMinutes <= 3 && lastKnown.accuracy <= 30.0) {
          return GpsResult(
            latitude: lastKnown.latitude,
            longitude: lastKnown.longitude,
            quality: GpsQuality.freshCache,
            label: 'Caché reciente (${age.inSeconds}s atrás)',
          );
        }
      }
    } catch (_) {}

    // 3. Fallback seguro: reportar honestamente que no hay señal
    return GpsResult(
      quality: GpsQuality.indoorNoSignal,
      label: 'Sin señal satelital (Sala/Túnel)',
    );
  }
}
