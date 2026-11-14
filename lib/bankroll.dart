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
  List<dynamic> _bets = []; // Replace 'dynamic' with your Bet model class if defined

  @override
  void initState() {
    super.initState();
    _loadBets();
  }

  Future<void> _loadBets() async {
    // TODO: Load bets from storage or service
    setState(() {
      _bets = [];
    });
  }

  void _editSettings() {
    // TODO: Handle settings action
  }

  void _addBet() {
    // TODO: Handle add bet action
  }

  void _onMenu(dynamic b, String v) {
    // TODO: Handle menu actions (won, lost, void, pending, delete)
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

  /// Renders the bets in a structured tabular format
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimary),
              ),
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
