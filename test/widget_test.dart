import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tv_paraguay/main.dart';

void main() {
  testWidgets('TV Paraguay inicia correctamente', (WidgetTester tester) async {
    final fixture = jsonEncode([
      {
        'id': 2,
        'name': 'TELEFUTURO',
        'shortName': 'TF',
        'category': 'Nacional',
        'playerType': 'hls',
        'streamUrl': 'https://example.test/live.m3u8',
        'httpHeaders': <String, String>{},
        'isActive': true,
      },
    ]);
    await http.runWithClient(() async {
      await tester.pumpWidget(const TvParaguayApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('TV Paraguay'), findsOneWidget);
      expect(find.text('TELEFUTURO'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response(fixture, 200)));
  });
}
