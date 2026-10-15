import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/panel.dart';
import '../models/inspection.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/image_watermark_service.dart';
import '../services/whatsapp_service.dart';

class InspectionScreen extends StatefulWidget {
  final Panel panel;
  const InspectionScreen({super.key, required this.panel});

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final ImagePicker _picker = ImagePicker();
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locService = LocationService();
  final ImageWatermarkService _watermarkService = ImageWatermarkService();
  final WhatsAppService _whatsappService = WhatsAppService();

  final TextEditingController _responsibleController = TextEditingController(text: 'Soriano');
  final TextEditingController _crewController = TextEditingController(text: 'Guardia A - Mantenimiento Eléctrico');
  final TextEditingController _notesController = TextEditingController();

  List<String> _photosBefore = [];
  List<String> _photosObs = [];
  List<String> _photosAfter = [];

  final List<String> _commonObs = [
    'Limpieza general',
    'Se cambió anti humedecedor',
    'Falta de planos',
    'Ventilador no funciona',
    'Cables sueltos',
    'Ajuste de borneras',
    'Luz piloto quemada',
    'Filtro saturado',
  ];
  final Set<String> _selectedObs = {};

  String _finalStatus = 'OPERATIVO';
  GpsResult _currentGps = GpsResult(quality: GpsQuality.indoorNoSignal, label: 'Detectando...');
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _refreshGps();
  }

  Future<void> _refreshGps() async {
    final res = await _locService.getLocation();
    if (mounted) {
      setState(() => _currentGps = res);
    }
  }

  Future<void> _takePhoto(String phase) async {
    final XFile? file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (file == null) return;

    setState(() => _isProcessing = true);

    // Refrescar GPS en vivo al momento de la foto
    final freshGps = await _locService.getLocation();
    setState(() => _currentGps = freshGps);

    final nowStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

    final processedPath = await _watermarkService.watermarkImage(
      imagePath: file.path,
      phase: phase,
      tag: widget.panel.tag,
      location: widget.panel.loc,
      dateStr: nowStr,
      gpsText: freshGps.watermarkText,
    );

    setState(() {
      if (phase == 'ANTES') {
        _photosBefore.add(processedPath);
      } else if (phase == 'OBSERVACION') {
        _photosObs.add(processedPath);
      } else if (phase == 'DESPUES') {
        _photosAfter.add(processedPath);
      }
      _isProcessing = false;
    });
  }

  String _buildFullObservations() {
    final list = _selectedObs.toList();
    if (_notesController.text.trim().isNotEmpty) {
      list.add(_notesController.text.trim());
    }
    return list.join(', ');
  }

  Future<void> _saveAndShare() async {
    if (_photosBefore.isEmpty || _photosAfter.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se requiere al menos 1 foto de ANTES y 1 foto de DESPUÉS.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final nowStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final fullObs = _buildFullObservations();

    final inspection = Inspection(
      panelTag: widget.panel.tag,
      panelLoc: widget.panel.loc,
      panelType: widget.panel.type,
      date: nowStr,
      photosBefore: _photosBefore,
      photosObs: _photosObs,
      photosAfter: _photosAfter,
      observations: fullObs,
      finalStatus: _finalStatus,
      latitude: _currentGps.latitude,
      longitude: _currentGps.longitude,
      responsible: _responsibleController.text.trim(),
      crew: _crewController.text.trim(),
    );

    await _dbService.insertInspection(inspection);
    setState(() => _isProcessing = false);

    // Compartir a WhatsApp
    await _whatsappService.shareInspection(inspection);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Widget _buildPhotoSection(String title, String phase, List<String> photos, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            TextButton.icon(
              icon: const Icon(Icons.camera_alt, size: 16),
              label: const Text('Tomar Foto', style: TextStyle(fontSize: 12)),
              onPressed: _isProcessing ? null : () => _takePhoto(phase),
            ),
          ],
        ),
        if (photos.isEmpty)
          Container(
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Text('Sin fotos de $phase', style: const TextStyle(color: Colors.grey, fontSize: 11)),
          )
        else
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              itemBuilder: (context, i) {
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(image: FileImage(File(photos[i])), fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => setState(() => photos.removeAt(i)),
                        child: const CircleAvatar(radius: 10, backgroundColor: Colors.black87, child: Icon(Icons.close, size: 12, color: Colors.white)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.panel.tag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _isProcessing
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Estampando foto y GPS...')]))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info del tablero
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.panel.tag, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(widget.panel.loc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(_currentGps.hasValidFix ? Icons.gps_fixed : Icons.roofing, color: _currentGps.hasValidFix ? Colors.greenAccent : Colors.orangeAccent, size: 16),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_currentGps.label, style: TextStyle(color: _currentGps.hasValidFix ? Colors.greenAccent : Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600))),
                            IconButton(icon: const Icon(Icons.refresh, size: 16, color: Colors.grey), onPressed: _refreshGps),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Campos de cuadrilla y técnico
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _responsibleController,
                          decoration: const InputDecoration(labelText: 'Técnico Responsable', border: OutlineInputBorder()),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _crewController,
                          decoration: const InputDecoration(labelText: 'Cuadrilla', border: OutlineInputBorder()),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Secciones de Fotos
                  _buildPhotoSection('📸 FOTOS ANTES (Obligatorio)', 'ANTES', _photosBefore, Colors.cyanAccent),
                  _buildPhotoSection('⚠️ FOTOS OBSERVACIÓN (Opcional)', 'OBSERVACION', _photosObs, Colors.amberAccent),
                  _buildPhotoSection('✅ FOTOS DESPUÉS (Obligatorio)', 'DESPUES', _photosAfter, Colors.greenAccent),

                  const SizedBox(height: 10),

                  // Observaciones Rápidas
                  const Text('Observaciones Comunes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _commonObs.map((obs) {
                      final isSel = _selectedObs.contains(obs);
                      return FilterChip(
                        label: Text(obs, style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white70)),
                        selected: isSel,
                        selectedColor: Colors.cyanAccent,
                        backgroundColor: const Color(0xFF1E293B),
                        checkmarkColor: Colors.black,
                        onSelected: (val) {
                          setState(() {
                            if (val) _selectedObs.add(obs);
                            else _selectedObs.remove(obs);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Detalle adicional de observaciones...', border: OutlineInputBorder()),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Estado Final
                  Row(
                    children: [
                      const Text('Estado Final:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('OPERATIVO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        selected: _finalStatus == 'OPERATIVO',
                        selectedColor: Colors.green,
                        onSelected: (_) => setState(() => _finalStatus = 'OPERATIVO'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('OBSERVADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        selected: _finalStatus == 'OBSERVADO',
                        selectedColor: Colors.amber[800],
                        onSelected: (_) => setState(() => _finalStatus = 'OBSERVADO'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Botón Enviar WhatsApp
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.black),
                      icon: const Icon(Icons.send, color: Colors.black),
                      label: const Text('Guardar y Compartir a WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: _saveAndShare,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
