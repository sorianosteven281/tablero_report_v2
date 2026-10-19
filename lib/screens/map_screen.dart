import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/panel.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import 'inspection_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locService = LocationService();
  final MapController _mapController = MapController();
  final GlobalKey _mapKey = GlobalKey();

  List<Panel> _allPanels = [];
  List<Panel> _panelsWithGps = [];
  LatLng? _myLocation;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _showLabels = true;
  bool _useSatellite = true;

  // Modo Ubicar / Reubicar
  bool _isPlacingMode = false;
  Panel? _placingPanel;

  static const List<Map<String, dynamic>> _palette = [
    {'name': 'Cian', 'hex': '#06B6D4', 'color': Color(0xFF06B6D4)},
    {'name': 'Verde', 'hex': '#10B981', 'color': Color(0xFF10B981)},
    {'name': 'Ámbar', 'hex': '#F59E0B', 'color': Color(0xFFF59E0B)},
    {'name': 'Rojo', 'hex': '#EF4444', 'color': Color(0xFFEF4444)},
    {'name': 'Azul', 'hex': '#0284C7', 'color': Color(0xFF0284C7)},
    {'name': 'Naranja', 'hex': '#F97316', 'color': Color(0xFFF97316)},
    {'name': 'Púrpura', 'hex': '#8B5CF6', 'color': Color(0xFF8B5CF6)},
    {'name': 'Rosa', 'hex': '#EC4899', 'color': Color(0xFFEC4899)},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final all = await _dbService.getAllPanels();
    final gps = await _locService.getLocation(allowGps: true);

    if (mounted) {
      setState(() {
        _allPanels = all;
        _panelsWithGps = all.where((p) => p.latitude != null && p.longitude != null).toList();
        if (gps.hasValidFix) {
          _myLocation = LatLng(gps.latitude!, gps.longitude!);
        }
        _isLoading = false;
      });
    }
  }

  Color _parseColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return const Color(0xFF06B6D4);
    try {
      final hex = hexString.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF06B6D4);
    }
  }

  Future<void> _centerOnMe() async {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 18.0);
      return;
    }

    final gps = await _locService.getLocation(allowGps: true);
    if (gps.hasValidFix && mounted) {
      setState(() => _myLocation = LatLng(gps.latitude!, gps.longitude!));
      _mapController.move(_myLocation!, 18.0);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin señal satelital en este momento.')),
      );
    }
  }

  // Activa el modo para ubicar un panel con la mira central
  void _startPlacingMode(Panel panel) {
    setState(() {
      _isPlacingMode = true;
      _placingPanel = panel;
    });

    if (panel.latitude != null && panel.longitude != null) {
      _mapController.move(LatLng(panel.latitude!, panel.longitude!), 18.5);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mueve el mapa para ubicar "${panel.tag}" y presiona Fijar Ubicación.'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _confirmPlacement() async {
    if (_placingPanel == null) return;

    final center = _mapController.camera.center;
    final tag = _placingPanel!.tag;

    await _dbService.updatePanelDetails(
      tag,
      latitude: center.latitude,
      longitude: center.longitude,
    );

    await _loadData();

    if (mounted) {
      setState(() {
        _isPlacingMode = false;
        _placingPanel = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Punto guardado para $tag: (${center.latitude.toStringAsFixed(6)}, ${center.longitude.toStringAsFixed(6)})'),
          backgroundColor: Colors.green[800],
        ),
      );
    }
  }

  void _cancelPlacement() {
    setState(() {
      _isPlacingMode = false;
      _placingPanel = null;
    });
  }

  // Exportar captura del mapa y compartir por WhatsApp
  Future<void> _exportMap() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      final boundary = _mapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('No se pudo capturar la vista del mapa.');
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Error al codificar imagen PNG.');
      }

      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final timeStr = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final file = File('${tempDir.path}/mapa_tableros_$timeStr.png');
      await file.writeAsBytes(bytes);

      if (mounted) {
        final totalGps = _panelsWithGps.length;
        await Share.shareXFiles(
          [XFile(file.path)],
          text: '📍 *MAPA DE TABLEROS Y PUNTOS TÉCNICOS - CHINALCO*\nTableros georreferenciados: $totalGps\nGenerado con Tablero Report App.',
          subject: 'Mapa de Tableros Chinalco',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar mapa: $e'), backgroundColor: Colors.red[800]),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // Modal para seleccionar qué tablero ubicar o registrar uno nuevo
  void _showSelectPanelToPlaceDialog({LatLng? initialCoord}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return _SelectPanelModal(
          panels: _allPanels,
          initialCoord: initialCoord,
          onPanelSelected: (panel) {
            Navigator.pop(ctx);
            if (initialCoord != null) {
              _savePanelAtCoord(panel, initialCoord);
            } else {
              _startPlacingMode(panel);
            }
          },
          onNewManualCreated: (newPanel) async {
            Navigator.pop(ctx);
            await _dbService.insertPanel(newPanel);
            await _loadData();
            if (newPanel.latitude == null) {
              _startPlacingMode(newPanel);
            } else {
              _mapController.move(LatLng(newPanel.latitude!, newPanel.longitude!), 18.5);
            }
          },
        );
      },
    );
  }

  Future<void> _savePanelAtCoord(Panel panel, LatLng coord) async {
    await _dbService.updatePanelDetails(
      panel.tag,
      latitude: coord.latitude,
      longitude: coord.longitude,
    );
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ubicado "${panel.tag}" en (${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)})'),
          backgroundColor: Colors.green[800],
        ),
      );
    }
  }

  // Modal de detalles y edición del punto (color, notas, reubicar)
  void _showPanelDetails(Panel p) {
    final noteCtrl = TextEditingController(text: p.note ?? '');
    String selectedHex = p.color ?? '#06B6D4';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentColor = _parseColor(selectedHex);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barra de agarre
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Encabezado
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: currentColor.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: currentColor, width: 2),
                          ),
                          child: Icon(Icons.bolt, color: currentColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.tag,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: currentColor,
                                ),
                              ),
                              Text(p.loc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(
                                'GPS: ${p.latitude?.toStringAsFixed(6)}, ${p.longitude?.toStringAsFixed(6)}',
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Selector de Color
                    const Text('Color identificador del TAG:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _palette.map((item) {
                        final hex = item['hex'] as String;
                        final color = item['color'] as Color;
                        final isSelected = selectedHex.toUpperCase() == hex.toUpperCase();

                        return GestureDetector(
                          onTap: () async {
                            setModalState(() => selectedHex = hex);
                            await _dbService.updatePanelDetails(p.tag, color: hex);
                            await _loadData();
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: isSelected ? 3 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)]
                                  : null,
                            ),
                            child: isSelected ? const Icon(Icons.check, size: 18, color: Colors.black) : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Campo de Guía / Sugerencia / Nota
                    const Text('Guía de Acceso o Sugerencia Técnica:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ej. Acceso por escalera posterior, llevar llave 1/2, pulsador observado...',
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.save, color: Colors.cyanAccent),
                          tooltip: 'Guardar Nota',
                          onPressed: () async {
                            final note = noteCtrl.text.trim();
                            await _dbService.updatePanelDetails(p.tag, note: note);
                            await _loadData();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Nota guardada con éxito'), duration: Duration(seconds: 2)),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Botones de acción rápida
                    Row(
                      children: [
                        // Reubicar
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.cyanAccent,
                              side: const BorderSide(color: Colors.cyanAccent),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.open_with, size: 18),
                            label: const Text('Reubicar'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _startPlacingMode(p);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Iniciar Inspección
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.build, size: 18),
                            label: const Text('Inspeccionar', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionScreen(panel: p)));
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Quitar ubicación
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
                        icon: const Icon(Icons.location_off, size: 16),
                        label: const Text('Quitar coordenadas del mapa', style: TextStyle(fontSize: 12)),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _dbService.updatePanelDetails(p.tag, clearGps: true);
                          await _loadData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Coordenadas eliminadas para ${p.tag}')),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _myLocation ?? const LatLng(-11.6685, -76.1455); // UM Chinalco Toromocho

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mapa Satelital de Tableros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              '${_panelsWithGps.length} de ${_allPanels.length} tableros en mapa',
              style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
            ),
          ],
        ),
        actions: [
          // Alternar Satélite vs Calles
          IconButton(
            icon: Icon(_useSatellite ? Icons.layers : Icons.satellite_alt, color: Colors.white70),
            tooltip: _useSatellite ? 'Cambiar a Mapa Callejero' : 'Cambiar a Vista Satelital',
            onPressed: () => setState(() => _useSatellite = !_useSatellite),
          ),

          // Alternar Etiquetas TAG
          IconButton(
            icon: Icon(_showLabels ? Icons.label : Icons.label_off, color: _showLabels ? Colors.cyanAccent : Colors.grey),
            tooltip: _showLabels ? 'Ocultar Nombres TAG' : 'Mostrar Nombres TAG',
            onPressed: () => setState(() => _showLabels = !_showLabels),
          ),

          // Exportar Mapa (Captura y Compartir)
          IconButton(
            icon: _isExporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                : const Icon(Icons.share, color: Colors.cyanAccent),
            tooltip: 'Exportar Mapa y Compartir',
            onPressed: _isExporting ? null : _exportMap,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : Stack(
              children: [
                // Vista del Mapa con soporte de Captura HD
                RepaintBoundary(
                  key: _mapKey,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: 16.5,
                      maxZoom: 21.0,
                      onLongPress: (tapPosition, point) {
                        if (!_isPlacingMode) {
                          _showSelectPanelToPlaceDialog(initialCoord: point);
                        }
                      },
                    ),
                    children: [
                      // Capa de mapa: Satélite ArcGIS HD o Vector OSM
                      if (_useSatellite)
                        TileLayer(
                          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                          maxZoom: 21,
                          maxNativeZoom: 19,
                        )
                      else
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.tablero_report',
                          maxZoom: 19,
                        ),

                      // Marcadores de Tableros y Puntos
                      MarkerLayer(
                        markers: [
                          // Marcador de Mi Ubicación
                          if (_myLocation != null)
                            Marker(
                              point: _myLocation!,
                              width: 24,
                              height: 24,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                                ),
                              ),
                            ),

                          // Pines de Tableros con Color y Badge de TAG
                          ..._panelsWithGps.map((p) {
                            final pinColor = _parseColor(p.color);
                            final hasNote = p.note != null && p.note!.trim().isNotEmpty;

                            return Marker(
                              point: LatLng(p.latitude!, p.longitude!),
                              width: _showLabels ? 100 : 36,
                              height: _showLabels ? 56 : 36,
                              child: GestureDetector(
                                onTap: () => _showPanelDetails(p),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_showLabels)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F172A).withOpacity(0.88),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: pinColor, width: 1.2),
                                          boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 4)],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              p.tag,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (hasNote) ...[
                                              const SizedBox(width: 3),
                                              Icon(Icons.edit_note, size: 12, color: pinColor),
                                            ],
                                          ],
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: pinColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 4, offset: const Offset(0, 2))
                                        ],
                                      ),
                                      child: const Icon(Icons.bolt, size: 16, color: Colors.black),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),

                // Mira central para colocación precisa en modo ubicar
                if (_isPlacingMode && _placingPanel != null) ...[
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withOpacity(0.95),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.cyanAccent, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 8)],
                          ),
                          child: Text(
                            _placingPanel!.tag,
                            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Icon(
                          Icons.location_searching,
                          color: Colors.cyanAccent,
                          size: 38,
                          shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                        ),
                      ],
                    ),
                  ),

                  // Barra flotante inferior de confirmación
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.cyanAccent, width: 1.5),
                        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Mueve el mapa hacia el punto de "${_placingPanel!.tag}"',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey,
                                    side: const BorderSide(color: Colors.grey),
                                  ),
                                  onPressed: _cancelPlacement,
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyanAccent,
                                    foregroundColor: Colors.black,
                                  ),
                                  icon: const Icon(Icons.check_circle),
                                  label: const Text('Fijar Ubicación', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: _confirmPlacement,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),

      // Botones Flotantes (si no está en modo colocar)
      floatingActionButton: _isPlacingMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Centrar en Mi GPS
                FloatingActionButton.small(
                  heroTag: 'fab_my_loc',
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.cyanAccent,
                  onPressed: _centerOnMe,
                  tooltip: 'Mi Ubicación GPS',
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 10),

                // Añadir / Ubicar Tablero
                FloatingActionButton.extended(
                  heroTag: 'fab_add_panel',
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Ubicar Tablero', style: TextStyle(fontWeight: FontWeight.bold)),
                  tooltip: 'Seleccionar tablero para ubicar en mapa',
                  onPressed: () => _showSelectPanelToPlaceDialog(),
                ),
              ],
            ),
    );
  }
}

// Modal para buscar y seleccionar tableros o crear puntos manuales
class _SelectPanelModal extends StatefulWidget {
  final List<Panel> panels;
  final LatLng? initialCoord;
  final Function(Panel) onPanelSelected;
  final Function(Panel) onNewManualCreated;

  const _SelectPanelModal({
    required this.panels,
    this.initialCoord,
    required this.onPanelSelected,
    required this.onNewManualCreated,
  });

  @override
  State<_SelectPanelModal> createState() => _SelectPanelModalState();
}

class _SelectPanelModalState extends State<_SelectPanelModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Panel> _filtered = [];
  bool _filterOnlyWithoutGps = false;

  @override
  void initState() {
    super.initState();
    _filtered = widget.panels;
  }

  void _applyFilter() {
    final query = _searchCtrl.text.trim().toUpperCase();
    setState(() {
      _filtered = widget.panels.where((p) {
        final matchesQuery = query.isEmpty ||
            p.tag.toUpperCase().contains(query) ||
            p.loc.toUpperCase().contains(query) ||
            p.type.toUpperCase().contains(query);

        final matchesGps = !_filterOnlyWithoutGps || (p.latitude == null || p.longitude == null);

        return matchesQuery && matchesGps;
      }).toList();
    });
  }

  void _showCreateManualDialog() {
    final tagCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String selectedHex = '#06B6D4';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Row(
                children: [
                  Icon(Icons.add_location, color: Colors.cyanAccent),
                  SizedBox(width: 8),
                  Text('Nuevo Punto / Guía Manual', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: tagCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'TAG o Nombre del Punto *',
                        hintText: 'Ej. REFUGIO-01, BOMBA-400...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Ubicación / Área *',
                        hintText: 'Ej. Espesadores, Flotación...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Guía / Nota / Sugerencia',
                        hintText: 'Ej. Acceso directo por faja 03...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Color identificador:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: _MapScreenState._palette.map((item) {
                        final hex = item['hex'] as String;
                        final color = item['color'] as Color;
                        final isSel = selectedHex.toUpperCase() == hex.toUpperCase();
                        return GestureDetector(
                          onTap: () => setDlgState(() => selectedHex = hex),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: isSel ? Colors.white : Colors.transparent, width: isSel ? 2 : 1),
                            ),
                            child: isSel ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                  onPressed: () {
                    final tag = tagCtrl.text.trim().toUpperCase();
                    final loc = locCtrl.text.trim();
                    if (tag.isEmpty || loc.isEmpty) {
                      return;
                    }
                    Navigator.pop(ctx);
                    final newP = Panel(
                      tag: tag,
                      loc: loc,
                      type: 'PUNTO MANUAL',
                      latitude: widget.initialCoord?.latitude,
                      longitude: widget.initialCoord?.longitude,
                      color: selectedHex,
                      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                    );
                    widget.onNewManualCreated(newP);
                  },
                  child: const Text('Crear Punto'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Barra de agarre
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),

          // Título y botón de crear manual
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Seleccionar Tablero a Ubicar',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.cyanAccent),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo Punto', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _showCreateManualDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Buscador
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => _applyFilter(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar por TAG o área (ej. 2214, CP060)...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),

          // Filtro rápido: "Solo sin ubicar"
          Row(
            children: [
              FilterChip(
                label: const Text('Solo sin ubicar GPS', style: TextStyle(fontSize: 12)),
                selected: _filterOnlyWithoutGps,
                selectedColor: Colors.cyanAccent.withOpacity(0.2),
                checkmarkColor: Colors.cyanAccent,
                labelStyle: TextStyle(color: _filterOnlyWithoutGps ? Colors.cyanAccent : Colors.white70),
                backgroundColor: const Color(0xFF0F172A),
                onSelected: (val) {
                  setState(() => _filterOnlyWithoutGps = val);
                  _applyFilter();
                },
              ),
              const Spacer(),
              Text('${_filtered.length} resultados', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),

          // Lista de resultados
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No se encontraron tableros', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final p = _filtered[index];
                      final hasGps = p.latitude != null && p.longitude != null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasGps ? Colors.green.withOpacity(0.3) : Colors.amber.withOpacity(0.3),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: Icon(
                            hasGps ? Icons.location_on : Icons.location_off_outlined,
                            color: hasGps ? Colors.greenAccent : Colors.amberAccent,
                          ),
                          title: Text(
                            p.tag,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(
                            p.loc,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hasGps ? const Color(0xFF334155) : Colors.cyanAccent,
                              foregroundColor: hasGps ? Colors.white : Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            onPressed: () => widget.onPanelSelected(p),
                            child: Text(
                              hasGps ? 'Reubicar' : 'Ubicar',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
