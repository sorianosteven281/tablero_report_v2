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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item.panelTag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.cyanAccent)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isOperativo ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isOperativo ? Colors.green : Colors.amber),
                                  ),
                                  child: Text(
                                    item.finalStatus,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isOperativo ? Colors.greenAccent : Colors.amberAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(item.panelLoc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('${item.date} | Resp: ${item.responsible}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
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
                                Text('${allPhotos.length} fotos', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
