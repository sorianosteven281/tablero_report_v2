import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  List<Panel> _panelsWithGps = [];
  LatLng? _myLocation;
  bool _isLoading = true;

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
        _panelsWithGps = all.where((p) => p.latitude != null && p.longitude != null).toList();
        if (gps.hasValidFix) {
          _myLocation = LatLng(gps.latitude!, gps.longitude!);
        }
        _isLoading = false;
      });
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

  void _showPanelDetails(Panel p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.tag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.cyanAccent)),
              const SizedBox(height: 4),
              Text(p.loc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text('Coordenadas: ${p.latitude}, ${p.longitude}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                  icon: const Icon(Icons.build),
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
    final initialCenter = _myLocation ?? const LatLng(-11.6685, -76.1455); // UM Chinalco Toromocho

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa Satelital de Tableros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.cyanAccent,
        onPressed: _centerOnMe,
        tooltip: 'Mi Ubicación',
        child: const Icon(Icons.my_location),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
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
                ),
                MarkerLayer(
                  markers: [
                    // Marcador de Mi Ubicación (Punto azul como Google Maps)
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

                    // Marcadores de Tableros
                    ..._panelsWithGps.map((p) {
                      return Marker(
                        point: LatLng(p.latitude!, p.longitude!),
                        width: 32,
                        height: 32,
                        child: GestureDetector(
                          onTap: () => _showPanelDetails(p),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                            ),
                            child: const Icon(Icons.bolt, size: 18, color: Colors.black),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
    );
  }
}
