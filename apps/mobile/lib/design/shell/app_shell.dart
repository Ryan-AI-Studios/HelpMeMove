import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_breakpoints.dart';
import 'package:helpmemove/design/app_colors.dart';

/// Compact bar below 600 dp. Rail at 600 dp and above.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool rail = width >= AppBreakpoints.compact;
    final String path = GoRouterState.of(context).uri.path;
    final int selectedIndex = path == '/foundations' ? 1 : 0;
    final AppColors colors = appColorsOf(context);

    void select(int index) {
      context.go(index == 0 ? '/' : '/foundations');
    }

    return RepaintBoundary(
      key: const Key('scaffold-capture'),
      child: Scaffold(
        body: rail
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: select,
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: colors.surface,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.palette),
                        label: Text('Foundations'),
                      ),
                    ],
                  ),
                  Expanded(child: child),
                ],
              )
            : child,
        bottomNavigationBar: rail
            ? null
            : NavigationBar(
                height: 72,
                backgroundColor: colors.surface,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                selectedIndex: selectedIndex,
                onDestinationSelected: select,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.palette),
                    label: 'Foundations',
                  ),
                ],
              ),
      ),
    );
  }
}
