import 'package:flutter_forumhub/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('ForumHub app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ForumHubApp(),
      ),
    );
    await tester.pump();

    expect(find.text('ForumHub'), findsWidgets);
  });
}
