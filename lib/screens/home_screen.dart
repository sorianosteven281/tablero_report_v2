import 'package:flutter/material.dart';
import '../models/panel.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import 'inspection_screen.dart';
import 'history_screen.dart';
import 'map_screen.dart';
import 'area_map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locService = LocationService();
  final SettingsService _settingsService = SettingsService();
  final TextEditingController _searchController = TextEditingController();

  List<Panel> _allPanels = [];
  List<Panel> _filteredPanels = [];
  bool _isLoading = true;
  String _selectedCategory = 'TODOS';
  GpsResult _currentGps = GpsResult(quality: GpsQuality.indoorNoSignal, label: 'Detectando...');
  String _currentTech = 'Pon tu nombre';
  String _currentCrew = 'Guardia A - Mantenimiento Eléctrico';

  final List<String> _categories = [
    'TODOS',
    'FRENOS (255)',
    'FAJAS (200/220)',
    'MOLIENDA (2110)',
    'PEBBLES (2115)',
    'TÚNEL (2060)',
    'FLOTACIÓN (245)',
    'FILTRADO (280)',
    'HIDROMETALURGIA',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPanels();
    _refreshGps();
  }

  Future<void> _loadSettings() async {
    final tech = await _settingsService.getResponsibleName();
    final crew = await _settingsService.getCrewName();
    if (mounted) {
      setState(() {
        _currentTech = tech;
        _currentCrew = crew;
      });
    }
  }

  void _showSettingsDialog() {
    final techCtrl = TextEditingController(text: _currentTech == 'Pon tu nombre' ? '' : _currentTech);
    final crewCtrl = TextEditingController(text: _currentCrew);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.badge, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Text('Configurar Técnico / Cuadrilla', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: techCtrl,
                decoration: const InputDecoration(
                  labelText: 'Técnico Responsable',
                  hintText: 'Pon tu nombre...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person, color: Color(0xFF0284C7)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: crewCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre de Cuadrilla / Grupo',
                  hintText: 'Ej. Guardia A - Mantenimiento Eléctrico',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.groups, color: Color(0xFF0284C7)),
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
              final newTech = techCtrl.text.trim().isEmpty ? 'Pon tu nombre' : techCtrl.text.trim();
              final newCrew = crewCtrl.text.trim().isEmpty ? 'Guardia A - Mantenimiento Eléctrico' : crewCtrl.text.trim();
              await _settingsService.setResponsibleName(newTech);
              await _settingsService.setCrewName(newCrew);
              if (mounted) {
                setState(() {
                  _currentTech = newTech;
                  _currentCrew = newCrew;
                });
              }
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Técnico actualizado: $newTech')),
              );
            },
            child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddNewPanelDialog() {
    final tagCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'CP');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.add_box_outlined, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Text('Registrar Nuevo Tablero', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tagCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'TAG del Tablero *',
                  hintText: 'Ej. 2110-CP-099',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code, color: Color(0xFF0284C7)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ubicación / Sala Eléctrica *',
                  hintText: 'Ej. Sala Eléctrica 2210-ER-019',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.place, color: Color(0xFF0284C7)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Tablero',
                  hintText: 'CP, FCP, PLC, RIO, MCC...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category, color: Color(0xFF0284C7)),
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
              final tag = tagCtrl.text.trim().toUpperCase();
              final loc = locCtrl.text.trim();
              final type = typeCtrl.text.trim().toUpperCase();

              if (tag.isEmpty || loc.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor completa el TAG y la Ubicación')),
                );
                return;
              }

              final newPanel = Panel(
                tag: tag,
                loc: loc,
                type: type.isEmpty ? 'CP' : type,
                lat: _currentGps.lat,
                lng: _currentGps.lng,
              );

              await _dbService.insertPanel(newPanel);
              await _loadPanels();
              if (mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Tablero $tag agregado exitosamente')),
              );
            },
            child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPanels() async {
    setState(() => _isLoading = true);
    final panels = await _dbService.getAllPanels();
    setState(() {
      _allPanels = panels;
      _applyFilter();
      _isLoading = false;
    });
  }

  Future<void> _refreshGps() async {
    final res = await _locService.getLocation();
    if (mounted) {
      setState(() => _currentGps = res);
    }
  }

  void _applyFilter() {
    final rawQuery = _searchController.text.toLowerCase().trim();
    final cleanQuery = rawQuery.replaceAll('-', '').replaceAll(' ', '');
    final normDigitsQuery = cleanQuery.replaceAll(RegExp(r'0+(?=\d)'), '');

    setState(() {
      _filteredPanels = _allPanels.where((p) {
        final rawTag = p.tag.toLowerCase();
        final cleanTag = rawTag.replaceAll('-', '').replaceAll(' ', '');
        final normDigitsTag = cleanTag.replaceAll(RegExp(r'0+(?=\d)'), '');
        final rawLoc = p.loc.toLowerCase();

        final matchesQuery = rawQuery.isEmpty ||
            rawTag.contains(rawQuery) ||
            cleanTag.contains(cleanQuery) ||
            normDigitsTag.contains(normDigitsQuery) ||
            rawLoc.contains(rawQuery);

        if (!matchesQuery) return false;

        if (_selectedCategory == 'TODOS') return true;
        if (_selectedCategory == 'FRENOS (255)') return p.tag.contains('255');
        if (_selectedCategory == 'FAJAS (200/220)') return p.tag.contains('220') || p.tag.contains('200') || p.tag.contains('210');
        if (_selectedCategory == 'MOLIENDA (2110)') return p.tag.contains('2110');
        if (_selectedCategory == 'PEBBLES (2115)') return p.tag.contains('2115');
        if (_selectedCategory == 'TÚNEL (2060)') return p.tag.contains('2060');
        if (_selectedCategory == 'FLOTACIÓN (245)') return p.tag.contains('245');
        if (_selectedCategory == 'FILTRADO (280)') return p.tag.contains('280') || p.tag.contains('288');
        if (_selectedCategory == 'HIDROMETALURGIA') return p.tag.contains('10331');

        return true;
      }).toList();
    });
  }

  Color _getGpsColor() {
    switch (_currentGps.quality) {
      case GpsQuality.liveFix:
        return Colors.greenAccent;
      case GpsQuality.freshCache:
        return Colors.amberAccent;
      case GpsQuality.indoorNoSignal:
        return Colors.orangeAccent;
      case GpsQuality.disabled:
        return Colors.redAccent;
      case GpsQuality.skipped:
        return Colors.grey;
    }
  }

  IconData _getGpsIcon() {
    switch (_currentGps.quality) {
      case GpsQuality.liveFix:
        return Icons.gps_fixed;
      case GpsQuality.freshCache:
        return Icons.gps_not_fixed;
      case GpsQuality.indoorNoSignal:
        return Icons.roofing;
      case GpsQuality.disabled:
        return Icons.gps_off;
      case GpsQuality.skipped:
        return Icons.location_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 28, errorBuilder: (_, __, ___) => const Icon(Icons.bolt)),
            const SizedBox(width: 10),
            const Text('Tablero Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts),
            tooltip: 'Configurar Técnico / Cuadrilla',
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Mapa por Áreas / Zonas',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AreaMapScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Mapa GPS Satelital',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historial de Reportes',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner indicador de GPS y Técnico
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                // GPS Chip
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: _refreshGps,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _getGpsColor().withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(_getGpsIcon(), color: _getGpsColor(), size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'GPS: ${_currentGps.label}',
                              style: TextStyle(color: _getGpsColor(), fontSize: 11, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.refresh, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Técnico Chip (Clickable para editar)
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _showSettingsDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _currentTech == 'Pon tu nombre' ? const Color(0xFFF59E0B) : const Color(0xFF0284C7).withOpacity(0.5),
                          width: _currentTech == 'Pon tu nombre' ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            color: _currentTech == 'Pon tu nombre' ? const Color(0xFFF59E0B) : const Color(0xFF0284C7),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _currentTech,
                              style: TextStyle(
                                color: _currentTech == 'Pon tu nombre' ? const Color(0xFFF59E0B) : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.edit,
                            size: 12,
                            color: _currentTech == 'Pon tu nombre' ? const Color(0xFFF59E0B) : const Color(0xFF0284C7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Barra de búsqueda rápida
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _applyFilter(),
              decoration: InputDecoration(
                hintText: 'Buscar TAG, número (ej. 055) o área...',
                prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilter();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Chips de categorías de área
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat, style: TextStyle(fontSize: 11, color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold)),
                    selected: isSelected,
                    selectedColor: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF1E293B),
                    checkmarkColor: Colors.black,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = cat;
                        _applyFilter();
                      });
                    },
                  ),
                );
              },
            ),
          ),

          // Contador de resultados
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredPanels.length} tableros disponibles',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Text(
                  'UM Chinalco Toromocho',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          // Lista de tableros
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPanels.isEmpty
                    ? const Center(child: Text('No se encontraron tableros.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _filteredPanels.length,
                        itemBuilder: (context, index) {
                          final panel = _filteredPanels[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            color: const Color(0xFF1E293B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF0F172A),
                                child: Text(
                                  panel.tag.split('-').first.replaceAll(RegExp(r'[^0-9]'), ''),
                                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                panel.tag,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                              ),
                              subtitle: Text(
                                panel.loc,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => InspectionScreen(panel: panel),
                                  ),
                                );
                                _loadSettings();
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0284C7),
        icon: const Icon(Icons.add_circle_outline, color: Colors.white),
        label: const Text('Nuevo Tablero', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        onPressed: _showAddNewPanelDialog,
      ),
    );
  }
}
