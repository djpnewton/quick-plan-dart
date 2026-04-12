import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quick_plan/main.dart';
import 'package:quick_plan/src/ui/run_state.dart';

void main() {
  testWidgets('QuickPlanApp renders HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RunState(),
        child: const QuickPlanApp(),
      ),
    );
    expect(find.text('Quick Plan'), findsAtLeastNWidgets(1));
  });
}
