import 'package:flutter/material.dart';
import 'app_settings.dart';

class UserProfileCard extends StatelessWidget {
  final String name;
  final String phoneNumber;
  final VoidCallback? onEditPhoto;

  const UserProfileCard({
    super.key,
    required this.name,
    required this.phoneNumber,
    this.onEditPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cardBg(context),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    color: Color(0xFF008080), // Teal Green
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: onEditPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF008080),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.white,
                      ),
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
                    name.isNotEmpty ? name : 'User Profile',
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
                        phoneNumber.isNotEmpty ? phoneNumber : '+254712489816',
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
    );
  }
}

class BankrollTab extends StatefulWidget {
  const BankrollTab({super.key});

  @override
  State<BankrollTab> createState() => _BankrollTabState();
}

class _BankrollTabState extends State<BankrollTab> {
  bool _isUnlocked = false;
  String _correctPin = '1234'; // Default PIN code
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  List<dynamic> _bets = [];

  @override
  void initState() {
    super.initState();
    _loadBets();
  }

  Future<void> _loadBets() async {
    setState(() {
      _bets = [];
    });
  }

  void _verifyPin() {
    if (_pinController.text == _correctPin) {
      setState(() {
        _isUnlocked = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN. Try 1234')),
      );
    }
  }

  void _editSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bankroll Security Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a new 4-digit PIN to protect your bankroll:'),
            const SizedBox(height: 12),
            TextField(
              controller: _newPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'New 4-Digit PIN',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF008080),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (_newPinController.text.length == 4) {
                setState(() {
                  _correctPin = _newPinController.text;
                });
                _newPinController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN updated successfully!')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN must be exactly 4 digits')),
                );
              }
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
  }

  void _addBet() {
    // TODO: Handle add bet action
  }

  void _onMenu(dynamic b, String v) {
    // TODO: Handle menu actions
  }

  Widget _summaryCard() {
    return Card(
      color: cardBg(context),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text('Bankroll', style: TextStyle(fontSize: 12, color: Colors.grey)),
                SizedBox(height: 4),
                Text('Ksh 0.00', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            Column(
              children: [
                Text('Total Profit', style: TextStyle(fontSize: 12, color: Colors.grey)),
                SizedBox(height: 4),
                Text('Ksh 0.00', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(dynamic b) {
    return Chip(
      label: const Text('Pending', style: TextStyle(fontSize: 10)),
      backgroundColor: Colors.orange.withOpacity(0.2),
    );
  }

  Widget _betsTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Stake', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Odds', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: _bets.asMap().entries.map((entry) {
          final int index = entry.key + 1;
          final b = entry.value;
          return DataRow(cells: [
            DataCell(Text('$index')),
            DataCell(Text(b.description?.toString() ?? '')),
            DataCell(Text('${b.stake ?? 0}')),
            DataCell(Text('${b.odds ?? 0}')),
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

  @override
  Widget build(BuildContext context) {
    // If locked, render PIN entry screen
    if (!_isUnlocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Color(0xFF008080)),
              const SizedBox(height: 16),
              const Text(
                'Bankroll Protected',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your 4-digit PIN to view financial records (Hint: 1234)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
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
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'PIN',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008080),
                  foregroundColor: Colors.white,
                ),
                onPressed: _verifyPin,
                child: const Text('Unlock Bankroll'),
              ),
            ],
          ),
        ),
      );
    }

    // Unlocked Content View
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF008080)),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Lock Bankroll',
                    icon: const Icon(Icons.lock, color: Color(0xFF008080)),
                    onPressed: () {
                      setState(() {
                        _isUnlocked = false;
                        _pinController.clear();
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Settings / Change PIN',
                    icon: const Icon(Icons.tune, color: Color(0xFF008080)),
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
                const UserProfileCard(
                  name: 'Samuel Moturi Oino',
                  phoneNumber: '+254712489816',
                ),
                const SizedBox(height: 12),
                _summaryCard(),
                const SizedBox(height: 12),
                if (_bets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No bets logged yet. Tap "Add bet" to record a stake and its odds, then mark it won or lost when finished.',
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
