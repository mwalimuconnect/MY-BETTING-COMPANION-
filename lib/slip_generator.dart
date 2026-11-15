// ---------------------------------------------------------------------------
// Slips tab (MY PICKS) - Fully corrected scoping & method names
// ---------------------------------------------------------------------------
class _SlipsData {
  final List<SlipLeg> legs;
  final SuggestedSlip? suggested;

  const _SlipsData(this.legs, this.suggested);
}

class SavedSlipsTab extends StatefulWidget {
  const SavedSlipsTab({super.key});

  @override
  State<SavedSlipsTab> createState() => _SavedSlipsTabState();
}

class _SavedSlipsTabState extends State<SavedSlipsTab> {
  late Future<_SlipsData> _slipsFuture;

  @override
  void initState() {
    super.initState();
    _loadSlips();
  }

  Future<_SlipsData> _fetch() async {
    final legs = await SlipStore.load();
    final suggested = await SuggestedSlipStore.load();
    return _SlipsData(legs, suggested);
  }

  void _loadSlips() {
    setState(() {
      _slipsFuture = _fetch();
    });
  }

  /// Safaricom Green day and date header helper
  Widget _buildDayHeader(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    String formatted = dateStr;
    if (dt != null) {
      const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
      const days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
      formatted = '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        formatted.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00C853), // Safaricom Green highlight
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _suggestedCard(BuildContext context, SuggestedSlip slip) {
    final double chance = slip.totalOdds > 0 ? 100 / slip.totalOdds : 0;

    return Card(
      color: cardBg(context),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kTealGreen, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    slip.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Text(
                  '${slip.totalOdds.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: kTealGreen,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            for (int i = 0; i < slip.selections.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${slip.selections[i]['match']}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Prediction: ${slip.selections[i]['prediction']}',
                            style: TextStyle(fontSize: 12, color: mutedText(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${slip.selections[i]['odds']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: kTealGreen,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < slip.selections.length - 1)
                const Divider(height: 8, color: Colors.black12),
            ],
            const Divider(height: 16),
            Text(
              'Chance that every leg wins: about ${chance.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kTealGreen.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Stake', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        'Ksh ${slip.stake.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Possible Win', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        'Ksh ${slip.potentialPayout.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: kTealGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              SuggestedSlipStore.note,
              style: TextStyle(fontSize: 10, color: mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedManualList(List<SlipLeg> legs) {
    if (legs.isEmpty) return const SizedBox.shrink();

    final Map<String, List<SlipLeg>> grouped = {};
    for (final leg in legs) {
      grouped.putIfAbsent(leg.dayKey, () => []).add(leg);
    }

    final sortedDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            '📌 MY SAVED PICKS',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: kTealGreen,
              letterSpacing: 1.1,
            ),
          ),
        ),
        for (final day in sortedDays) ...[
          _buildDayHeader(day),
          for (int i = 0; i < grouped[day]!.length; i++)
            Card(
              color: cardBg(context),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: kTealGreen,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  '${grouped[day]![i].home} vs ${grouped[day]![i].away}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tip: ${grouped[day]![i].tip.isNotEmpty ? grouped[day]![i].tip : "None"} | Score: ${grouped[day]![i].score.isNotEmpty ? grouped[day]![i].score : "Pending"}',
                    style: TextStyle(fontSize: 12, color: mutedText(context)),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    await SlipStore.remove(grouped[day]![i].key);
                    _loadSlips();
                  },
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SlipsData>(
      future: _slipsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              buildMyPicksHeader(),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          );
        }

        final data = snapshot.data ?? const _SlipsData([], null);
        final legs = data.legs;
        final summary = SlipStore.summary(legs);

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            buildMyPicksHeader(),
            
            // Section 1: System-Generated Daily Accumulator
            if (data.suggested != null) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  '🧠 DAILY VALUE ACCUMULATOR',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: kTealGreen,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              _buildDayHeader(data.suggested!.date),
              _suggestedCard(context, data.suggested!),
            ],

            // Summary Card for Manual Saved Picks (if any exist)
            if (legs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Card(
                  color: cardBg(context),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statItem('Accumulator', summary.status),
                        _statItem('Won', '${summary.won}'),
                        _statItem('Lost', '${summary.lost}'),
                        _statItem('Pending', '${summary.pending}'),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // Section 2: Manually Saved Bookmarks Grouped by Day
            if (legs.isEmpty && data.suggested == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No saved picks yet. Bookmark matches from the Fixtures tab to add them here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedText(context)),
                ),
              )
            else
              _buildGroupedManualList(legs),
          ],
        );
      },
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
