import 'package:flutter/material.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
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
  var _scaffoldCompleted = false;
  String? _bridgeResult;

  @override
  Widget build(BuildContext context) {
    final bridgeResult = _bridgeResult;
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
                        _scaffoldCompleted = true;
                      });
                    },
                    child: const Text('Scaffold check'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        try {
                          final subject = acceptSubject(raw: 'subject-smoke-1');
                          _bridgeResult = subject == 'subject-smoke-1'
                              ? 'Bridge check completed'
                              : 'Bridge check failed';
                        } on BridgeError {
                          _bridgeResult = 'Bridge check failed';
                        }
                      });
                    },
                    child: const Text('Bridge check'),
                  ),
                  if (_scaffoldCompleted)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Scaffold check completed',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (bridgeResult != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(bridgeResult, textAlign: TextAlign.center),
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
