import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';

const Color _teal = Color(0xFF008080); // Teal Green

class UserProfileCard extends StatelessWidget {
  final String name;
  final String phoneNumber;
  final VoidCallback? onEdit;

  const UserProfileCard({
    super.key,
    required this.name,
    required this.phoneNumber,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cardBg(context),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Photo Box / Avatar
            Stack(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 40,
                    color: _teal,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: _teal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // User Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : 'Tap to add your name',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        phoneNumber.isNotEmpty ? phoneNumber : 'No phone number',
                        style: TextStyle(
                          fontSize: 13,
                          color: mutedText(context),
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
    );
  }
}

/// One bet. status: pending, won, lost, void.
class Bet {
  final int id;
  final String date; // ISO string
  final String description;
  final double stake;
  final double odds;
  String status;

  Bet({
    required this.id,
    required this.date,
    required this.description,
    required this.stake,
    required this.odds,
    this.status = 'pending',
  });

  /// Profit or loss once settled (a pending stake is not counted yet).
  double get profit {
    if (status == 'won') return stake * (odds - 1);
    if (status == 'lost') return -stake;
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'description': description,
        'stake': stake,
        'odds': odds,
        'status': status,
      };

  factory Bet.fromJson(Map<String, dynamic> j) {
    return Bet(
      id: j['id'] is num ? (j['id'] as num).toInt() : 0,
      date: j['date']?.toString() ?? '',
      description: j['description']?.toString() ?? 'Bet',
      stake: j['stake'] is num ? (j['stake'] as num).toDouble() : 0,
      odds: j['odds'] is num ? (j['odds'] as num).toDouble() : 1,
      status: j['status']?.toString() ?? 'pending',
    );
  }
}

class BankrollTab extends StatefulWidget {
  const BankrollTab({super.key});

  @override
  State<BankrollTab> createState() => _BankrollTabState();
}

class _BankrollTabState extends State<BankrollTab> {
  static const String _dataKey = 'bankroll_v1';
  static const String _pinKey = 'bankroll_pin';
  static const String _nameKey = 'profile_name';
  static const String _phoneKey = 'profile_phone';

  bool _loading = true;
  bool _isUnlocked = false;
  String? _storedPin; // null until the user creates a PIN

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  double _starting = 0;
  double _cap = 0; // monthly cap on total stakes, 0 = not set
  List<Bet> _bets = [];

  // Profile details live only on this phone (never in the code).
  String _profileName = '';
  String _profilePhone = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- storage
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _storedPin = prefs.getString(_pinKey);
      _profileName = prefs.getString(_nameKey) ?? '';
      _profilePhone = prefs.getString(_phoneKey) ?? '';

      final raw = prefs.getString(_dataKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _starting = decoded['starting'] is num
              ? (decoded['starting'] as num).toDouble()
              : 0;
          _cap = decoded['cap'] is num ? (decoded['cap'] as num).toDouble() : 0;
          final list = decoded['bets'];
          if (list is List) {
            _bets = [];
            for (final e in list) {
              if (e is Map) _bets.add(Bet.fromJson(Map<String, dynamic>.from(e)));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Could not load bankroll: $e');
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _dataKey,
        jsonEncode({
          'starting': _starting,
          'cap': _cap,
          'bets': _bets.map((b) => b.toJson()).toList(),
        }),
      );
    } catch (e) {
      debugPrint('Could not save bankroll: $e');
    }
  }

  Future<void> _savePin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinKey, pin);
    } catch (e) {
      debugPrint('Could not save PIN: $e');
    }
  }

  // ---------------------------------------------------------------- profile
  Future<void> _saveProfile(String name, String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, name);
      await prefs.setString(_phoneKey, phone);
    } catch (e) {
      debugPrint('Could not save profile: $e');
    }
  }

  void _editProfile() {
    final nameCtl = TextEditingController(text: _profileName);
    final phoneCtl = TextEditingController(text: _profilePhone);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phoneCtl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Saved on this phone only.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = nameCtl.text.trim();
              final phone = phoneCtl.text.trim();
              setState(() {
                _profileName = name;
                _profilePhone = phone;
              });
              await _saveProfile(name, phone);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- PIN
  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<void> _createPin() async {
    final pin = _pinController.text;
    if (!_validPin(pin)) {
      _snack('Choose a PIN of exactly 4 digits');
      return;
    }
    if (pin != _confirmPinController.text) {
      _snack('The two PINs do not match');
      return;
    }
    await _savePin(pin);
    if (!mounted) return;
    setState(() {
      _storedPin = pin;
      _isUnlocked = true;
      _pinController.clear();
      _confirmPinController.clear();
    });
  }

  void _verifyPin() {
    if (_pinController.text == _storedPin) {
      setState(() {
        _isUnlocked = true;
        _pinController.clear();
      });
    } else {
      _pinController.clear();
      _snack('Incorrect PIN');
    }
  }

  // ---------------------------------------------------------------- numbers
  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  double get _settledProfit => _bets.fold(0.0, (sum, b) => sum + b.profit);
  double get _balance => _starting + _settledProfit;
  double get _pendingStake => _bets
      .where((b) => b.status == 'pending')
      .fold(0.0, (sum, b) => sum + b.stake);

  double get _spentThisMonth {
    final now = DateTime.now();
    var total = 0.0;
    for (final b in _bets) {
      if (b.status == 'void') continue;
      final d = DateTime.tryParse(b.date);
      if (d != null && d.year == now.year && d.month == now.month) {
        total += b.stake;
      }
    }
    return total;
  }

  double get _roi {
    var staked = 0.0;
    for (final b in _bets) {
      if (b.status == 'won' || b.status == 'lost') staked += b.stake;
    }
    return staked == 0 ? 0 : _settledProfit / staked * 100;
  }

  String _ksh(double v) => 'Ksh ${v.toStringAsFixed(2)}';

  Color _profitColor(double v) {
    if (v > 0) return Colors.green.shade600;
    if (v < 0) return Colors.red.shade600;
    return Colors.grey;
  }

  // ---------------------------------------------------------------- dialogs
  void _editSettings() {
    final startCtl = TextEditingController(
        text: _starting > 0 ? _starting.toStringAsFixed(2) : '');
    final capCtl =
        TextEditingController(text: _cap > 0 ? _cap.toStringAsFixed(2) : '');
    final newPinCtl = TextEditingController();
    String? pinError;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bankroll Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: startCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Starting bankroll (Ksh)'),
                ),
                TextField(
                  controller: capCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Monthly spending cap (Ksh, total stakes)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPinCtl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: 'New 4-digit PIN (leave empty to keep)',
                    counterText: '',
                    errorText: pinError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final newPin = newPinCtl.text;
                if (newPin.isNotEmpty && !_validPin(newPin)) {
                  setDialogState(() => pinError = 'PIN must be exactly 4 digits');
                  return;
                }

                setState(() {
                  _starting = math.max(0, _parse(startCtl.text) ?? 0);
                  _cap = math.max(0, _parse(capCtl.text) ?? 0);
                  if (newPin.isNotEmpty) _storedPin = newPin;
                });
                await _saveData();
                if (newPin.isNotEmpty) await _savePin(newPin);

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                _snack(newPin.isNotEmpty ? 'Settings and PIN updated' : 'Settings saved');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBet() async {
    final descCtl = TextEditingController();
    final stakeCtl = TextEditingController();
    final oddsCtl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Bet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtl,
                decoration:
                    const InputDecoration(labelText: 'What did you bet on? (optional)'),
              ),
              TextField(
                controller: stakeCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stake (Ksh)'),
              ),
              TextField(
                controller: oddsCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Odds (decimal, e.g. 1.85)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );

    if (ok != true) return;
    final stake = _parse(stakeCtl.text);
    final odds = _parse(oddsCtl.text);
    if (stake == null || stake <= 0 || odds == null || odds <= 1) {
      if (!mounted) return;
      _snack('Enter a stake above 0 and odds above 1.0');
      return;
    }

    final now = DateTime.now();
    final desc = descCtl.text.trim();
    setState(() {
      _bets.insert(
        0,
        Bet(
          id: now.millisecondsSinceEpoch,
          date: now.toIso8601String(),
          description: desc.isEmpty ? 'Bet' : desc,
          stake: stake,
          odds: odds,
        ),
      );
    });
    await _saveData();
  }

  Future<void> _onMenu(Bet bet, String action) async {
    setState(() {
      if (action == 'delete') {
        _bets.removeWhere((b) => b.id == bet.id);
      } else {
        bet.status = action;
      }
    });
    await _saveData();
  }

  // ---------------------------------------------------------------- widgets
  Widget _summaryCard() {
    final spent = _spentThisMonth;
    final capUsed = _cap > 0 ? spent / _cap : 0.0;
    final capColor =
        capUsed >= 1 ? Colors.red : (capUsed >= 0.8 ? Colors.orange : _teal);

    Widget line(String label, String value, {Color? color, bool bold = true}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                    color: color)),
          ],
        ),
      );
    }

    return Card(
      color: cardBg(context),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bankroll (settled bets)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(_ksh(_balance),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const Divider(height: 20),
            line('Total profit / loss', _ksh(_settledProfit),
                color: _profitColor(_settledProfit)),
            line('ROI', '${_roi.toStringAsFixed(1)}%', color: _profitColor(_roi)),
            line('At stake (pending)', _ksh(_pendingStake), bold: false),
            const Divider(height: 20),
            line('Staked this month',
                _cap > 0 ? '${_ksh(spent)} / ${_ksh(_cap)}' : _ksh(spent),
                color: capColor),
            if (_cap > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: math.min(1.0, capUsed),
                  minHeight: 8,
                  color: capColor,
                  backgroundColor: lineColor(context),
                ),
              ),
                if (capUsed >= 1)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'You have reached your monthly cap. Consider stopping for this month.',
                    style: TextStyle(
                        color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              else if (capUsed >= 0.8)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'You have used ${(capUsed * 100).toStringAsFixed(0)}% of your monthly cap.',
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Tip: set a monthly cap in settings.',
                    style: TextStyle(color: mutedText(context), fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(Bet b) {
    Color bg;
    Color fg;
    switch (b.status) {
      case 'won':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case 'lost':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        break;
      case 'void':
        bg = Colors.blueGrey.shade100;
        fg = Colors.blueGrey.shade700;
        break;
      default:
        bg = Colors.orange.withOpacity(0.2);
        fg = Colors.orange.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(b.status.toUpperCase(),
          style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _betsTable() {
    const head = TextStyle(fontWeight: FontWeight.bold);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('#', style: head)),
          DataColumn(label: Text('Description', style: head)),
          DataColumn(label: Text('Stake', style: head), numeric: true),
          DataColumn(label: Text('Odds', style: head), numeric: true),
          DataColumn(label: Text('P/L', style: head), numeric: true),
          DataColumn(label: Text('Status', style: head)),
          DataColumn(label: Text('Actions', style: head)),
        ],
        rows: _bets.asMap().entries.map((entry) {
          final int index = entry.key + 1;
          final Bet b = entry.value;
          final settled = b.status == 'won' || b.status == 'lost';
          return DataRow(cells: [
            DataCell(Text('$index')),
            DataCell(ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(b.description, overflow: TextOverflow.ellipsis),
            )),
            DataCell(Text(b.stake.toStringAsFixed(2))),
            DataCell(Text(b.odds.toStringAsFixed(2))),
            DataCell(Text(
              settled ? b.profit.toStringAsFixed(2) : '-',
              style: TextStyle(color: settled ? _profitColor(b.profit) : null),
            )),
            DataCell(_statusChip(b)),
            DataCell(
              PopupMenuButton<String>(
                onSelected: (v) => _onMenu(b, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'won', child: Text('Mark won')),
                  PopupMenuItem(value: 'lost', child: Text('Mark lost')),
                  PopupMenuItem(value: 'void', child: Text('Mark void')),
                  PopupMenuItem(value: 'pending', child: Text('Mark pending')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _lockScreen() {
    final creating = _storedPin == null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: _teal),
            const SizedBox(height: 16),
            Text(
              creating ? 'Create a PIN' : 'Bankroll Protected',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              creating
                  ? 'Choose a 4-digit PIN to protect your bankroll records.'
                  : 'Enter your 4-digit PIN to view financial records.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                onSubmitted: (_) => creating ? null : _verifyPin(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'PIN',
                  counterText: '',
                ),
              ),
            ),
            if (creating) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _confirmPinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Confirm PIN',
                    counterText: '',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              onPressed: creating ? _createPin : _verifyPin,
              child: Text(creating ? 'Set PIN' : 'Unlock Bankroll'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // If locked (or no PIN yet), render the PIN screen
    if (!_isUnlocked) {
      return _lockScreen();
    }

    // Unlocked content view
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bankroll',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _teal),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Lock Bankroll',
                    icon: const Icon(Icons.lock, color: _teal),
                    onPressed: () {
                      setState(() {
                        _isUnlocked = false;
                        _pinController.clear();
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Settings / Change PIN',
                    icon: const Icon(Icons.tune, color: _teal),
                    onPressed: _editSettings,
                  ),
                  ElevatedButton.icon(
                    onPressed: _addBet,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Bet'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                UserProfileCard(
                  name: _profileName,
                  phoneNumber: _profilePhone,
                  onEdit: _editProfile,
                ),
                const SizedBox(height: 12),
                _summaryCard(),
                const SizedBox(height: 12),
                if (_bets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No bets logged yet. Tap "Add Bet" to record a stake and its odds, then mark it won or lost when finished.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedText(context)),
                    ),
                  )
                else
                  _betsTable(),
                const SizedBox(height: 16),
                Text(
                  'Only bet what you can afford to lose. Tips are model estimates, not guarantees.',
                  style: TextStyle(color: mutedText(context), fontSize: 11),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

