// Basic smoke test — verifies the app boots to the StudyVault home tab
// without throwing, since this app has no counter to test against.

import 'package:flutter_test/flutter_test.dart';

import 'package:gallery_on_the_go/main.dart';

void main() {
  testWidgets('App launches to StudyVault shell', (WidgetTester tester) async {
    await tester.pumpWidget(const GalleryOnTheGoApp());
    await tester.pump();

    expect(find.text('StudyVault'), findsWidgets);
  });
}
