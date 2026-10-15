import 'package:flutter/material.dart';
import '../models/panel.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import 'inspection_screen.dart';
import 'history_screen.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _dbService = DatabaseService();
  final LocationService _locService = LocationService();
  final TextEditingController _searchController = TextEditingController();

  List<Panel> _allPanels = [];
  List<Panel> _filteredPanels = [];
  bool _isLoading = true;
  String _selectedCategory = 'TODOS';
  GpsResult _currentGps = GpsResult(quality: GpsQuality.indoorNoSignal, label: 'Detectando...');

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
    _loadPanels();
    _refreshGps();
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
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredPanels = _allPanels.where((p) {
        final matchesQuery = query.isEmpty ||
            p.tag.toLowerCase().contains(query) ||
            p.loc.toLowerCase().contains(query);

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
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Mapa de Tableros',
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
          // Banner indicador de GPS en vivo
          GestureDetector(
            onTap: _refreshGps,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _getGpsColor().withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(_getGpsIcon(), color: _getGpsColor(), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GPS: ${_currentGps.label}',
                      style: TextStyle(color: _getGpsColor(), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.refresh, size: 16, color: Colors.grey),
                ],
              ),
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
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => InspectionScreen(panel: panel),
                                  ),
                                );
                              },
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
