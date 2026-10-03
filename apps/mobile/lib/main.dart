import 'package:flutter/material.dart';

void main() {
  runApp(const HelpMeMoveApp());
}

class HelpMeMoveApp extends StatelessWidget {
  const HelpMeMoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HelpMeMove',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3C7A62)),
        useMaterial3: true,
      ),
      home: const ScaffoldCheckScreen(),
    );
  }
}

class ScaffoldCheckScreen extends StatefulWidget {
  const ScaffoldCheckScreen({super.key});

  @override
  State<ScaffoldCheckScreen> createState() => _ScaffoldCheckScreenState();
}

class _ScaffoldCheckScreenState extends State<ScaffoldCheckScreen> {
  var _completed = false;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('scaffold-capture'),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('HelpMeMove', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _completed = true;
                      });
                    },
                    child: const Text('Scaffold check'),
                  ),
                  if (_completed)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Scaffold check completed',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
