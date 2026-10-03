import 'package:flutter/material.dart';
import '../services/buddy_store.dart';
import '../widgets/buddy_brand.dart';

class ProgressScreen extends StatelessWidget {
  final DateTime? today;
  const ProgressScreen({super.key, this.today});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: BuddyStore.notifier,
    builder: (context, _, _) {
      final now = today ?? DateTime.now();
      final seconds = BuddyStore.secondsOn(now);
      final fraction = (seconds / (BuddyStore.goalMinutes * 60)).clamp(
        0.0,
        1.0,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BuddyHeading(
            'Your progress',
            'Your pace counts. Breaks are welcome, too.',
          ),
          BuddyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today’s reading',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '${seconds ~/ 60} of ${BuddyStore.goalMinutes} minutes',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: fraction,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  semanticsLabel: 'Daily reading goal',
                ),
                const SizedBox(height: 16),
                const Text('A goal is an invitation, not a deadline.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: {3, 5, 10, 15, BuddyStore.goalMinutes}
                      .map(
                        (m) => ChoiceChip(
                          label: Text('$m min'),
                          selected: BuddyStore.goalMinutes == m,
                          onSelected: (_) async {
                            try {
                              await BuddyStore.setGoal(m);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not save your goal.'),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BuddyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reading days',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '${BuddyStore.currentStreak(now)} day current streak · ${BuddyStore.bestStreak} day best',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (i) {
                    final day = DateTime(now.year, now.month, now.day - 6 + i);
                    final done = BuddyStore.secondsOn(day) > 0;
                    return Semantics(
                      label:
                          '${day.day}/${day.month}: ${done ? 'reading completed' : 'no completed reading'}',
                      child: Container(
                        width: 56,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: done
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              done ? Icons.check : Icons.remove,
                              color: done
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                            Text(
                              '${day.day}/${day.month}',
                              style: TextStyle(
                                fontSize: 12,
                                color: done
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BuddyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time you made for reading',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '${BuddyStore.totalSeconds ~/ 60} minutes · ${BuddyStore.sessions.length} completed sessions',
                ),
                const SizedBox(height: 8),
                Text('${BuddyStore.totalWords} words in completed readings'),
                const SizedBox(height: 12),
                const Text(
                  'Start a session in the reader and tap Finish when you are done. Time pauses when you leave the app. Word totals count the passages you finish, not a reading assessment.',
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
