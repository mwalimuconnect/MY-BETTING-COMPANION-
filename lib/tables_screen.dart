import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'league_data.dart';
import 'api_service.dart'; // Import your updated ApiService

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedLeague = 'PL'; // Default competition code

    final Map<String, String> _leagues = {
    'KPL': 'Kenyan Premier League (Kenya)',
    'PL': 'Premier League (England)',
    'ELC': 'Championship (England)',
    'PD': 'La Liga (Spain)',
    'SA': 'Serie A (Italy)',
    'BL1': 'Bundesliga (Germany)',
    'FL1': 'Ligue 1 (France)',
    'DED': 'Eredivisie (Netherlands)',
    'PPL': 'Primeira Liga (Portugal)',
    'CL': 'UEFA Champions League',
    'EC': 'European Championship',
    'WC': 'FIFA World Cup',
    'BSA': 'Brasileirão Série A (Brazil)',
    'ARG': 'Liga Profesional (Argentina)',
    'MLS': 'Major League Soccer (USA)',
    'SPL': 'Saudi Pro League (Saudi Arabia)',
    'J1': 'J1 League (Japan)',
    'KL1': 'K League 1 (South Korea)',
    'ALE': 'A-League Men (Australia)',
    'ACN': 'Africa Cup of Nations (AFCON)',
    'CAF': 'CAF Champions League (Africa)',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // League Selector Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: cardBg(context),
          child: Row(
            children: [
              Text(
                'Competition:',
                style: TextStyle(fontWeight: FontWeight.bold, color: mutedText(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedLeague,
                  isExpanded: true,
                  dropdownColor: cardBg(context),
                  items: _leagues.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedLeague = val;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        // Sub-tabs for Standings vs Scorers
        TabBar(
          controller: _tabController,
          labelColor: kPrimary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: kPrimary,
          tabs: const [
            Tab(text: 'Standings Table'),
            Tab(text: 'Top Scorers'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              LeagueStandingsView(code: _selectedLeague),
              LeagueScorersView(code: _selectedLeague),
            ],
          ),
        ),
      ],
    );
  }
}

class LeagueStandingsView extends StatelessWidget {
  final String code;
  const LeagueStandingsView({super.key, required this.code});

  static const TextStyle _head = TextStyle(fontWeight: FontWeight.bold);

  // Function to show team insights dialog when a team is tapped
  Future<void> _showTeamInsights(BuildContext context, String teamName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await ApiService.fetchTeamInsights(teamName);
      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      // Parse response or show injuries list
      final injuriesList = data['response'] as List? ?? [];

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$teamName Insights'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active Injuries & Suspensions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kPrimary),
                  ),
                  const SizedBox(height: 8),
                  if (injuriesList.isEmpty)
                    const Text('No active injury reports returned for this team right now.')
                  else
                    ...injuriesList.map((injury) {
                      final player = injury['player']?['name'] ?? 'Unknown Player';
                      final type = injury['player']?['type'] ?? 'Injury';
                      final reason = injury['player']?['reason'] ?? 'Unknown reason';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $player ($type: $reason)', style: const TextStyle(fontSize: 12)),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load team insights: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StandingGroup>>(
      future: LeagueApi.standings(code),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Could not load standings:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No standings data available for this competition.'));
        }

        final groups = snapshot.data!;
        return ListView.builder(
          itemCount: groups.length + 1,
          itemBuilder: (context, gIndex) {
            // Last item: short legend and a note about missing data.
            if (gIndex == groups.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'P played, W won, D drawn, L lost, GF goals for, GA goals against, GD goal difference, Pts points. '
                  'Tap any team name to view live injury reports and squad insights.',
                  style: TextStyle(fontSize: 11, color: mutedText(context)),
                ),
              );
            }

            final group = groups[gIndex];
            final bool showForm = group.rows.any((r) => r.form.isNotEmpty);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (group.name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      group.name.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ),
                Card(
                  color: cardBg(context),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 14,
                      headingRowColor: WidgetStateProperty.all(headBg(context)),
                      columns: [
                        const DataColumn(label: Text('Pos', style: _head)),
                        const DataColumn(label: Text('Team', style: _head)),
                        const DataColumn(label: Text('P', style: _head), numeric: true),
                        const DataColumn(label: Text('W', style: _head), numeric: true),
                        const DataColumn(label: Text('D', style: _head), numeric: true),
                        const DataColumn(label: Text('L', style: _head), numeric: true),
                        const DataColumn(label: Text('GF', style: _head), numeric: true),
                        const DataColumn(label: Text('GA', style: _head), numeric: true),
                        const DataColumn(label: Text('GD', style: _head), numeric: true),
                        const DataColumn(
                          label: Text('Pts', style: TextStyle(fontWeight: FontWeight.bold, color: kPrimary)),
                          numeric: true,
                        ),
                        if (showForm) const DataColumn(label: Text('Form', style: _head)),
                      ],
                      rows: group.rows.map((row) {
                        return DataRow(cells: [
                          DataCell(Text('${row.position}',
                              style: TextStyle(fontWeight: FontWeight.bold, color: mutedText(context)))),
                          DataCell(
                            InkWell(
                              onTap: () => _showTeamInsights(context, row.team),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 140),
                                child: Text(row.team,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: kPrimary,
                                      decoration: TextDecoration.underline,
                                    )),
                              ),
                            ),
                          ),
                          DataCell(Text('${row.played}')),
                          DataCell(Text('${row.won}')),
                          DataCell(Text('${row.draw}')),
                          DataCell(Text('${row.lost}')),
                          DataCell(Text('${row.goalsFor}')),
                          DataCell(Text('${row.goalsAgainst}')),
                          DataCell(Text(row.goalDifference > 0
                              ? '+${row.goalDifference}'
                              : '${row.goalDifference}')),
                          DataCell(Text('${row.points}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary))),
                          if (showForm) DataCell(Text(row.form.replaceAll(',', ' '))),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class LeagueScorersView extends StatelessWidget {
  final String code;
  const LeagueScorersView({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScorerRow>>(
      future: LeagueApi.scorers(code),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Could not load top scorers:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No top scorers available for this competition.'));
        }

        final scorers = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: scorers.length,
          itemBuilder: (context, index) {
            final scorer = scorers[index];
            return Card(
              color: cardBg(context),
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: kPrimary.withOpacity(0.1),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary, fontSize: 13),
                  ),
                ),
                title: Text(scorer.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(
                  '${scorer.team} | ${scorer.played} played',
                  style: TextStyle(fontSize: 12, color: mutedText(context)),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${scorer.goals} Goals',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kPrimary),
                    ),
                    if (scorer.assists > 0)
                      Text(
                        '${scorer.assists} assists',
                        style: TextStyle(fontSize: 11, color: mutedText(context)),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
