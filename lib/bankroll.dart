import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'main.dart';
import 'slip_access_manager.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'fixture_model.dart';

const Color _teal = Color(0xFF008080); // Teal Green

class UserProfileCard extends StatelessWidget {
  final String name;
  final String phoneNumber;
  final bool isAdmin;
  final VoidCallback? onEdit;

  const UserProfileCard({
    super.key,
    required this.name,
    required this.phoneNumber,
    required this.isAdmin,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name.isNotEmpty ? name : 'Tap to add your name',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isAdmin)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'ADMIN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                      ],
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
  final List<FixtureModel> fixtures;

  const BankrollTab({
    super.key,
    this.fixtures = const [],
  });

  @override
  State<BankrollTab> createState() => _BankrollTabState();
}

class _BankrollTabState extends State<BankrollTab> with WidgetsBindingObserver {
  static const String _dataKey = 'bankroll_v1';
  static const String _pinKey = 'bankroll_pin';
  static const String _nameKey = 'profile_name';
  static const String _phoneKey = 'profile_phone';
  static const String _unlockTimeKey = 'bankroll_unlock_timestamp';
  static const String _bgTimeKey = 'app_background_timestamp';
  static const int _gracePeriodMinutes = 15;

  bool _loading = true;
  bool _submittingAccount = false;
  bool _isUnlocked = false;
  bool _isAdmin = false;

  String? _storedPin;
  final TextEditingController _phoneSetupController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  double _starting = 0;
  double _cap = 0;
  List<Bet> _bets = [];
  List<FixtureModel> _fixtures = [];
  SuggestedSlip? _todaySuggestedSlip;

  String _profileName = '';
  String _profilePhone = '';

    @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fixtures = List<FixtureModel>.from(widget.fixtures);
    _load();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    try {
      final loaded = await ApiService.fetchFixtures();
      if (!mounted) return;
      setState(() {
        _fixtures = loaded;
      });
    } catch (_) {
      // Keep any existing fixtures or fall back to manual typing in _addBet()
    }
  }

  List<String> _outcomeChoicesFor(FixtureModel? fixture) {
    final List<String> choices = [];

    if (fixture != null) {
      if (fixture.topTip.trim().isNotEmpty) {
        choices.add(fixture.topTip.trim());
      }
      if (fixture.btts.trim().isNotEmpty &&
          fixture.btts.trim().toUpperCase() != 'N/A') {
        choices.add('BTTS: ${fixture.btts.trim()}');
      }
      if (fixture.over25Goals.trim().isNotEmpty &&
          fixture.over25Goals.trim().toUpperCase() != 'N/A') {
        choices.add('O/U 2.5: ${fixture.over25Goals.trim()}');
      }
      if (fixture.over15Goals.trim().isNotEmpty &&
          fixture.over15Goals.trim().toUpperCase() != 'N/A') {
        choices.add('Over 1.5 (${fixture.over15Goals.trim()})');
      }
    }

    const standardMarkets = [
      'Home Win (1)',
      'Draw (X)',
      'Away Win (2)',
      '1X (Home or Draw)',
      'X2 (Away or Draw)',
      '12 (Home or Away)',
      'GG (BTTS Yes)',
      'NG (BTTS No)',
      'Over 1.5 Goals',
      'Over 2.5 Goals',
      'Under 2.5 Goals',
      'Under 3.5 Goals',
      'Custom...',
    ];

    for (final m in standardMarkets) {
      if (!choices.contains(m)) {
        choices.add(m);
      }
    }
    return choices;
    }
bool? _evaluatePick(String pick, String homeTeam, String awayTeam, int hGoals, int aGoals) {
  final p = pick.trim().toLowerCase();
  final hName = homeTeam.trim().toLowerCase();
  final aName = awayTeam.trim().toLowerCase();
  final total = hGoals + aGoals;

  bool mentionsTeam(String fullName) {
    if (fullName.isEmpty) return false;
    if (p == fullName || p == '$fullName win' || p.startsWith('$fullName ')) {
      return true;
    }
    return fullName
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 4 && !{'fc', 'sc', 'cf', 'cd', 'ca', 'cr'}.contains(w))
        .any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(p));
  }

  if (p == '1' || p == 'home' || p == 'home win' || mentionsTeam(hName)) {
    return hGoals > aGoals;
  }
  if (p == '2' || p == 'away' || p == 'away win' || mentionsTeam(aName)) {
    return aGoals > hGoals;
  }
  if (p == 'x' || p == 'draw') return hGoals == aGoals;
  if (p == '1x' || p.contains('or draw') && mentionsTeam(hName)) return hGoals >= aGoals;
  if (p == 'x2' || p.contains('or draw') && mentionsTeam(aName)) return aGoals >= hGoals;
  if (p == '12' || p == 'home or away') return hGoals != aGoals;

  if (p.contains('over 1.5') || p == 'ov 1.5') return total > 1;
  if (p.contains('over 2.5') || p == 'ov 2.5') return total > 2;
  if (p.contains('under 2.5') || p == 'un 2.5') return total < 3;
  if (p.contains('under 3.5') || p == 'un 3.5') return total < 4;
  if (p == 'gg' || p == 'btts' || p.contains('btts: yes') || p == 'btts yes') {
    return hGoals > 0 && aGoals > 0;
  }
  if (p == 'ng' || p == 'btts no' || p.contains('btts: no')) {
    return hGoals == 0 || aGoals == 0;
  }
  return null;
}

Future<void> _autoSettleBets() async {
  if (_bets.isEmpty || _fixtures.isEmpty) return;

  bool changed = false;
  for (final bet in _bets) {
    if (bet.status != 'pending') continue;

    // Skip multi-leg descriptions unless you parse each leg separately
    if (bet.description.startsWith('Multi (')) continue;

    final match = RegExp(r'^(.+?)\s*\[(.+)\]$').firstMatch(bet.description.trim());
    if (match == null) continue;

    final descMatch = match.group(1)!.trim().toLowerCase();
    final pick = match.group(2)!.trim();

    for (final f in _fixtures) {
      if (!f.effectiveIsFinished) continue;
      final labelA = '${f.homeTeam} vs ${f.awayTeam}'.toLowerCase();
      final labelB = '${f.homeTeam} v ${f.awayTeam}'.toLowerCase();
      if (descMatch != labelA && descMatch != labelB) continue;

      final scoreRaw = f.actualScore
          .replaceAll(RegExp(r'^ft\s*', caseSensitive: false), '')
          .trim();
      final parts = scoreRaw.split(RegExp(r'\s*-\s*'));
      if (parts.length != 2) continue;

      final hGoals = int.tryParse(parts[0].trim());
      final aGoals = int.tryParse(parts[1].trim());
      if (hGoals == null || aGoals == null) continue;

      final won = _evaluatePick(pick, f.homeTeam, f.awayTeam, hGoals, aGoals);
      if (won != null) {
        bet.status = won ? 'won' : 'lost';
        changed = true;
      }
      break;
    }
  }

  if (changed && mounted) {
    setState(() {});
    await _saveData();
  }
}
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phoneSetupController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _loadFixtures();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _handleLifecycleChange(state);
  }

  Future<void> _handleLifecycleChange(AppLifecycleState state) async {
    final prefs = await SharedPreferences.getInstance();

    if (state == AppLifecycleState.paused) {
      await prefs.setInt(_bgTimeKey, DateTime.now().millisecondsSinceEpoch);
    } else if (state == AppLifecycleState.resumed) {
      final int bgTime = prefs.getInt(_bgTimeKey) ?? 0;
      if (bgTime > 0) {
        final int diffMinutes =
            (DateTime.now().millisecondsSinceEpoch - bgTime) ~/ (1000 * 60);
        if (diffMinutes >= _gracePeriodMinutes && mounted) {
          setState(() {
            _isUnlocked = false;
          });
        }
      }
    }
  }

  Future<void> _recordUnlockTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_unlockTimeKey, DateTime.now().millisecondsSinceEpoch);
  }
  
    // ---------------------------------------------------------------- storage
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _storedPin = prefs.getString(_pinKey);
      _profileName = prefs.getString(_nameKey) ?? '';
      _profilePhone = prefs.getString(_phoneKey) ?? '';
      _phoneSetupController.text = _profilePhone;

      if (_profilePhone.isNotEmpty) {
        final status = await SlipAccessManager.checkAccess();
        _isAdmin = status.isAdmin;
        if (_storedPin == null && status.serverPin.isNotEmpty) {
          _storedPin = status.serverPin;
        }
      }

      _todaySuggestedSlip = await SuggestedSlipStore.load();
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
        title: const Text('Edit Bankroll Account'),
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
              final status = await SlipAccessManager.checkAccess();
              if (!mounted) return;
              setState(() => _isAdmin = status.isAdmin);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------- Account Setup & PIN
  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<void> _createBankrollAccount() async {
    final phone = _phoneSetupController.text.trim();
    final pin = _pinController.text.trim();

    if (phone.length < 9) {
      _snack('Enter a valid phone number (e.g. 0712345678)');
      return;
    }
    if (!_validPin(pin)) {
      _snack('Choose a PIN of exactly 4 digits');
      return;
    }
    if (pin != _confirmPinController.text.trim()) {
      _snack('The two PINs do not match');
      return;
    }

    setState(() => _submittingAccount = true);

    await _saveProfile(_profileName, phone);
    await _savePin(pin);

    // Register & sync account with backend MongoDB
    final status = await SlipAccessManager.checkAccess(overridePhone: phone, pin: pin);

    if (!mounted) return;
    setState(() {
      _submittingAccount = false;
      _profilePhone = phone;
      _storedPin = pin;
      _isAdmin = status.isAdmin;
      _isUnlocked = true;
      _pinController.clear();
      _confirmPinController.clear();
    });
    _snack('Bankroll Account created and synced!');
  }

 Future<void> _verifyPin() async {
    if (_pinController.text.trim() == _storedPin) {
      await _recordUnlockTime(); // Save 15-min grace window
      setState(() {
        _isUnlocked = true;
        _pinController.clear();
      });
    } else {
      _pinController.clear();
      _snack('Incorrect PIN');
    }
 } 

  void _forgotPinDialog() {
    final phoneCtl = TextEditingController();
    final newPinCtl = TextEditingController();
    final confirmPinCtl = TextEditingController();
    bool resetting = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reset Bankroll PIN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter the phone number registered to your Bankroll Account to set a new 4-digit PIN.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Registered Phone Number',
                    hintText: 'e.g. 0712345678',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPinCtl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'New 4-Digit PIN',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPinCtl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New PIN',
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: resetting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
              onPressed: resetting
                  ? null
                  : () async {
                      final enteredPhone = phoneCtl.text.trim();
                      final newPin = newPinCtl.text.trim();

                      if (enteredPhone.isEmpty) {
                        _snack('Enter your registered phone number');
                        return;
                      }
                      if (!_validPin(newPin)) {
                        _snack('PIN must be exactly 4 digits');
                        return;
                      }
                      if (newPin != confirmPinCtl.text.trim()) {
                        _snack('PINs do not match');
                        return;
                      }

                      String norm(String p) {
                        var c = p.replaceAll(RegExp(r'\s+|\+'), '');
                        if (c.startsWith('0')) c = '254${c.substring(1)}';
                        return c;
                      }

                      if (_profilePhone.isNotEmpty &&
                          norm(enteredPhone) != norm(_profilePhone)) {
                        _snack('Phone number does not match this account');
                        return;
                      }

                      setDialogState(() => resetting = true);

                      // Sync reset with backend MongoDB
                      final backendOk =
                          await SlipAccessManager.resetPin(enteredPhone, newPin);

                      // Always save locally if local phone matched, even if offline
                      if (backendOk || _profilePhone.isNotEmpty) {
                        await _savePin(newPin);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);

                        setState(() {
                          _profilePhone = enteredPhone;
                          _storedPin = newPin;
                          _isUnlocked = true;
                          _pinController.clear();
                        });
                        _snack('PIN reset successfully. Account unlocked.');
                      } else {
                        setDialogState(() => resetting = false);
                        _snack('Account not found on server for that phone number');
                      }
                    },
              child: resetting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Reset PIN'),
            ),
          ],
        ),
      ),
    );
  }


// ---------------------------------------------------------------- numbers
  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  double get _settledProfit => _bets.fold(0.0, (sum, b) => sum + b.profit);
  double get _balance => _starting + _settledProfit;

  double get _pendingStake {
    double manualPending = _bets
        .where((b) => b.status == 'pending')
        .fold(0.0, (sum, b) => sum + b.stake);
    if (_todaySuggestedSlip != null) {
      manualPending += _todaySuggestedSlip!.stake;
    }
    return manualPending;
  }

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
    if (_todaySuggestedSlip != null) {
      final d = DateTime.tryParse(_todaySuggestedSlip!.date);
      if (d != null && d.year == now.year && d.month == now.month) {
        total += _todaySuggestedSlip!.stake;
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
  final pinCtl = TextEditingController();
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
                controller: pinCtl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6, // Adjusted to 6 digits for PIN or Admin Passcode
                decoration: InputDecoration(
                  labelText: 'New 6-digit PIN or Admin Key',
                  hintText: 'Leave empty to keep current',
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
              backgroundColor: const Color(0xFF008080),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final inputVal = pinCtl.text.trim();

              // Check if they entered the admin secret key '775067'
                    if (inputVal == '775067') {
        if (_profilePhone.trim().isEmpty) {
          setDialogState(() => pinError = 'Set your phone number in profile first');
          return;
        }
        _snack('Activating admin access...');
        try {
          final response = await http
              .post(
                Uri.parse('https://my-betting-companion.onrender.com/api/access/make-admin'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'phone': _profilePhone.trim(),
                  'secretKey': '775067',
                }),
              )
              .timeout(const Duration(seconds: 45));

          if (response.statusCode == 200) {
            await SlipAccessManager.checkAccess();
            if (!mounted) return;
            setState(() => _isAdmin = true);
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            
            return;
          } else {
            setDialogState(() => pinError = 'Server error (${response.statusCode})');
            return;
          }
        } catch (e) {
          setDialogState(() => pinError = 'Network timeout. Try again.');
          return;
        }
      }
          // Standard PIN validation (allows 4 to 6 digits)
              if (inputVal.isNotEmpty && (inputVal.length < 4 || inputVal.length > 6)) {
                setDialogState(() => pinError = 'PIN must be 4 to 6 digits');
                return;
              }

              setState(() {
                _starting = math.max(0, _parse(startCtl.text) ?? 0);
                _cap = math.max(0, _parse(capCtl.text) ?? 0);
                if (inputVal.isNotEmpty && inputVal != '775067') {
                  _storedPin = inputVal;
                }
              });

              await _saveData();
              if (inputVal.isNotEmpty && inputVal != '775067') {
                await _savePin(inputVal);
                if (_profilePhone.isNotEmpty) {
                  await SlipAccessManager.resetPin(_profilePhone, inputVal);
                }
              }

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              _snack(inputVal.isNotEmpty ? 'Settings and PIN updated' : 'Settings saved');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
bool _isFixtureFinished(FixtureModel f) {
  final rawStatus = ''; // Replace with f.<yourStatusField> if FixtureModel has one
  final status = rawStatus.trim().toUpperCase();
  const finishedStatuses = {
    'FINISHED',
    'FT',
    'AET',
    'PEN',
    'AWD',
    'WO',
    'CANC',
    'CANCELLED',
    'PST',
    'POSTPONED',
    'ABD',
    'ABANDONED',
  };
  if (finishedStatuses.contains(status)) return true;

  final kickoff = f.utcDate; 
  if (kickoff != null) {
  final DateTime? dt =
    kickoff is DateTime ? kickoff as DateTime : DateTime.tryParse(kickoff.toString());
    const liveStatuses = {'IN_PLAY', 'LIVE', '1H', '2H', 'HT', 'ET', 'BT', 'P'};
    if (dt != null &&
        dt.toUtc().isBefore(DateTime.now().toUtc()) &&
        !liveStatuses.contains(status)) {
      return true;
    }
  }
  return false;
}
bool _isFixtureFinished(FixtureModel f) {
    if (f.effectiveIsFinished) return true;

    final DateTime? dt = f.kickoff ?? FixtureModel._parseTimestamp(f.utcDate);
    if (dt != null &&
        dt.toUtc().isBefore(DateTime.now().toUtc()) &&
        !f.effectiveIsLive) {
      return true;
    }
    return false;
    }
Future<void> _addBet() async {
  final matchCtl = TextEditingController();
  final betTypeCtl = TextEditingController();
  final stakeCtl = TextEditingController();
  final oddsCtl = TextEditingController();
  bool isMultibet = false;
  FixtureModel? selectedFixture;
    String? selectedOutcome;
    String? selectedBetType;
    final List<String> multiLegs = [];
    const betTypes = [
      '1X2 (Match Result)',
      'Both Teams to Score (GG / BTTS)',
      'Over / Under Goals',
      'Double Chance (1X / 12 / X2)',
      'Draw No Bet',
      'Corners',
      'Cards',
      'Custom',
    ];
  if (_fixtures.isEmpty) {
    _loadFixtures();
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => AlertDialog(
        title: const Text('Add Bet & Prediction Type'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Single'),
                    selected: !isMultibet,
                    onSelected: (_) =>
                        setModalState(() => isMultibet = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Multibet'),
                    selected: isMultibet,
                    onSelected: (_) =>
                        setModalState(() => isMultibet = true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_fixtures.isNotEmpty) ...[
                DropdownButtonFormField<FixtureModel>(
                  value: selectedFixture,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select Fixture',
                  ),
                  hint: const Text('Choose fixture or type below'),
                  items: [
            items: [
            for (final f in _fixtures.where((item) => !_isFixtureFinished(item)))
            DropdownMenuItem<FixtureModel>(
              value: f,
              child: Text(
                '${f.homeTeam} vs ${f.awayTeam}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        DropdownMenuItem<FixtureModel>(
                        value: f,
                        child: Text(
                          '${f.homeTeam} vs ${f.awayTeam}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (f) {
                    setModalState(() {
                      selectedFixture = f;
                      if (f != null) {
                        matchCtl.text = '${f.homeTeam} vs ${f.awayTeam}';
                        selectedOutcome = null;
                      }
                    });
                  },
                ),
  
                  const SizedBox(height: 8),
                ],
                DropdownButtonFormField<String>(
                  value: selectedOutcome,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Possible Outcomes',
                  ),
                  hint: const Text('Choose outcome or type below'),
                  items: [
                    for (final o in _outcomeChoicesFor(selectedFixture))
                      DropdownMenuItem<String>(
                        value: o,
                        child: Text(
                          o,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (val) {
                    setModalState(() {
                      selectedOutcome = val;
                      if (val != null && val != 'Custom...') {
                        betTypeCtl.text = val;
                      } else if (val == 'Custom...') {
                        betTypeCtl.clear();
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
              TextField(
                controller: matchCtl,
                decoration: const InputDecoration(
                  labelText: 'Match (e.g., Arsenal vs Chelsea)',
                  hintText: 'Home vs Away',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: betTypeCtl,
                decoration: const InputDecoration(
                  labelText: 'Bet Type / Pick (e.g., GG, Over 2.5, Home Win)',
                  hintText: 'e.g. GG or 1X or Over 2.5',
                ),
              ),
          TextField(
          controller: betTypeCtl,
          decoration: const InputDecoration(
            labelText: 'Bet Type / Pick (e.g., GG, Over 2.5, Home',
            hintText: 'e.g. GG or 1X or Over 2.5',
          ),
        ), 
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedBetType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Bet Type'),
          hint: const Text('Select bet type'),
          items: [
            for (final bt in betTypes)
              DropdownMenuItem<String>(
                value: bt,
                child: Text(bt, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (val) {
            setModalState(() {
              selectedBetType = val;
              if (val != null && val != 'Custom') {
                betTypeCtl.text = val;
              } else if (val == 'Custom') {
                betTypeCtl.clear();
              }
            });
          },
        ),
        const SizedBox(height: 8), 
              const SizedBox(height: 8),
              TextField(
                controller: stakeCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stake (Ksh)'),
              ),
              if (isMultibet) ...[
                  OutlinedButton.icon(
                  onPressed: () {
                    final m = matchCtl.text.trim();
                    final p = betTypeCtl.text.trim();
                    if (m.isEmpty || p.isEmpty) {
                    _snack('Pick or enter a fixture and outcome first.');
                     return;
                    }
                    setModalState(() {
                    multiLegs.add('$m [$p]');
                    selectedFixture = null;
                    selectedOutcome = null;
                    selectedBetType = null;
                    matchCtl.clear();
                    betTypeCtl.clear();
                   });
                 },
                icon: const Icon(Icons.add),
                label: Text('Add Leg (${multiLegs.length})'),
                )
                for (int i = 0; i < multiLegs.length; i++)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${multiLegs[i]}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () =>
                            setModalState(() => multiLegs.removeAt(i)),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: oddsCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Odds (decimal, e.g. 1.85)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add & Track'),
          ),
        ],
      ),
    ),
  );

    if (ok != true) return;
    final matchName = matchCtl.text.trim();
    final betType = betTypeCtl.text.trim();
    final stake = _parse(stakeCtl.text);
    final odds = _parse(oddsCtl.text);
    if (isMultibet && matchName.isNotEmpty && betType.isNotEmpty) {
  multiLegs.add('$matchName [$betType]');
}

final hasValidPick = isMultibet
    ? (multiLegs.isNotEmpty || matchName.isNotEmpty)
    : matchName.isNotEmpty;

if (!hasValidPick || stake == null || stake <= 0 || odds == null || odds <= 1.0) {
  if (!mounted) return;
  _snack('Enter a valid match or leg, stake above 0, and odds above 1.0');
  return;
}

final fullDescription = isMultibet && multiLegs.isNotEmpty
    ? 'Multi (${multiLegs.length} legs): ${multiLegs.join(' | ')}'
    : (betType.isNotEmpty ? '$matchName [$betType]' : matchName);

    if (matchName.isEmpty || stake == null || stake <= 0 || odds == null || odds <= 1) {
      if (!mounted) return;
      _snack('Enter a valid match name, stake above 0, and odds above 1.0');
      return;
    }
    
    final now = DateTime.now();
    
    setState(() {
      _bets.insert(
        0,
        Bet(
          id: now.millisecondsSinceEpoch,
          date: now.toIso8601String(),
          description: fullDescription,
          stake: stake,
          odds: odds,
          status: 'pending', // Will auto-settle or can be matched against live scores
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
                const Text('Bankroll (settled bets)',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
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

  Widget _automatedSlipCard() {
    if (_todaySuggestedSlip == null) return const SizedBox.shrink();
    return Card(
      color: cardBg(context),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _teal, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔥 Today\'s Automated Slip',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _teal),
                ),
                Text(
                  '${_todaySuggestedSlip!.totalOdds.toStringAsFixed(2)}x',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _teal),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _todaySuggestedSlip!.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Stake: ${_ksh(_todaySuggestedSlip!.stake)}',
                    style: const TextStyle(fontSize: 12)),
                Text('Potential Win: ${_ksh(_todaySuggestedSlip!.potentialPayout)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _comparisonTableCard() {
    final systemBets = _bets.where((b) => b.description.contains('Accumulator')).toList();
    final manualBets = _bets.where((b) => !b.description.contains('Accumulator')).toList();

    double totalStaked(List<Bet> list) =>
        list.where((b) => b.status != 'void').fold(0.0, (s, b) => s + b.stake);

    double totalWon(List<Bet> list) {
      return list
          .where((b) => b.status == 'won')
          .fold(0.0, (s, b) => s + b.stake + b.profit);
    }

    double totalProfit(List<Bet> list) => list.fold(0.0, (s, b) => s + b.profit);
    int countStatus(List<Bet> list, String status) =>
        list.where((b) => b.status == status).length;

    final sysStaked = totalStaked(systemBets);
    final sysWonAmount = totalWon(systemBets);
    final sysProfit = totalProfit(systemBets);
    final sysWins = countStatus(systemBets, 'won');
    final sysLosses = countStatus(systemBets, 'lost');

    final manStaked = totalStaked(manualBets);
    final manWonAmount = totalWon(manualBets);
    final manProfit = totalProfit(manualBets);
    final manWins = countStatus(manualBets, 'won');
    final manLosses = countStatus(manualBets, 'lost');

    return Card(
      color: cardBg(context),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Performance: System vs Manual',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _teal),
            ),
            const SizedBox(height: 10),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.3),
                1: FlexColumnWidth(1.0),
                2: FlexColumnWidth(1.0),
              },
              border: TableBorder.all(color: lineColor(context), width: 0.5),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: lineColor(context).withOpacity(0.3)),
                  children: const [
                    Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Metric',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('System (Auto)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: _teal))),
                    Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Manual (You)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Total Staked', style: TextStyle(fontSize: 11))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_ksh(sysStaked), style: const TextStyle(fontSize: 11))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_ksh(manStaked), style: const TextStyle(fontSize: 11))),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Amount Won', style: TextStyle(fontSize: 11))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_ksh(sysWonAmount),
                            style: const TextStyle(fontSize: 11, color: Colors.green))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_ksh(manWonAmount),
                            style: const TextStyle(fontSize: 11, color: Colors.green))),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Profit / Loss', style: TextStyle(fontSize: 11))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_ksh(sysProfit),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _profitColor(sysProfit)))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(_ksh(manProfit),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _profitColor(manProfit)))),
                  ],
                ),
                TableRow(
                  children: [
                    const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Record (W - L)', style: TextStyle(fontSize: 11))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('$sysWins - $sysLosses',
                            style: const TextStyle(fontSize: 11))),
                    Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('$manWins - $manLosses',
                            style: const TextStyle(fontSize: 11))),
                  ],
                ),
              ],
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

  int _weekOfYear(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final days = date.difference(startOfYear).inDays;
    return (days / 7).ceil();
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  Widget _groupedBetsSection() {
    if (_bets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No bets logged yet. Tap "Add Bet" to record a stake and its odds, or view automated daily slips from the Slips tab.',
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedText(context)),
        ),
      );
    }

    final Map<String, Map<int, Map<String, List<Bet>>>> grouped = {};
    for (final b in _bets) {
      final dt = DateTime.tryParse(b.date) ?? DateTime.now();
      final monthKey = '${_monthName(dt.month)} ${dt.year}';
      final weekNum = _weekOfYear(dt);
      final dayKey =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(monthKey, () => {});
      grouped[monthKey]!.putIfAbsent(weekNum, () => {});
      grouped[monthKey]![weekNum]!.putIfAbsent(dayKey, () => []);
      grouped[monthKey]![weekNum]![dayKey]!.add(b);
    }

    return Column(
      children: grouped.entries.map((monthEntry) {
        final monthName = monthEntry.key;
        final weeks = monthEntry.value.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key));
        return Card(
          color: cardBg(context),
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(
              monthName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _teal),
            ),
            subtitle: Text(
                '${weeks.fold(0, (sum, w) => sum + w.value.values.fold(0, (s, d) => s + d.length))} bets logged'),
            children: weeks.map((weekEntry) {
              final weekNum = weekEntry.key;
              final days = weekEntry.value.entries.toList()
                ..sort((a, b) => b.key.compareTo(a.key));
              return ExpansionTile(
                title: Text('Week $weekNum',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                children: days.map((dayEntry) {
                  final dayDate = dayEntry.key;
                  final dayBets = dayEntry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            dayDate,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: mutedText(context)),
                          ),
                        ),
                        ...dayBets.map((b) {
                          final settled = b.status == 'won' || b.status == 'lost';
                          return Card(
                            elevation: 0,
                            color: lineColor(context).withOpacity(0.3),
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              title: Text(b.description,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(
                                'Stake: ${_ksh(b.stake)} – Odds: ${b.odds.toStringAsFixed(2)}${settled ? ' – P/L: ${_ksh(b.profit)}' : ''}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: settled ? _profitColor(b.profit) : null),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _statusChip(b),
                                  PopupMenuButton<String>(
                                    onSelected: (v) => _onMenu(b, v),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'won', child: Text('Mark won')),
                                      PopupMenuItem(value: 'lost', child: Text('Mark lost')),
                                      PopupMenuItem(value: 'void', child: Text('Mark void')),
                                      PopupMenuItem(
                                          value: 'pending', child: Text('Mark pending')),
                                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _lockScreen() {
    final creating = _storedPin == null || _profilePhone.isEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance_wallet, size: 64, color: _teal),
            const SizedBox(height: 16),
            Text(
              creating ? 'Create Bankroll Account' : 'Bankroll Account',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              creating
                  ? 'Register with your phone number and a 4-digit PIN to create your Bankroll Account.'
                  : 'Enter your 4-digit PIN to unlock your Bankroll Account.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (creating) ...[
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _phoneSetupController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Phone Number (e.g. 0712345678)',
                    prefixIcon: Icon(Icons.phone, color: _teal),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: 260,
              child: TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                onSubmitted: (_) => creating ? null : _verifyPin(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '4-Digit PIN',
                  counterText: '',
                ),
              ),
            ),
            if (creating) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _confirmPinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Confirm 4-Digit PIN',
                    counterText: '',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(260, 48),
              ),
              onPressed: _submittingAccount
                  ? null
                  : (creating ? _createBankrollAccount : _verifyPin),
              child: _submittingAccount
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(creating ? 'Create Bankroll Account' : 'Unlock Bankroll Account'),
            ),
            if (!creating) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: _forgotPinDialog,
                child: const Text(
                  'Forgot PIN?',
                  style: TextStyle(color: _teal, fontWeight: FontWeight.w600),
                ),
              ),
            ],
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
    if (!_isUnlocked) {
      return _lockScreen();
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bankroll Account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _teal),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Lock Account',
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
                  isAdmin: _isAdmin,
                  onEdit: _editProfile,
                ),
                
                const SizedBox(height: 12),
                _summaryCard(),
                const SizedBox(height: 12),
                _automatedSlipCard(),
                const SizedBox(height: 8),
                _comparisonTableCard(),
                const SizedBox(height: 12),
                _groupedBetsSection(),
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
