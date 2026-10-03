import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/buddy_brand.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BuddyMark(size: 112),
                const SizedBox(height: 36),
                Text(
                  'AksharBuddy',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Words feel better\nwith a buddy.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 36,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Read, listen, and understand.\nOne comfortable step at a time.',
                ),
                const SizedBox(height: 32),
                const BuddyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Made for your way of reading'),
                      SizedBox(height: 12),
                      Text(
                        'Adjust the page. Hear the words. Keep what you learn.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    var signedIn = false;
                    try {
                      signedIn = FirebaseAuth.instance.currentUser != null;
                    } catch (_) {
                      /* Startup handles initialization. */
                    }
                    Navigator.pushReplacementNamed(
                      context,
                      signedIn ? '/home' : '/login',
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: Text('Let’s begin')),
                      SizedBox(width: 12),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/home'),
                  child: const Text('Try without an account'),
                ),
                const SizedBox(height: 20),
                Text(
                  'English · Hindi · Marathi',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
