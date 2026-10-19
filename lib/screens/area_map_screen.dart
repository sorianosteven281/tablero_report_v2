import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/panel.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/cached_tile_provider.dart';
import 'inspection_screen.dart';

class AreaZoneInfo {
  final String key;
  final String name;
  final LatLng center;
  final Color color;

  const AreaZoneInfo({
    required this.key,
    required this.name,
    required this.center,
    required this.color,
  });
}

class AreaMapScreen extends StatefulWidget {
  const AreaMapScreen({super.key});

  @override
  State<AreaMapScreen> createState() => _AreaMapScreenState();
}

class _AreaMapScreenState extends State<AreaMapScreen> {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locService = LocationService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  static const List<AreaZoneInfo> _zones = [
    AreaZoneInfo(key: '200_OVERLAND', name: 'Chancado / Faja Overland', center: LatLng(-11.619815, -76.144497), color: Color(0xFFE2E8F0)),
    AreaZoneInfo(key: '200_FAJA3', name: 'Faja 03 / Stockpile', center: LatLng(-11.667326, -76.146119), color: Color(0xFF38BDF8)),
    AreaZoneInfo(key: '2060_TUNEL', name: 'Túnel de Reclamo', center: LatLng(-11.666595, -76.148037), color: Color(0xFF94A3B8)),
    AreaZoneInfo(key: '210_FAJAS', name: 'Fajas 210 / 220', center: LatLng(-11.667574, -76.146744), color: Color(0xFF60A5FA)),
    AreaZoneInfo(key: '2110_MOLIENDA', name: 'Molienda / Hidrociclones', center: LatLng(-11.667827, -76.147272), color: Color(0xFFF59E0B)),
    AreaZoneInfo(key: '2115_PEBBLES', name: 'Chancado Pebbles', center: LatLng(-11.667715, -76.148334), color: Color(0xFFD97706)),
    AreaZoneInfo(key: '2210_FLOTACION', name: 'Flotación Rougher/Scav', center: LatLng(-11.668864, -76.146309), color: Color(0xFF0284C7)),
    AreaZoneInfo(key: '2212_ESPESADOR', name: 'Espesador Bulk 2212', center: LatLng(-11.670238, -76.146580), color: Color(0xFF0EA5E9)),
    AreaZoneInfo(key: '2215_REMOLIENDA', name: 'Remolienda 2215', center: LatLng(-11.670026, -76.145222), color: Color(0xFF22D3EE)),
    AreaZoneInfo(key: '230_SERVICIOS', name: 'Servicios 230', center: LatLng(-11.669306, -76.144678), color: Color(0xFF64748B)),
    AreaZoneInfo(key: '240_COBRE', name: 'Espesador Cobre / Moly', center: LatLng(-11.670495, -76.144054), color: Color(0xFFFB923C)),
    AreaZoneInfo(key: '245_FILTRADO', name: 'Filtros Prensa 245', center: LatLng(-11.670737, -76.141961), color: Color(0xFF4ADE80)),
    AreaZoneInfo(key: '251_SUBEST', name: 'Subestaciones US-001/2', center: LatLng(-11.668154, -76.145796), color: Color(0xFFA855F7)),
    AreaZoneInfo(key: '255_RELAVES', name: 'Espesadores Relaves 1-7', center: LatLng(-11.669835, -76.144860), color: Color(0xFFF43F5E)),
    AreaZoneInfo(key: '2562_GEHO', name: 'Bombas GEHO 451-456', center: LatLng(-11.668542, -76.143800), color: Color(0xFFE11D48)),
    AreaZoneInfo(key: '260_REACTIVOS', name: 'Reactivos / CMC', center: LatLng(-11.670532, -76.144569), color: Color(0xFFFBBF24)),
    AreaZoneInfo(key: '2615_CAL', name: 'Planta Lechada Cal', center: LatLng(-11.671900, -76.144689), color: Color(0xFFFDE047)),
    AreaZoneInfo(key: '400_SILOS', name: 'Silos de Cal 1-3', center: LatLng(-11.671591, -76.145292), color: Color(0xFFFEF08A)),
  ];

  List<Panel> _allPanels = [];
  List<Panel> _filteredPanels = [];
  String _selectedZoneKey = 'ALL';
  LatLng? _myLocation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final list = await _dbService.getAllPanels();
    final gps = await _locService.getLocation(allowGps: true);

    // Filter out true Hidrometalurgia
    final nonHidro = list.where((p) {
      final loc = p.loc.toUpperCase();
      final tag = p.tag.toUpperCase();
      return loc != 'HIDROMETALURGIA' && !tag.startsWith('10331');
    }).toList();

    if (mounted) {
      setState(() {
        _allPanels = nonHidro;
        _applyFilters();
        if (gps.hasValidFix) {
          _myLocation = LatLng(gps.latitude!, gps.longitude!);
        }
        _isLoading = false;
      });
    }
  }

  String _getZoneKeyForPanel(Panel p) {
    final tag = p.tag.toUpperCase();
    final loc = p.loc.toUpperCase();

    if (tag.startsWith('400') || loc.contains('SILO')) return '400_SILOS';
    if (tag.startsWith('2615') || loc.contains('LECHADA') || loc.contains('REDUCCION DE CAL')) return '2615_CAL';
    if (tag.startsWith('2562') || loc.contains('GEHO')) return '2562_GEHO';
    if (tag.startsWith('2560') || tag.startsWith('2561') || tag.startsWith('255') || loc.contains('ESPESADOR')) return '255_RELAVES';
    if (tag.startsWith('245') || tag.startsWith('2460') || loc.contains('FILTR')) return '245_FILTRADO';
    if (tag.startsWith('240') || tag.startsWith('2410') || loc.contains('MOLIBDENO')) return '240_COBRE';
    if (tag.startsWith('2212')) return '2212_ESPESADOR';
    if (tag.startsWith('2215') || loc.contains('REMOLIENDA')) return '2215_REMOLIENDA';
    if (tag.startsWith('2210') || loc.contains('FLOT') || loc.contains('ROUGHER')) return '2210_FLOTACION';
    if (tag.startsWith('2115') || loc.contains('PEBBLE')) return '2115_PEBBLES';
    if (tag.startsWith('2110') || loc.contains('MOLINO') || loc.contains('MOLIENDA') || loc.contains('HIDROCICL')) return '2110_MOLIENDA';
    if (tag.startsWith('2060') || loc.contains('TÚNEL') || loc.contains('TUNEL') || loc.contains('RECLAMO')) return '2060_TUNEL';
    if (tag.startsWith('251') || loc.contains('SUBESTACI')) return '251_SUBEST';
    if (tag.startsWith('260') || tag.startsWith('2610') || loc.contains('REACTIVO') || loc.contains('CMC')) return '260_REACTIVOS';
    if (tag.startsWith('230')) return '230_SERVICIOS';
    if (tag.startsWith('205') || loc.contains('FAJA 3') || loc.contains('FAJA 03')) return '200_FAJA3';
    if (tag.startsWith('210') || tag.startsWith('220')) return '210_FAJAS';
    if (tag.startsWith('200')) return '200_OVERLAND';
    return '230_SERVICIOS';
  }

  LatLng _getEstimatedCoordForPanel(Panel p, int index) {
    if (p.latitude != null && p.longitude != null) {
      return LatLng(p.latitude!, p.longitude!);
    }
    final zKey = _getZoneKeyForPanel(p);
    final zone = _zones.firstWhere((z) => z.key == zKey, orElse: () => _zones[9]);

    // Deterministic jitter based on tag hash so markers in the same zone scatter slightly
    final hash = p.tag.hashCode.abs();
    final angle = (hash % 360) * (pi / 180.0);
    final distance = ((hash % 100) / 100.0) * 0.00035; // ~30 meters radius

    final lat = zone.center.latitude + (distance * cos(angle));
    final lon = zone.center.longitude + (distance * sin(angle));
    return LatLng(lat, lon);
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase().replaceAll('-', '').replaceAll(' ', '');
    setState(() {
      _filteredPanels = _allPanels.where((p) {
        final zKey = _getZoneKeyForPanel(p);
        if (_selectedZoneKey != 'ALL' && zKey != _selectedZoneKey) {
          return false;
        }
        if (query.isNotEmpty) {
          final cleanTag = p.tag.toLowerCase().replaceAll('-', '').replaceAll(' ', '');
          final cleanLoc = p.loc.toLowerCase();
          return cleanTag.contains(query) || cleanLoc.contains(query);
        }
        return true;
      }).toList();
    });
  }

  void _zoomToZone(AreaZoneInfo zone) {
    setState(() {
      _selectedZoneKey = zone.key;
      _applyFilters();
    });
    _mapController.move(zone.center, 17.5);
  }

  void _showPanelSheet(Panel p, LatLng coord) {
    final zKey = _getZoneKeyForPanel(p);
    final zone = _zones.firstWhere((z) => z.key == zKey, orElse: () => _zones[9]);
    final isGpsReal = p.latitude != null && p.longitude != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16)), side: BorderSide(color: Color(0xFF334155))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.tag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF38BDF8))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isGpsReal ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFFF59E0B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isGpsReal ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                    ),
                    child: Text(
                      isGpsReal ? '📍 GPS Verificado' : '🗺️ Estimado por Zona',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isGpsReal ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(p.loc, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.domain, size: 14, color: zone.color),
                  const SizedBox(width: 4),
                  Text('Área: ${zone.name}', style: TextStyle(color: zone.color, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Coord: ${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
                  icon: const Icon(Icons.build_circle),
                  label: const Text('Iniciar Inspección', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionScreen(panel: p)));
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _myLocation ?? const LatLng(-11.6685, -76.1455);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Mapa Guía de Zonas (Planta Concentradora)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Barra de Búsqueda rápida
                Container(
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por tag o ubicación en zonas...',
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF38BDF8)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                _applyFilters();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => _applyFilters(),
                  ),
                ),

                // Carrusel horizontal de selector de Zonas
                Container(
                  color: const Color(0xFF1E293B),
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('Todas (${_allPanels.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          selected: _selectedZoneKey == 'ALL',
                          selectedColor: const Color(0xFF0284C7),
                          backgroundColor: const Color(0xFF0F172A),
                          onSelected: (_) {
                            setState(() {
                              _selectedZoneKey = 'ALL';
                              _applyFilters();
                            });
                          },
                        ),
                      ),
                      ..._zones.map((z) {
                        final isSel = _selectedZoneKey == z.key;
                        final count = _allPanels.where((p) => _getZoneKeyForPanel(p) == z.key).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text('${z.name} ($count)', style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                            backgroundColor: isSel ? z.color : const Color(0xFF0F172A),
                            side: BorderSide(color: z.color.withOpacity(0.6)),
                            onPressed: () => _zoomToZone(z),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                // Mapa satelital interactivo
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: 16.5,
                      maxZoom: 21.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        maxZoom: 21,
                        maxNativeZoom: 19,
                        tileProvider: CachedTileProvider(),
                      ),
                      MarkerLayer(
                        markers: [
                          // Mi ubicación
                          if (_myLocation != null)
                            Marker(
                              point: _myLocation!,
                              width: 22,
                              height: 22,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2.5),
                                ),
                              ),
                            ),

                          // Marcadores de Tableros con color según zona
                          ..._filteredPanels.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final p = entry.value;
                            final coord = _getEstimatedCoordForPanel(p, idx);
                            final zKey = _getZoneKeyForPanel(p);
                            final zone = _zones.firstWhere((z) => z.key == zKey, orElse: () => _zones[9]);
                            final isGpsReal = p.latitude != null && p.longitude != null;

                            return Marker(
                              point: coord,
                              width: 28,
                              height: 28,
                              child: GestureDetector(
                                onTap: () => _showPanelSheet(p, coord),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: zone.color,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black, width: 1.5),
                                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                                  ),
                                  child: Icon(
                                    isGpsReal ? Icons.bolt : Icons.location_on,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
