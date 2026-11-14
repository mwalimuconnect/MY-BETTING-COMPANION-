import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'league_data.dart';

class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedLeague = 'PL'; // Default competition code

  final Map<String, String> _leagues = {
    'PL': 'Premier League',
    'CL': 'Champions League',
    'PD': 'La Liga',
    'SA': 'Serie A',
    'BL1': 'Bundesliga',
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Competition:',
                style: TextStyle(fontWeight: FontWeight.bold, color: mutedText(context)),
              ),
              DropdownButton<String>(
                value: _selectedLeague,
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
          itemCount: groups.length,
          itemBuilder: (context, gIndex) {
            final group = groups[gIndex];
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
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: group.rows.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: lineColor(context)),
                    itemBuilder: (context, rIndex) {
                      final row = group.rows[rIndex];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 28,
                          alignment: Alignment.center,
                          child: Text(
                            '${row.position}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: mutedText(context)),
                          ),
                        ),
                        title: Text(
                          row.team,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          'P: ${row.played}  W: ${row.won}  D: ${row.draw}  L: ${row.lost}  GD: ${row.goalDifference > 0 ? "+${row.goalDifference}" : row.goalDifference}',
                          style: TextStyle(fontSize: 11, color: mutedText(context)),
                        ),
                        trailing: Text(
                          '${row.points} pts',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kPrimary),
                        ),
                      );
                    },
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
                subtitle: Text(scorer.team, style: TextStyle(fontSize: 12, color: mutedText(context))),
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
