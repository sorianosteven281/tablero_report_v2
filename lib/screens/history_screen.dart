import 'dart:io';
import 'package:flutter/material.dart';
import '../models/inspection.dart';
import '../services/database_service.dart';
import '../services/whatsapp_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  final WhatsAppService _whatsappService = WhatsAppService();

  List<Inspection> _inspections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final list = await _dbService.getAllInspections();
    setState(() {
      _inspections = list;
      _isLoading = false;
    });
  }

  void _showEditDialog(Inspection item) {
    final respCtrl = TextEditingController(text: item.responsible);
    final crewCtrl = TextEditingController(text: item.crew);
    final obsCtrl = TextEditingController(text: item.observations);
    String status = item.finalStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF334155))),
          title: Row(
            children: [
              const Icon(Icons.edit_note, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Editar: ${item.panelTag}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: respCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Técnico Responsable',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person, color: Color(0xFF38BDF8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: crewCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cuadrilla',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.groups, color: Color(0xFF38BDF8)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: ['OPERATIVO', 'EN OBSERVACIÓN', 'NO OPERATIVO'].contains(status) ? status : 'OPERATIVO',
                  decoration: const InputDecoration(
                    labelText: 'Estado Final',
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: const Color(0xFF1E293B),
                  items: const [
                    DropdownMenuItem(value: 'OPERATIVO', child: Text('OPERATIVO', style: TextStyle(color: Color(0xFF10B981)))),
                    DropdownMenuItem(value: 'EN OBSERVACIÓN', child: Text('EN OBSERVACIÓN', style: TextStyle(color: Color(0xFFF59E0B)))),
                    DropdownMenuItem(value: 'NO OPERATIVO', child: Text('NO OPERATIVO', style: TextStyle(color: Color(0xFFEF4444)))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => status = val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: obsCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () async {
                final updated = Inspection(
                  id: item.id,
                  panelTag: item.panelTag,
                  panelLoc: item.panelLoc,
                  panelType: item.panelType,
                  date: item.date,
                  photosBefore: item.photosBefore,
                  photosObs: item.photosObs,
                  photosAfter: item.photosAfter,
                  observations: obsCtrl.text.trim(),
                  finalStatus: status,
                  latitude: item.latitude,
                  longitude: item.longitude,
                  responsible: respCtrl.text.trim().isEmpty ? 'Pon tu nombre' : respCtrl.text.trim(),
                  crew: crewCtrl.text.trim(),
                );
                await _dbService.updateInspection(updated);
                Navigator.pop(ctx);
                _loadHistory();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Reporte actualizado correctamente.'),
                      action: SnackBarAction(
                        label: 'Reenviar WA',
                        textColor: const Color(0xFF25D366),
                        onPressed: () => _whatsappService.shareInspection(updated),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Inspecciones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _inspections.isEmpty
              ? const Center(child: Text('No hay inspecciones registradas.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _inspections.length,
                  itemBuilder: (context, i) {
                    final item = _inspections[i];
                    final allPhotos = [...item.photosBefore, ...item.photosObs, ...item.photosAfter];
                    final isOperativo = item.finalStatus.toUpperCase().contains('OPERATIVO');

                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFF334155))),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item.panelTag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF38BDF8))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isOperativo ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFFF59E0B).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isOperativo ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                                  ),
                                  child: Text(
                                    item.finalStatus,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isOperativo ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(item.panelLoc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('${item.date} | Resp: ${item.responsible}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            if (item.observations.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('Obs: ${item.observations}', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontStyle: FontStyle.italic)),
                            ],
                            const SizedBox(height: 8),

                            if (allPhotos.isNotEmpty)
                              SizedBox(
                                height: 60,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: allPhotos.length,
                                  itemBuilder: (context, pIdx) {
                                    final p = allPhotos[pIdx];
                                    final fileExists = File(p).existsSync();
                                    return Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      width: 50,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(6),
                                        image: fileExists
                                            ? DecorationImage(image: FileImage(File(p)), fit: BoxFit.cover)
                                            : null,
                                      ),
                                      child: !fileExists
                                          ? const Icon(Icons.image_not_supported, size: 20, color: Colors.white24)
                                          : null,
                                    );
                                  },
                                ),
                              ),

                            const Divider(color: Colors.white12, height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF38BDF8),
                                    side: const BorderSide(color: Color(0xFF38BDF8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.edit_note, size: 16),
                                  label: const Text('Editar', style: TextStyle(fontSize: 12)),
                                  onPressed: () => _showEditDialog(item),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.share, size: 16, color: Color(0xFF25D366)),
                                  label: const Text('Reenviar WhatsApp', style: TextStyle(color: Color(0xFF25D366), fontSize: 12)),
                                  onPressed: () async {
                                    try {
                                      await _whatsappService.shareInspection(item);
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error al compartir: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
