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

class PhotoItem {
  final String originalPath;
  String? stampedPath;
  bool isStamping;

  PhotoItem({
    required this.originalPath,
    this.stampedPath,
    this.isStamping = false,
  });

  String get currentPath => stampedPath ?? originalPath;
}

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

  final List<PhotoItem> _photosBefore = [];
  final List<PhotoItem> _photosObs = [];
  final List<PhotoItem> _photosAfter = [];

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
  bool _gpsEnabled = true;
  GpsResult _currentGps = GpsResult(quality: GpsQuality.indoorNoSignal, label: 'Detectando GPS...');
  bool _isSaving = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _refreshGps();
  }

  Future<void> _refreshGps() async {
    if (!_gpsEnabled) {
      setState(() {
        _currentGps = GpsResult(quality: GpsQuality.skipped, label: 'GPS desactivado');
      });
      return;
    }

    final res = await _locService.getLocation(allowGps: true);
    if (mounted) {
      setState(() => _currentGps = res);
    }
  }

  Future<void> _takePhoto(String phase) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return;

      final item = PhotoItem(
        originalPath: file.path,
        isStamping: true,
      );

      setState(() {
        if (phase == 'ANTES') {
          _photosBefore.add(item);
        } else if (phase == 'OBSERVACION') {
          _photosObs.add(item);
        } else if (phase == 'DESPUES') {
          _photosAfter.add(item);
        }
      });

      // Procesamiento de estampado en segundo plano (no congela la pantalla)
      _processPhotoInBackground(item, phase);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al capturar foto: $e')),
        );
      }
    }
  }

  Future<void> _processPhotoInBackground(PhotoItem item, String phase) async {
    try {
      final nowStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      final gpsText = _gpsEnabled ? _currentGps.watermarkText : 'GPS: Omitido (No requerido)';

      final stampedPath = await _watermarkService.watermarkImage(
        imagePath: item.originalPath,
        phase: phase,
        tag: widget.panel.tag,
        location: widget.panel.loc,
        dateStr: nowStr,
        gpsText: gpsText,
      );

      if (mounted) {
        setState(() {
          item.stampedPath = stampedPath;
          item.isStamping = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => item.isStamping = false);
      }
    }
  }

  String _buildFullObservations() {
    final list = _selectedObs.toList();
    if (_notesController.text.trim().isNotEmpty) {
      list.add(_notesController.text.trim());
    }
    return list.join(', ');
  }

  Future<void> _saveAndShare() async {
    // Si alguna foto sigue estampándose en segundo plano, esperar hasta 2.5s
    final allItems = [..._photosBefore, ..._photosObs, ..._photosAfter];
    if (allItems.any((p) => p.isStamping)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Terminando de estampar fotos en segundo plano...'),
          duration: Duration(seconds: 1),
        ),
      );
      int waits = 0;
      while (allItems.any((p) => p.isStamping) && waits < 10) {
        await Future.delayed(const Duration(milliseconds: 250));
        waits++;
      }
    }

    if (_photosBefore.isEmpty || _photosAfter.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se requiere al menos 1 foto de ANTES y 1 foto de DESPUÉS.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = 'Guardando reporte y abriendo WhatsApp...';
    });

    try {
      final nowStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
      final fullObs = _buildFullObservations();

      final inspection = Inspection(
        panelTag: widget.panel.tag,
        panelLoc: widget.panel.loc,
        panelType: widget.panel.type,
        date: nowStr,
        photosBefore: _photosBefore.map((p) => p.currentPath).toList(),
        photosObs: _photosObs.map((p) => p.currentPath).toList(),
        photosAfter: _photosAfter.map((p) => p.currentPath).toList(),
        observations: fullObs,
        finalStatus: _finalStatus,
        latitude: (_gpsEnabled && _currentGps.hasValidFix) ? _currentGps.latitude : null,
        longitude: (_gpsEnabled && _currentGps.hasValidFix) ? _currentGps.longitude : null,
        responsible: _responsibleController.text.trim(),
        crew: _crewController.text.trim(),
      );

      await _dbService.insertInspection(inspection);

      // Compartir a WhatsApp de forma segura
      await _whatsappService.shareInspection(inspection);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte guardado. Detalle al compartir: $e'),
            backgroundColor: Colors.amber[900],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildGpsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.panel.tag,
                      style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(widget.panel.loc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              // Switch de GPS Opcional
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _gpsEnabled ? 'GPS ON' : 'GPS OFF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _gpsEnabled ? Colors.greenAccent : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _gpsEnabled,
                    activeColor: Colors.greenAccent,
                    onChanged: (val) {
                      setState(() {
                        _gpsEnabled = val;
                        if (!val) {
                          _currentGps = GpsResult(
                            quality: GpsQuality.skipped,
                            label: 'GPS desactivado (opcional)',
                          );
                        } else {
                          _refreshGps();
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                !_gpsEnabled
                    ? Icons.location_off
                    : (_currentGps.hasValidFix ? Icons.gps_fixed : Icons.roofing),
                color: !_gpsEnabled
                    ? Colors.grey
                    : (_currentGps.hasValidFix ? Colors.greenAccent : Colors.orangeAccent),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _gpsEnabled ? _currentGps.label : 'GPS no requerido para este reporte',
                  style: TextStyle(
                    color: !_gpsEnabled
                        ? Colors.grey
                        : (_currentGps.hasValidFix ? Colors.greenAccent : Colors.orangeAccent),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_gpsEnabled)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
                  onPressed: _refreshGps,
                  tooltip: 'Actualizar GPS',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(String title, String phase, List<PhotoItem> photos, Color color) {
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
              onPressed: () => _takePhoto(phase),
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
                final item = photos[i];
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(File(item.currentPath)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (item.isStamping)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 2,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => setState(() => photos.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.black87,
                          child: Icon(Icons.close, size: 12, color: Colors.white),
                        ),
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
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info del tablero + Switch GPS
                _buildGpsCard(),
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
                          if (val) {
                            _selectedObs.add(obs);
                          } else {
                            _selectedObs.remove(obs);
                          }
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
                    onPressed: _isSaving ? null : _saveAndShare,
                  ),
                ),
              ],
            ),
          ),

          // Overlay no bloqueante durante guardado
          if (_isSaving)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF25D366)),
                      const SizedBox(height: 14),
                      Text(
                        _statusMessage,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
