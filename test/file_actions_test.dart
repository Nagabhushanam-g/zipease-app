import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/file_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zipease.zipease/exports');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 'launched';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Open with and Share forward file and action', () async {
    final first = await FileActions.perform(
      path: '/tmp/photo.jpg', name: 'photo.jpg', action: FileAction.open,
    );
    final second = await FileActions.perform(
      path: '/tmp/photo.jpg', name: 'photo.jpg', action: FileAction.share,
    );
    expect(first, 'launched');
    expect(second, 'launched');
    expect(calls.map((c) => c.method), ['fileAction', 'fileAction']);
    expect((calls.first.arguments as Map)['action'], 'open');
    expect((calls.last.arguments as Map)['action'], 'share');
  });

  test('Only an .apk file can request Android installation', () async {
    expect(
      () => FileActions.perform(
        path: '/tmp/setup.exe', name: 'setup.exe',
        action: FileAction.install,
      ),
      throwsFormatException,
    );
    await FileActions.perform(
      path: '/tmp/APP.APK', name: 'APP.APK', action: FileAction.install,
    );
    expect((calls.single.arguments as Map)['action'], 'install');
  });
}
