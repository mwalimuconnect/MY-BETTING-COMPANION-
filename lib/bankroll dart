import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';

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

  /// Profit or loss once settled (stake is not counted until then).
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
  const BankrollTab({Key? key}) : super(key: key);

  @override
  State<BankrollTab> createState() => _BankrollTabState();
}

class _BankrollTabState extends State<BankrollTab> {
  static const String _prefsKey = 'bankroll_v1';

  double _starting = 0;
  double _cap = 0; // monthly spending cap (total stakes), 0 = not set
  List<Bet> _bets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
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

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
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

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  // ----- numbers -----
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

  // ----- dialogs -----
  Future<void> _editSettings() async {
    final startCtl = TextEditingController(
        text: _starting > 0 ? _starting.toStringAsFixed(2) : '');
    final capCtl =
        TextEditingController(text: _cap > 0 ? _cap.toStringAsFixed(2) : '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bankroll settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Starting bankroll'),
            ),
            TextField(
              controller: capCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Monthly spending cap (total stakes)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _starting = math.max(0, _parse(startCtl.text) ?? 0);
        _cap = math.max(0, _parse(capCtl.text) ?? 0);
      });
      await _save();
    }
  }

  Future<void> _addBet() async {
    final descCtl = TextEditingController();
    final stakeCtl = TextEditingController();
    final oddsCtl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add bet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtl,
                decoration: const InputDecoration(
                    labelText: 'What did you bet on? (optional)'),
              ),
              TextField(
                controller: stakeCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stake'),
              ),
              TextField(
                controller: oddsCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a stake above 0 and odds above 1.0'),
      ));
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
    await _save();
  }

  Future<void> _onMenu(Bet bet, String action) async {
    setState(() {
      if (action == 'delete') {
        _bets.removeWhere((b) => b.id == bet.id);
      } else {
        bet.status = action;
      }
    });
    await _save();
  }

  // ----- widgets -----
  Color _profitColor(double v) {
    if (v > 0) return Colors.green.shade600;
    if (v < 0) return Colors.red.shade600;
    return Colors.grey;
  }

  String _money(double v) => v.toStringAsFixed(2);

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
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade700;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(b.status.toUpperCase(),
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _summaryCard() {
    final spent = _spentThisMonth;
    final capUsed = _cap > 0 ? spent / _cap : 0.0;
    final capColor = capUsed >= 1
        ? Colors.red
        : (capUsed >= 0.8 ? Colors.orange : kPrimary);

    return Card(
      color: cardBg(context),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Balance (settled bets)',
                    style: TextStyle(fontSize: 12)),
                Text(_money(_balance),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Profit / loss', style: TextStyle(fontSize: 13)),
                Text(_money(_settledProfit),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _profitColor(_settledProfit))),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ROI', style: TextStyle(fontSize: 13)),
                Text('${_roi.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: _profitColor(_roi))),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('At stake (pending)', style: TextStyle(fontSize: 13)),
                Text(_money(_pendingStake),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Staked this month', style: TextStyle(fontSize: 13)),
                Text(
                    _cap > 0
                        ? '${_money(spent)} / ${_money(_cap)}'
                        : _money(spent),
                    style: TextStyle(fontWeight: FontWeight.w600, color: capColor)),
              ],
            ),
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
              if (capUsed >= 1) ...[
                const SizedBox(height: 8),
                const Text(
                  'You have reached your monthly cap. Consider stopping for this month.',
                  style: TextStyle(
                      color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ] else if (capUsed >= 0.8) ...[
                const SizedBox(height: 8),
                Text(
                  'You have used ${(capUsed * 100).toStringAsFixed(0)}% of your monthly cap.',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                ),
              ],
            ] else ...[
              const SizedBox(height: 6),
              Text('Tip: set a monthly cap in settings (top right).',
                  style: TextStyle(color: mutedText(context), fontSize: 11)),
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Bankroll',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: kPrimary)),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.tune, color: kPrimary),
                    onPressed: _editSettings,
                  ),
                  ElevatedButton.icon(
                    onPressed: _addBet,
                    icon: const Icon(Icons.add),
                    label: const Text('Add bet'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                _summaryCard(),
                const SizedBox(height: 12),
                if (_bets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No bets logged yet. Tap "Add bet" to record a stake and its odds, then mark it won or lost when it finishes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedText(context)),
                    ),
                  )
                else
                  for (final b in _bets)
                    Card(
                      child: ListTile(
                        title: Text(b.description),
                        subtitle: Text(
                          _betSubtitle(b),
                          style: const TextStyle(fontSize: 12),
                        ),
                        leading: _statusChip(b),
                        trailing: PopupMenuButton<String>(
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
                      ),
                    ),
                const SizedBox(height: 16),
                Text(
                  'Only bet what you can afford to lose. Tips are model estimates, not guarantees. If betting stops being fun, take a break.',
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
