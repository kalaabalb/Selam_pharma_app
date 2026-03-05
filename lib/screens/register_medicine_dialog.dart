import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/pharmacy_provider.dart';
import '../models/medicine.dart';
// Cloudinary upload is handled by SyncService; keep dialog offline-first.

class RegisterMedicineDialog extends StatefulWidget {
  const RegisterMedicineDialog({super.key});

  @override
  RegisterMedicineDialogState createState() => RegisterMedicineDialogState();
}

class RegisterMedicineDialogState extends State<RegisterMedicineDialog>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _totalQtyController = TextEditingController();
  final _buyPriceController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _barcodeController = TextEditingController();

  Uint8List? _imageBytes;
  String _selectedCategory = 'Others';
  bool _isExpanded = false;
  bool _showSuccess = false;
  bool _isLoading = false;
  late AnimationController _successAnimationController;
  late Animation<double> _successAnimation;
  late AnimationController _loadingAnimationController;
  late Animation<double> _loadingAnimation;

  final List<String> _categories = ['Antibiotics', 'Cosmetics', 'Others'];

  // Template and recent items data
  final List<Map<String, dynamic>> _savedTemplates = [];
  final List<Map<String, dynamic>> _recentMedicines = [];

  // UI constants / simple theme tokens local to this dialog
  final Color _primaryBlue = Colors.blue;
  final Color _accentGreen = Colors.green;
  final Color _successColor = Colors.green;
  final double _cornerRadius = 8.0;
  final double _pageScale = 1.0;

  // Simple validity flags used by input borders (kept true by default)
  final bool _isNameValid = true;
  final bool _isQtyValid = true;
  final bool _isBuyPriceValid = true;
  final bool _isSellPriceValid = true;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _successAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _successAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _successAnimationController,
        curve: Curves.easeOutBack,
      ),
    );
    _loadingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadingAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_loadingAnimationController);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalQtyController.dispose();
    _buyPriceController.dispose();
    _sellPriceController.dispose();
    _barcodeController.dispose();
    _successAnimationController.dispose();
    _loadingAnimationController.dispose();
    super.dispose();
  }

  // Format price input to currency (basic implementation)
  String _formatPrice(String value) {
    try {
      final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
      final doubleValue = double.tryParse(cleaned) ?? 0.0;
      final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
      return formatter.format(doubleValue);
    } catch (e) {
      return value;
    }
  }

  double _parsePrice(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _imageBytes = bytes;
        });
      }
    } catch (e) {
      // Show error message for camera/gallery issues
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? 'Camera not available on this device'
                  : 'Failed to access gallery',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Load saved templates and recent items
  void _loadSavedData() {
    // In a real app, this would load from shared preferences or database
    // For demo purposes, we'll initialize with some sample data
    _savedTemplates.addAll([
      {
        'name': 'Paracetamol 500mg',
        'category': 'Antibiotics',
        'buyPrice': 2.50,
        'sellPrice': 5.00,
        'quantity': 100,
      },
      {
        'name': 'Vitamin C 1000mg',
        'category': 'Cosmetics',
        'buyPrice': 8.00,
        'sellPrice': 15.00,
        'quantity': 50,
      },
    ]);

    // Load recent medicines from provider
    final provider = context.read<PharmacyProvider>();
    _recentMedicines.clear();
    // Get first 5 medicines (oldest) for the list
    final allMedicines = provider.medicines;
    if (allMedicines.length > 5) {
      _recentMedicines.addAll(
        allMedicines
            .take(5)
            .map(
              (medicine) => {
                'name': medicine.name,
                'category': medicine.category ?? 'Others',
                'buyPrice': medicine.buyPrice.toDouble(),
                'sellPrice': medicine.sellPrice.toDouble(),
                'quantity': medicine.totalQty,
              },
            ),
      );
    } else {
      _recentMedicines.addAll(
        allMedicines.map(
          (medicine) => {
            'name': medicine.name,
            'category': medicine.category ?? 'Others',
            'buyPrice': medicine.buyPrice.toDouble(),
            'sellPrice': medicine.sellPrice.toDouble(),
            'quantity': medicine.totalQty,
          },
        ),
      );
    }
  }

  // Apply template data to form
  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      _nameController.text = template['name'];
      _selectedCategory = template['category'];
      _buyPriceController.text = _formatPrice(template['buyPrice'].toString());
      _sellPriceController.text = _formatPrice(
        template['sellPrice'].toString(),
      );
      _totalQtyController.text = template['quantity'].toString();
    });
  }

  // Save current form as template
  void _saveAsTemplate() {
    if (_nameController.text.isNotEmpty) {
      final template = {
        'name': _nameController.text,
        'category': _selectedCategory,
        'buyPrice':
            double.tryParse(
              _buyPriceController.text.replaceAll('₹', '').replaceAll(',', ''),
            ) ??
            0.0,
        'sellPrice':
            double.tryParse(
              _sellPriceController.text.replaceAll('₹', '').replaceAll(',', ''),
            ) ??
            0.0,
        'quantity': int.tryParse(_totalQtyController.text) ?? 1,
      };

      setState(() {
        _savedTemplates.add(template);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Template saved successfully!'),
          backgroundColor: _successColor,
        ),
      );
    }
  }

  // Scan barcode and auto-fill medicine details
  Future<void> _scanBarcode() async {
    // Get provider before async operations
    final provider = context.read<PharmacyProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Request camera permission
    var status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Camera permission is required for barcode scanning'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Show scanner dialog
      final result = await showDialog<String>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            height: 400,
            child: MobileScanner(
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final barcode = barcodes.first.rawValue;
                  if (barcode != null) {
                    Navigator.of(context).pop(barcode);
                  }
                }
              },
            ),
          ),
        ),
      );

      if (result != null) {
        // Lookup medicine by barcode
        final medicine = provider.findMedicineByBarcode(result);

        if (medicine != null) {
          // Auto-fill fields
          setState(() {
            _nameController.text = medicine.name;
            _totalQtyController.text = medicine.totalQty.toString();
            _buyPriceController.text = medicine.buyPrice.toString();
            _sellPriceController.text = medicine.sellPrice.toString();
            _selectedCategory = medicine.category ?? 'Others';
            _imageBytes = medicine.imageBytes;
            _barcodeController.text = medicine.barcode ?? '';
          });

          messenger.showSnackBar(
            SnackBar(
              content: Text('Medicine "${medicine.name}" loaded from barcode'),
              backgroundColor: _accentGreen,
            ),
          );
        } else {
          // Set barcode for new medicine
          setState(() {
            _barcodeController.text = result;
          });
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Barcode scanned. Please enter medicine details.'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Scanning failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _registerMedicine() async {
    if (_formKey.currentState!.validate()) {
      final provider = context.read<PharmacyProvider>();

      // Check if medicine already exists
      final medicineName = _nameController.text.trim().toLowerCase();
      final existingMedicine = provider.medicines.any(
        (medicine) => medicine.name.toLowerCase() == medicineName,
      );

      if (existingMedicine) {
        // Show alert dialog for existing medicine
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Medicine Already Exists'),
              content: const Text(
                'This medicine is already registered in the system.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      // Simulate processing time
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      final medicine = Medicine(
        id: Uuid().v4(),
        name: _nameController.text.trim(),
        totalQty: int.parse(_totalQtyController.text),
        buyPrice: _parsePrice(_buyPriceController.text).round(),
        sellPrice: _parsePrice(_sellPriceController.text).round(),
        imageBytes: _imageBytes,
        category: _selectedCategory,
        barcode: _barcodeController.text.isNotEmpty
            ? _barcodeController.text
            : null,
      );

      // Always save image bytes locally first so the app works offline.
      // The SyncService will upload images and sync to Firestore when
      // network/auth conditions allow.
      if (_imageBytes != null) {
        medicine.imageBytes = _imageBytes;
      }
      medicine.lastModifiedMillis = DateTime.now().millisecondsSinceEpoch;

      await provider.addMedicine(medicine);
      if (!mounted) return;

      // Add to recent items
      final recentItem = {
        'name': medicine.name,
        'category': medicine.category,
        'buyPrice': medicine.buyPrice.toDouble(),
        'sellPrice': medicine.sellPrice.toDouble(),
        'quantity': medicine.totalQty,
      };
      setState(() {
        _recentMedicines.add(recentItem);
        if (_recentMedicines.length > 5) {
          // keep first five entries; drop newest extra
          _recentMedicines.removeLast();
        }
        _isLoading = false;
        _showSuccess = true;
      });

      _successAnimationController.forward();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Medicine registered successfully!'),
          backgroundColor: _successColor,
        ),
      );

      // Close dialog after animation
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          Navigator.of(context).pop(_selectedCategory);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          // allow full width so nothing is clipped; minimum constraints are handled by padding and natural content
          maxWidth: screenWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + s(10),
                left: s(6),
                right: s(6),
                top: s(8),
              ),
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: s(8)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header: single row with title centered between left and right groups
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, size: 24),
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            style: IconButton.styleFrom(
                              foregroundColor: _primaryBlue,
                            ),
                            tooltip: 'Close',
                          ),

                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Register Medicine',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _primaryBlue,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(
                            width: 120,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    child: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'save') {
                                          _saveAsTemplate();
                                        } else if (value.startsWith(
                                          'template_',
                                        )) {
                                          final parts = value.split('_');
                                          final idx =
                                              int.tryParse(parts[1]) ?? -1;
                                          if (idx >= 0 &&
                                              idx < _savedTemplates.length) {
                                            _applyTemplate(
                                              _savedTemplates[idx],
                                            );
                                          }
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'save',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.save,
                                                color: _primaryBlue,
                                              ),
                                              SizedBox(width: s(4)),
                                              Text('Save as Template'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        ..._savedTemplates.asMap().entries.map((
                                          entry,
                                        ) {
                                          final index = entry.key;
                                          final template = entry.value;
                                          return PopupMenuItem(
                                            value: 'template_$index',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.bookmark,
                                                  color: _accentGreen,
                                                ),
                                                SizedBox(width: s(4)),
                                                Expanded(
                                                  child: Text(
                                                    template['name'] ??
                                                        'Unknown',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                      icon: Icon(
                                        Icons.more_vert,
                                        color: _primaryBlue,
                                        size: 16,
                                      ),
                                      tooltip: 'Templates & options',
                                    ),
                                  ),
                                  SizedBox(width: s(2)),
                                  IconButton(
                                    onPressed: () => setState(
                                      () => _isExpanded = !_isExpanded,
                                    ),
                                    icon: Icon(
                                      _isExpanded
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      color: _primaryBlue,
                                      size: 18,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    tooltip: _isExpanded
                                        ? 'Exit full screen'
                                        : 'Full screen mode',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spLarge()),

                      // Templates Section (accessed via popup menu)
                      SizedBox(height: spLarge()),

                      // Recent Items Section (only show if has recent items)
                      if (_recentMedicines.isNotEmpty)
                        _buildRecentItemsSection(),

                      SizedBox(height: spLarge()),

                      // Basic Information Section
                      _buildSectionCard(
                        title: 'Basic Information',
                        icon: Icons.info_outline,
                        children: [
                          // Medicine Name - Prominent field
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                vertical: s(10),
                                horizontal: s(8),
                              ),
                              labelText: 'Medicine Name *',
                              labelStyle: TextStyle(fontSize: 12),
                              hintText: 'Enter medicine name',

                              prefixIcon: const Icon(Icons.medication),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: _isNameValid
                                      ? Colors.grey
                                      : Colors.red,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: _isNameValid
                                      ? Colors.grey
                                      : Colors.red,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textCapitalization: TextCapitalization.words,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Medicine name is required';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: spMed()),

                          // Category
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            isDense: false,
                            initialValue: _selectedCategory,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                vertical: s(10),
                                horizontal: s(8),
                              ),
                              labelText: 'Category *',
                              hintText: 'Select medicine category',

                              prefixIcon: const Icon(Icons.category),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            dropdownColor: Colors.white,
                            items: _categories.map((category) {
                              return DropdownMenuItem(
                                value: category,
                                child: Text(
                                  category,
                                  style: TextStyle(color: Colors.black87),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedCategory = value!;
                              });
                            },
                            validator: (value) => value == null
                                ? 'Please select a category'
                                : null,
                          ),
                          SizedBox(height: spMed()),

                          // Barcode (optional, shown when scanned or entered)
                          TextFormField(
                            controller: _barcodeController,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                vertical: s(10),
                                horizontal: s(8),
                              ),
                              labelText: 'Barcode',
                              labelStyle: TextStyle(fontSize: 12),
                              hintText: 'Scan or enter barcode',

                              prefixIcon: const Icon(Icons.qr_code),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: _scanBarcode,
                                tooltip: 'Scan Barcode',
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: s(8)),

                      // Inventory Section
                      _buildSectionCard(
                        title: 'Inventory',
                        icon: Icons.inventory_2,
                        children: [
                          // Quantity with increment/decrement
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Quantity *',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                              SizedBox(height: s(6)),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: _decrementQuantity,
                                    icon: const Icon(Icons.remove, size: 14),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).primaryColor.withValues(alpha: 0.1),
                                      minimumSize: const Size(40, 40),
                                    ),
                                  ),
                                  SizedBox(width: s(4)),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _totalQtyController,
                                      decoration: InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: s(8),
                                          horizontal: s(8),
                                        ),
                                        hintText: 'Enter quantity',

                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            _cornerRadius,
                                          ),
                                          borderSide: BorderSide(
                                            color: _isQtyValid
                                                ? Colors.grey
                                                : Colors.red,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            _cornerRadius,
                                          ),
                                          borderSide: BorderSide(
                                            color: _isQtyValid
                                                ? Colors.grey
                                                : Colors.red,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            _cornerRadius,
                                          ),
                                          borderSide: BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      style: TextStyle(fontSize: 14),
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Quantity is required';
                                        }
                                        final qty = int.tryParse(value);
                                        if (qty == null || qty <= 0) {
                                          return 'Enter a valid quantity';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  SizedBox(width: s(4)),
                                  IconButton(
                                    onPressed: _incrementQuantity,
                                    icon: const Icon(Icons.add, size: 14),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).primaryColor.withValues(alpha: 0.1),
                                      minimumSize: const Size(40, 40),
                                    ),
                                    tooltip: 'Increase quantity',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),

                      SizedBox(height: s(8)),

                      // Pricing Section
                      _buildSectionCard(
                        title: 'Pricing',
                        icon: Icons.attach_money,
                        children: [
                          // Buy Price
                          TextFormField(
                            controller: _buyPriceController,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                vertical: s(10),
                                horizontal: s(8),
                              ),
                              labelText: 'Buy Price (per unit) *',
                              labelStyle: TextStyle(fontSize: 12),
                              hintText: '₹0.00',

                              prefixIcon: const Icon(Icons.shopping_cart),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: _isBuyPriceValid
                                      ? Colors.grey
                                      : Colors.red,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: _isBuyPriceValid
                                      ? Colors.grey
                                      : Colors.red,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            style: TextStyle(fontSize: 14),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.₹,]'),
                              ),
                            ],
                            onChanged: (value) {
                              final formatted = _formatPrice(value);
                              if (formatted != value) {
                                _buyPriceController.value = TextEditingValue(
                                  text: formatted,
                                  selection: TextSelection.collapsed(
                                    offset: formatted.length,
                                  ),
                                );
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Buy price is required';
                              }
                              final price = double.tryParse(
                                value.replaceAll('₹', '').replaceAll(',', ''),
                              );
                              if (price == null || price <= 0) {
                                return 'Enter a valid price';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: spMed()),

                          // Sell Price
                          TextFormField(
                            controller: _sellPriceController,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                vertical: s(10),
                                horizontal: s(8),
                              ),
                              labelText: 'Sell Price (per unit) *',
                              labelStyle: const TextStyle(fontSize: 12),
                              hintText: '₹0.00',

                              prefixIcon: const Icon(Icons.sell),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: _isSellPriceValid
                                      ? Colors.grey
                                      : Colors.red,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: _isSellPriceValid
                                      ? Colors.grey
                                      : Colors.red,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                                borderSide: BorderSide(
                                  color: Theme.of(context).primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            style: TextStyle(fontSize: 14),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.₹,]'),
                              ),
                            ],
                            onChanged: (value) {
                              final formatted = _formatPrice(value);
                              if (formatted != value) {
                                _sellPriceController.value = TextEditingValue(
                                  text: formatted,
                                  selection: TextSelection.collapsed(
                                    offset: formatted.length,
                                  ),
                                );
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Sell price is required';
                              }
                              final price = double.tryParse(
                                value.replaceAll('₹', '').replaceAll(',', ''),
                              );
                              if (price == null || price <= 0) {
                                return 'Enter a valid price';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),

                      SizedBox(height: spLarge()),

                      // Media Section
                      _buildSectionCard(
                        title: 'Media',
                        icon: Icons.photo_camera,
                        children: [
                          // Image picker buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _pickImage(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt, size: 14),
                                  label: const Text('Camera'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    minimumSize: const Size(0, 40),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        _cornerRadius,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: s(4)),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _pickImage(ImageSource.gallery),
                                  icon: const Icon(
                                    Icons.photo_library,
                                    size: 14,
                                  ),
                                  label: const Text('Gallery'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    minimumSize: const Size(0, 40),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        _cornerRadius,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Image preview
                          if (_imageBytes != null) ...[
                            SizedBox(height: spMed()),
                            Center(
                              child: Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    _cornerRadius,
                                  ),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    _cornerRadius,
                                  ),
                                  child: Image.memory(
                                    _imageBytes!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: s(24)),

                      // Register Button
                      AnimatedBuilder(
                        animation: _loadingAnimation,
                        builder: (context, child) {
                          return ElevatedButton(
                            onPressed: _isLoading ? null : _registerMedicine,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  _cornerRadius,
                                ),
                              ),
                              elevation: _isLoading ? 0 : 2,
                              backgroundColor: _isLoading
                                  ? Colors.grey
                                  : _primaryBlue,
                            ),
                            child: _isLoading
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                _primaryBlue,
                                              ),
                                        ),
                                      ),
                                      SizedBox(width: s(4)),
                                      const Text(
                                        'Registering...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    'Register Medicine',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          );
                        },
                      ),

                      SizedBox(height: spMed()),
                    ],
                  ),
                ),
              ),
            ),

            // Success overlay
            if (_showSuccess)
              AnimatedBuilder(
                animation: _successAnimation,
                builder: (context, child) {
                  return Container(
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Center(
                      child: Transform.scale(
                        scale: _successAnimation.value,
                        child: Container(
                          padding: EdgeInsets.all(s(8)),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: s(36),
                              ),
                              SizedBox(height: spSmall()),
                              Text(
                                'Medicine Registered!',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                              ),
                              SizedBox(height: s(8)),
                              Text(
                                'Successfully added to inventory',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.grey[600]),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // Convenient helper to scale spacings/paddings/radii within this page.
  double s(double value) => value * _pageScale;

  double spLarge() => s(18);
  double spMed() => s(10);
  double spSmall() => s(6);

  void _decrementQuantity() {
    final current = int.tryParse(_totalQtyController.text) ?? 1;
    final updated = (current > 1) ? current - 1 : 1;
    setState(() {
      _totalQtyController.text = updated.toString();
    });
  }

  void _incrementQuantity() {
    final current = int.tryParse(_totalQtyController.text) ?? 0;
    final updated = current + 1;
    setState(() {
      _totalQtyController.text = updated.toString();
    });
  }

  Widget _buildRecentItemsSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cornerRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(s(2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: _primaryBlue, size: 16),
                SizedBox(width: s(4)),
                Flexible(
                  child: Text(
                    'Recent Items',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: s(4)),
            SizedBox(
              height: 88,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _recentMedicines.length,
                itemBuilder: (context, index) {
                  final item = _recentMedicines[index];
                  return GestureDetector(
                    onTap: () => _applyTemplate(item),
                    child: Container(
                      width: 140,
                      margin: EdgeInsets.only(right: s(4)),
                      padding: EdgeInsets.all(s(2)),
                      decoration: BoxDecoration(
                        color: _primaryBlue.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(_cornerRadius),
                        border: Border.all(
                          color: _primaryBlue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'] ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: spSmall()),
                          Text(
                            item['category'] ?? 'Others',
                            style: TextStyle(fontSize: 10, color: _primaryBlue),
                          ),
                          SizedBox(height: spSmall()),
                          Text(
                            '₹${item['sellPrice'] ?? 0.0}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cornerRadius),
      ),
      child: Padding(
        padding: EdgeInsets.all(s(2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _primaryBlue, size: 16),
                SizedBox(width: s(4)),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: s(4)),
            ...children,
          ],
        ),
      ),
    );
  }
}
