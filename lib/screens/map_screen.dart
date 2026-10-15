import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/panel.dart';
import '../services/database_service.dart';
import 'inspection_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final DatabaseService _dbService = DatabaseService();
  List<Panel> _panelsWithGps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPanels();
  }

  Future<void> _loadPanels() async {
    final all = await _dbService.getAllPanels();
    if (mounted) {
      setState(() {
        _panelsWithGps = all.where((p) => p.latitude != null && p.longitude != null).toList();
        _isLoading = false;
      });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa Satelital de Tableros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(-11.6685, -76.1455), // UM Chinalco Toromocho
                initialZoom: 16.0,
                maxZoom: 21.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                  maxZoom: 21,
                  maxNativeZoom: 19,
                ),
                MarkerLayer(
                  markers: _panelsWithGps.map((p) {
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
                  }).toList(),
                ),
              ],
            ),
    );
  }
}
