import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
// theme toggling removed for home screen only
// import '../providers/theme_provider.dart';
import '../models/medicine.dart';
import 'medicine_detail_screen.dart';
import 'register_medicine_dialog.dart';
import 'report_screen.dart';
import 'audit_screen.dart';
import 'chat_screen.dart';
import 'contact_screen.dart';
import 'trash_screen.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_bottom_nav_bar.dart';
// removed unused import
import 'help_screen.dart';

// route without any transition animation
PageRouteBuilder<T> _noAnimRoute<T>(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Medicine> _filteredMedicines = [];
  int _selectedCategoryIndex = 0;
  int _selectedNavIndex = 0;
  final List<String> _categories = [
    'All',
    'Antibiotics',
    'Cosmetics',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterMedicines);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _filterMedicines();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Filter medicines when provider changes
    _filterMedicines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterMedicines() {
    final query = _searchController.text;
    final selectedCategory = _categories[_selectedCategoryIndex];
    final provider = context.read<PharmacyProvider>();
    setState(() {
      _filteredMedicines = provider.searchMedicines(query).where((medicine) {
        final medCategory = medicine.category ?? 'Others';
        if (selectedCategory == 'All') return true;
        return medCategory == selectedCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // fetch provider once; filtering logic uses it directly
    final pharmacyProvider = context.read<PharmacyProvider>();

    return Scaffold(
      drawer: AppDrawer(
        onRegister: () {
          Navigator.of(context).pop();
          showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (context) => RegisterMedicineDialog(),
          ).then((category) {
            if (category != null && category != 'All') {
              final index = _categories.indexOf(category);
              if (index != -1) {
                setState(() {
                  _selectedCategoryIndex = index;
                });
                _filterMedicines();
              }
            }
          });
        },
        onContact: () {
          Navigator.of(context).pop();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ContactScreen()),
          );
        },
        onTrash: () {
          Navigator.of(context).pop();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TrashScreen()),
          );
        },
        onHelp: () {
          Navigator.of(context).pop();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const HelpScreen()),
          );
        },
      ),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.local_pharmacy, size: 32, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Pharmacy Manager',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        // no actions on this page; theme toggle removed
        actions: [],
        toolbarHeight: 56,
        titleSpacing: 8,
      ),
      body: Column(
        children: [
          // Pharmacy-themed search bar
          Container(
            margin: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search medicines...',
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  color: Color(0xFF007BFF),
                  size: 20,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _filterMedicines();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          // Category buttons
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _categories.map((category) {
                final isSelected =
                    _categories[_selectedCategoryIndex] == category;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategoryIndex = _categories.indexOf(category);
                      });
                      _filterMedicines();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.0),
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isSelected ? Color(0xFF007BFF) : Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: isSelected
                              ? Color(0xFF007BFF)
                              : Colors.grey[300]!,
                          width: 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Color(0xFF007BFF).withAlpha(77),
                                  blurRadius: 3,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        category,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Medicine count indicator
          if (_filteredMedicines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Icon(Icons.inventory_2, color: Color(0xFF28A745), size: 20),
                  SizedBox(width: 8),
                  Text(
                    '${_filteredMedicines.length} medicine${_filteredMedicines.length == 1 ? '' : 's'} available',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _filteredMedicines.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 56,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No medicines found',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Add your first medicine using the Register button',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width > 600 ? 4 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.all(16.0),
                        cacheExtent: 1000, // preload items for smoother scrolling
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16.0,
                          mainAxisSpacing: 16.0,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _filteredMedicines.length,
                        itemBuilder: (context, index) {
                          final medicine = _filteredMedicines[index];
                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    MedicineDetailScreen(medicine: medicine),
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(25),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // Medicine image or placeholder
                                    medicine.imageBytes != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: Image.memory(
                                              medicine.imageBytes!,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(
                                                    0xFFE3F2FD,
                                                  ), // Light blue
                                                  Color(
                                                    0xFFF1F8E9,
                                                  ), // Light green
                                                ],
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.medication,
                                              size: 48,
                                              color: Color(
                                                0xFF007BFF,
                                              ).withAlpha(153),
                                            ),
                                          ),
                                    // Gradient overlay for text readability
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withAlpha(178),
                                          ],
                                          stops: [0.4, 1.0],
                                        ),
                                      ),
                                    ),
                                    // Medicine info overlay
                                    Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          // Medicine name
                                          Text(
                                            medicine.name,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black.withAlpha(
                                                    128,
                                                  ),
                                                  blurRadius: 4,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          SizedBox(height: 8),
                                          // Quantity and price in a row
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              // Quantity indicator
                                              Flexible(
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        medicine.remainingQty >
                                                            10
                                                        ? Color(
                                                            0xFF28A745,
                                                          ).withAlpha(229)
                                                        : medicine.remainingQty >
                                                              0
                                                        ? Colors.orange
                                                              .withAlpha(229)
                                                        : Colors.red.withAlpha(
                                                            229,
                                                          ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.inventory_2,
                                                        size: 12,
                                                        color: Colors.white,
                                                      ),
                                                      SizedBox(width: 2),
                                                      Text(
                                                        '${medicine.remainingQty}',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 4),
                                              // Price
                                              Flexible(
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withAlpha(229),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.attach_money,
                                                        size: 12,
                                                        color: Color(
                                                          0xFF28A745,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${medicine.sellPrice}',
                                                        style: TextStyle(
                                                          color: Colors.black87,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Menu button
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'delete') {
                                            _showDeleteDialog(
                                              context,
                                              medicine,
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.delete,
                                                  size: 18,
                                                  color: Colors.red,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Delete'),
                                              ],
                                            ),
                                          ),
                                        ],
                                        icon: Icon(
                                          Icons.more_vert,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      // register button is rendered inline inside CustomBottomNavBar
      bottomNavigationBar: CustomBottomNavBar(
        pharmacyProvider: pharmacyProvider,
        selectedIndex: _selectedNavIndex,
        onSelect: (i) => setState(() => _selectedNavIndex = i),
        onHome: () => setState(() => _selectedNavIndex = 0),
        onRegister: () {
          showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            builder: (context) => RegisterMedicineDialog(),
          ).then((category) {
            if (category != null && category != 'All') {
              final index = _categories.indexOf(category);
              if (index != -1) {
                setState(() {
                  _selectedCategoryIndex = index;
                });
                _filterMedicines();
              }
            }
          });
        },
        onChat: () {
          Navigator.of(context).push(_noAnimRoute(ChatScreen()));
        },
        onReports: () {
          pharmacyProvider.clearNewReportsNotification();
          Navigator.of(context).push(_noAnimRoute(ReportScreen()));
        },
        onAudit: () {
          Navigator.of(context).push(_noAnimRoute(AuditScreen()));
        },
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Medicine medicine) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Medicine',
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete ${medicine.name}?',
          style: GoogleFonts.montserrat(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: GoogleFonts.montserrat()),
          ),
          TextButton(
            onPressed: () => _deleteMedicine(context, medicine),
            child: Text(
              'Delete',
              style: GoogleFonts.montserrat(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteMedicine(BuildContext context, Medicine medicine) async {
    final navigator = Navigator.of(context);
    await context.read<PharmacyProvider>().deleteMedicine(medicine);
    navigator.pop();
  }
}
