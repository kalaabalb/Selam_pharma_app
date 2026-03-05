import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../models/medicine.dart';
import '../models/report.dart';
import '../utils/ui_helpers.dart';

class MedicineDetailScreen extends StatefulWidget {
  final Medicine medicine;

  const MedicineDetailScreen({required this.medicine, super.key});

  @override
  MedicineDetailScreenState createState() => MedicineDetailScreenState();
}

class MedicineDetailScreenState extends State<MedicineDetailScreen> {
  final _soldQtyController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _restockQtyController = TextEditingController();
  final _restockBuyPriceController = TextEditingController();
  final _restockSellPriceController = TextEditingController();
  late Medicine _currentMedicine;
  List<Report> _medicineReports = [];
  double _profitMargin = 0.0;
  int _breakEvenUnits = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_medicineReports.isEmpty) {
      _loadMedicineReports();
    }
  }

  @override
  void initState() {
    super.initState();
    _currentMedicine = widget.medicine;
    _sellPriceController.text = widget.medicine.sellPrice.toString();
    _soldQtyController.clear(); // Reset quantity field for new sale
    _calculateAnalytics();
    // make sure provider data is fresh (includes Firestore sync)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<PharmacyProvider>().loadData();
      } catch (_) {}
    });
  }

  void _loadMedicineReports() {
    final provider = context.read<PharmacyProvider>();
    _medicineReports =
        provider.reports
            .where((report) => report.medicineName == _currentMedicine.name)
            .toList()
          ..sort(
            (a, b) => b.dateTime.compareTo(a.dateTime),
          ); // Most recent first
  }

  void _calculateAnalytics() {
    // Profit per unit (gain for each sold medicine)
    _profitMargin = (_currentMedicine.sellPrice - _currentMedicine.buyPrice)
        .toDouble();

    // Break-even units: Total cost divided by sell price per unit
    if (_currentMedicine.sellPrice > 0) {
      _breakEvenUnits =
          (_currentMedicine.totalQty * _currentMedicine.buyPrice) ~/
          _currentMedicine.sellPrice;
    }
  }

  void _showRestockDialog() {
    _restockQtyController.text = _currentMedicine.totalQty.toString();
    _restockBuyPriceController.text = _currentMedicine.buyPrice.toString();
    _restockSellPriceController.text = _currentMedicine.sellPrice.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Restock Medicine',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _restockQtyController,
              decoration: InputDecoration(
                labelText: 'New Quantity',
                labelStyle: GoogleFonts.montserrat(fontSize: 12),
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              style: GoogleFonts.montserrat(fontSize: 12),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _restockBuyPriceController,
              decoration: InputDecoration(
                labelText: 'New Buy Price',
                labelStyle: GoogleFonts.montserrat(fontSize: 12),
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              style: GoogleFonts.montserrat(fontSize: 12),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _restockSellPriceController,
              decoration: InputDecoration(
                labelText: 'New Sell Price',
                labelStyle: GoogleFonts.montserrat(fontSize: 12),
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              style: GoogleFonts.montserrat(fontSize: 12),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: GoogleFonts.montserrat(fontSize: 12),
            ),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newQty =
                  int.tryParse(_restockQtyController.text) ??
                  _currentMedicine.totalQty;
              final newBuyPrice =
                  int.tryParse(_restockBuyPriceController.text) ??
                  _currentMedicine.buyPrice;
              final newSellPrice =
                  int.tryParse(_restockSellPriceController.text) ??
                  _currentMedicine.sellPrice;

              setState(() {
                _currentMedicine.totalQty = newQty;
                _currentMedicine.buyPrice = newBuyPrice;
                _currentMedicine.sellPrice = newSellPrice;
                _currentMedicine.soldQty = 0; // Reset sold quantity
                _sellPriceController.text = newSellPrice.toString();
              });

              _calculateAnalytics();

              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final provider = context.read<PharmacyProvider>();
              await provider.updateMedicine(_currentMedicine);

              // Clear historical reports for this medicine so analytics start at 0
              // after a restock (user requested Total Revenue and Real Profit
              // to reset to zero on restock).
              try {
                await provider.removeReportsForMedicine(_currentMedicine.name);
              } catch (_) {}

              // Reload reports and refresh analytics/UI immediately.
              setState(() {
                _loadMedicineReports();
                _calculateAnalytics();
              });

              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Medicine restocked successfully'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text('Restock', style: GoogleFonts.montserrat(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog() {
    final nameController = TextEditingController(text: _currentMedicine.name);
    _restockQtyController.text = _currentMedicine.totalQty.toString();
    _restockBuyPriceController.text = _currentMedicine.buyPrice.toString();
    _restockSellPriceController.text = _currentMedicine.sellPrice.toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Update Medicine',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Medicine Name',
                labelStyle: GoogleFonts.montserrat(fontSize: 12),
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              style: GoogleFonts.montserrat(fontSize: 12),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _restockQtyController,
              decoration: InputDecoration(
                labelText: 'Quantity',
                labelStyle: GoogleFonts.montserrat(fontSize: 12),
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              style: GoogleFonts.montserrat(fontSize: 12),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _restockBuyPriceController,
              decoration: InputDecoration(
                labelText: 'Buy Price',
                labelStyle: GoogleFonts.montserrat(fontSize: 12),
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              style: GoogleFonts.montserrat(fontSize: 12),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _restockSellPriceController,
              decoration: InputDecoration(
                labelText: 'Sell Price',
                labelStyle: GoogleFonts.montserrat(fontSize: 12),
                hintStyle: GoogleFonts.montserrat(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              style: GoogleFonts.montserrat(fontSize: 12),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: GoogleFonts.montserrat(fontSize: 12),
            ),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newQty =
                  int.tryParse(_restockQtyController.text) ??
                  _currentMedicine.totalQty;
              final newBuyPrice =
                  int.tryParse(_restockBuyPriceController.text) ??
                  _currentMedicine.buyPrice;
              final newSellPrice =
                  int.tryParse(_restockSellPriceController.text) ??
                  _currentMedicine.sellPrice;

              setState(() {
                _currentMedicine.name = newName.isNotEmpty
                    ? newName
                    : _currentMedicine.name;
                _currentMedicine.totalQty = newQty;
                _currentMedicine.soldQty =
                    0; // Reset sold quantity when updating total
                _currentMedicine.buyPrice = newBuyPrice;
                _currentMedicine.sellPrice = newSellPrice;
                _sellPriceController.text = newSellPrice.toString();
              });

              _calculateAnalytics();

              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final provider = context.read<PharmacyProvider>();
              await provider.updateMedicine(_currentMedicine);
              // Reload reports with the new medicine name
              _loadMedicineReports();

              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Medicine updated successfully')),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text('Update', style: GoogleFonts.montserrat(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.montserrat(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildAnalyticsCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitTrendChart() {
    // Calculate profit for last 7 days
    final now = DateTime.now();
    final last7Days = List.generate(
      7,
      (index) => now.subtract(Duration(days: 6 - index)),
    );

    final profitData = last7Days.map((date) {
      final dayReports = _medicineReports.where(
        (report) =>
            report.dateTime.year == date.year &&
            report.dateTime.month == date.month &&
            report.dateTime.day == date.day,
      );
      return dayReports.fold<double>(
        0,
        (sum, report) => sum + report.totalGain,
      );
    }).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < 7) {
                  return Text(
                    DateFormat('E').format(last7Days[index]),
                    style: GoogleFonts.montserrat(fontSize: 10),
                  );
                }
                return const Text('');
              },
              reservedSize: 22,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.montserrat(fontSize: 10),
                );
              },
              reservedSize: 28,
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: profitData
                .asMap()
                .entries
                .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
                .toList(),
            isCurved: true,
            color: Colors.green,
            barWidth: 3,
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.1),
            ),
            dotData: FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesChart() {
    // Calculate sales volume for last 7 days
    final now = DateTime.now();
    final last7Days = List.generate(
      7,
      (index) => now.subtract(Duration(days: 6 - index)),
    );

    final salesData = last7Days.map((date) {
      final dayReports = _medicineReports.where(
        (report) =>
            report.dateTime.year == date.year &&
            report.dateTime.month == date.month &&
            report.dateTime.day == date.day,
      );
      return dayReports.fold<int>(0, (sum, report) => sum + report.soldQty);
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: salesData.isNotEmpty
            ? salesData.reduce((a, b) => a > b ? a : b).toDouble() * 1.2
            : 10,
        barGroups: salesData.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.toDouble(),
                color: Theme.of(context).colorScheme.primary,
                width: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }).toList(),
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < 7) {
                  return Text(
                    DateFormat('E').format(last7Days[index]),
                    style: GoogleFonts.montserrat(fontSize: 10),
                  );
                }
                return const Text('');
              },
              reservedSize: 22,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  meta.formattedValue,
                  style: GoogleFonts.montserrat(fontSize: 10),
                );
              },
              reservedSize: 28,
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  void _addToReport() async {
    final soldQty = int.tryParse(_soldQtyController.text) ?? 0;
    final sellPrice =
        int.tryParse(_sellPriceController.text) ?? _currentMedicine.sellPrice;

    if (soldQty > 0 &&
        soldQty <= _currentMedicine.remainingQty &&
        sellPrice > 0) {
      final totalGain = soldQty * sellPrice;
      final report = Report(
        medicineName: _currentMedicine.name,
        soldQty: soldQty,
        sellPrice: sellPrice,
        totalGain: totalGain,
        dateTime: DateTime.now(),
      );

      final provider = context.read<PharmacyProvider>();
      try {
        await provider.addReport(report);
      } catch (e) {
        if (mounted) {
          showAppSnackBar(context, 'Failed to add report: $e', error: true);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _currentMedicine.soldQty += soldQty;
        });
      }
      provider.updateMedicine(_currentMedicine);

      // Refetch updated medicine to ensure UI reflects changes
      try {
        _currentMedicine = provider.medicines.firstWhere(
          (m) => m.id == _currentMedicine.id,
        );
      } catch (e) {
        if (mounted) {
          if (mounted) {
            showAppSnackBar(
              context,
              'Failed to update medicine: $e',
              error: true,
            );
          }
        }
        return;
      }

      if (mounted) {
        setState(() {
          _loadMedicineReports(); // Reload reports to update total revenue and chart
        });
      }

      if (mounted) {
        showAppSnackBar(context, 'Sale added to report');
      }

      _soldQtyController.clear();
      _sellPriceController.clear();
    } else {
      String errorMessage = 'Invalid input';
      if (soldQty <= 0) {
        errorMessage = 'Quantity must be greater than 0';
      } else if (soldQty > _currentMedicine.remainingQty) {
        errorMessage = 'Not enough stock available';
      } else if (sellPrice <= 0) {
        errorMessage = 'Price must be greater than 0';
      }
      if (mounted) {
        showAppSnackBar(context, errorMessage, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final hintColor = theme.hintColor;

    // recompute reports each time we rebuild so remote sync updates take effect
    final providerReports = context.watch<PharmacyProvider>().reports;
    _medicineReports =
        providerReports
            .where((r) => r.medicineName == _currentMedicine.name)
            .toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final double realProfit =
        _medicineReports.fold<double>(
          0,
          (sum, report) => sum + report.totalGain,
        ) -
        (_currentMedicine.soldQty * _currentMedicine.buyPrice);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentMedicine.name,
          style: GoogleFonts.montserrat(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.appBarTheme.titleTextStyle?.color,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_currentMedicine.remainingQty == 0)
            Card(
              color: theme.colorScheme.errorContainer,
              margin: const EdgeInsets.all(16.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.error, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.error,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Out of Stock Alert!',
                            style: GoogleFonts.montserrat(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Medicine: ${_currentMedicine.name}\n'
                      'Total Sold: ${_currentMedicine.soldQty}\n'
                      'Profit: ${realProfit.toStringAsFixed(0)} Birr',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _showRestockDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        child: Text(
                          'Restock',
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top info card with image and key details
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          // Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _currentMedicine.imageBytes != null
                                ? Image.memory(
                                    _currentMedicine.imageBytes!,
                                    width: 110,
                                    height: 110,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 120,
                                    height: 120,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.08),
                                    child: Icon(
                                      Icons.medical_services,
                                      size: 48,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                          ),
                          SizedBox(width: 12),
                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentMedicine.name,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _buildBadge(
                                      'Remaining',
                                      '${_currentMedicine.remainingQty}',
                                    ),
                                    _buildBadge(
                                      'Total',
                                      '${_currentMedicine.totalQty}',
                                    ),
                                    _buildBadge(
                                      'Buy',
                                      '${_currentMedicine.buyPrice}',
                                    ),
                                    _buildBadge(
                                      'Sell',
                                      '${_currentMedicine.sellPrice}',
                                    ),
                                  ],
                                ),
                                if (_currentMedicine.remainingQty == 0) ...[
                                  SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (realProfit >= 0
                                                  ? Colors.green
                                                  : Colors.red)
                                              .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Profit: ${realProfit.toStringAsFixed(0)} Birr',
                                      style: GoogleFonts.montserrat(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: realProfit >= 0
                                            ? Colors.green[700]
                                            : Colors.red[700],
                                      ),
                                    ),
                                  ),
                                ],
                                SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _showUpdateDialog,
                                      icon: Icon(Icons.edit, size: 16),
                                      label: Text(
                                        'Edit',
                                        style: GoogleFonts.montserrat(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onPrimary,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // Financial Analytics Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.analytics,
                                color: theme.colorScheme.primary,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Financial Analytics',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildAnalyticsCard(
                                  'Profit per Unit',
                                  '${_profitMargin.toStringAsFixed(0)} Birr',
                                  Icons.trending_up,
                                  _profitMargin >= 0
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: _buildAnalyticsCard(
                                  'Units to Recover Cost',
                                  _breakEvenUnits.toString(),
                                  Icons.balance,
                                  Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildAnalyticsCard(
                                  'Total Revenue',
                                  '${_medicineReports.fold<double>(0, (sum, report) => sum + report.totalGain)} Birr',
                                  Icons.attach_money,
                                  Colors.green,
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: _buildAnalyticsCard(
                                  'Total Cost',
                                  '${(_currentMedicine.remainingQty * _currentMedicine.buyPrice)} Birr',
                                  Icons.money_off,
                                  Colors.red,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildAnalyticsCard(
                                  'Real Profit',
                                  '${(_medicineReports.fold<double>(0, (sum, report) => sum + report.totalGain) - (_currentMedicine.soldQty * _currentMedicine.buyPrice)).toStringAsFixed(0)} Birr',
                                  Icons.account_balance_wallet,
                                  (_medicineReports.fold<double>(
                                                0,
                                                (sum, report) =>
                                                    sum + report.totalGain,
                                              ) -
                                              (_currentMedicine.soldQty *
                                                  _currentMedicine.buyPrice)) >=
                                          0
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Profit Trend (Last 7 Days)',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: 12),
                          SizedBox(
                            height: 150,
                            child: _buildProfitTrendChart(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // Sales History Card
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history,
                                color: theme.colorScheme.primary,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Recent Sales',
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          _medicineReports.isEmpty
                              ? Center(
                                  child: Text(
                                    'No sales recorded yet',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 12,
                                      color: hintColor,
                                    ),
                                  ),
                                )
                              : Column(
                                  children: [
                                    SizedBox(
                                      height: 200,
                                      child: ListView.builder(
                                        itemCount: _medicineReports.length > 10
                                            ? 10
                                            : _medicineReports.length,
                                        itemBuilder: (context, index) {
                                          final report =
                                              _medicineReports[index];
                                          return ListTile(
                                            dense: true,
                                            leading: CircleAvatar(
                                              backgroundColor: theme
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.1),
                                              child: Text(
                                                '${index + 1}',
                                                style: GoogleFonts.montserrat(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                            title: Text(
                                              DateFormat(
                                                'MMM dd, yyyy HH:mm',
                                              ).format(report.dateTime),
                                              style: GoogleFonts.montserrat(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            subtitle: Text(
                                              'Qty: ${report.soldQty} × ${report.sellPrice} Birr',
                                              style: GoogleFonts.montserrat(
                                                fontSize: 10,
                                                color: hintColor,
                                              ),
                                            ),
                                            trailing: Text(
                                              '${report.totalGain} Birr',
                                              style: GoogleFonts.montserrat(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.green,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Sales Chart (Last 7 Days)',
                                      style: GoogleFonts.montserrat(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    SizedBox(
                                      height: 150,
                                      child: _buildSalesChart(),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // Additional info card (can expand later)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Details',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No extra details available.',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12.0),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _soldQtyController,
                        decoration: InputDecoration(
                          labelText: 'Quantity',
                          labelStyle: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: hintColor,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                        ),
                        style: GoogleFonts.montserrat(fontSize: 12),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        controller: _sellPriceController,
                        decoration: InputDecoration(
                          labelText: 'Price',
                          labelStyle: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: hintColor,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                        ),
                        style: GoogleFonts.montserrat(fontSize: 12),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addToReport,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      'Add to Report',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
