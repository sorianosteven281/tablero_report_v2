import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Gestor de caché persistente para teselas/tiles del mapa satelital.
/// Guarda las partes del mapa descargadas en el almacenamiento del dispositivo
/// para acceso instantáneo y uso 100% offline sin volver a descargarlas.
class MapTileCacheManager {
  static final CacheManager instance = CacheManager(
    Config(
      'map_tiles_store',
      stalePeriod: const Duration(days: 180), // Conserva los tiles descargados por 6 meses
      maxNrOfCacheObjects: 20000,            // Hasta 20,000 bloques de mapa persistentes
    ),
  );
}

/// Proveedor de teselas con caché local en disco para flutter_map.
class CachedTileProvider extends TileProvider {
  final BaseCacheManager _cacheManager;

  CachedTileProvider({
    BaseCacheManager? cacheManager,
    super.headers,
  }) : _cacheManager = cacheManager ?? MapTileCacheManager.instance;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      cacheManager: _cacheManager,
      headers: headers,
    );
  }
}
