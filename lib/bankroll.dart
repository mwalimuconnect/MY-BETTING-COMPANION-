import 'package:flutter/material.dart';
import 'app_settings.dart';

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
                            PopupMenuItem(value: 'pending', child: Text('Mark pending')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    ),
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

  String _betSubtitle(dynamic b) {
    return 'Stake: ${b.stake} | Odds: ${b.odds}';
  }
}
