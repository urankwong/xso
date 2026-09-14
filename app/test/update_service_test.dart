import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/providers/update_service.dart';

/// 「从 GitHub 更新」的离线判定测试：版本解析/比较、Release JSON、按 ABI 选包。
/// 不发真实网络请求（CI 与沙箱里都不该依赖 api.github.com 可达）。
void main() {
  group('AppVersion', () {
    test('解析 tag 与 pubspec 版本号写法', () {
      expect(AppVersion.parse('v0.1.0+6')!.parts, [0, 1, 0]);
      expect(AppVersion.parse('v0.1.0+6')!.build, 6);
      expect(AppVersion.parse('0.1.0')!.build, 0);
      expect(AppVersion.parse('v0.1.0+6')!.display, '0.1.0+6');
      expect(AppVersion.parse('v1.2')!.parts, [1, 2]);
      expect(AppVersion.parse(''), isNull);
      expect(AppVersion.parse('v'), isNull);
    });

    test('构建号也认 `-7`，非数字后缀（beta）判为无法解析', () {
      expect(AppVersion.parse('v0.1.0-7')!.display, '0.1.0+7');
      expect(
        AppVersion.parse('v0.1.0-7')!.compareTo(AppVersion.parse('0.1.0+6')!),
        greaterThan(0),
      );
      expect(AppVersion.parse('v0.1.0-beta1'), isNull);
    });

    test('构建号参与比较（同版本多次发 Release 也能检测到更新）', () {
      final a = AppVersion.parse('0.1.0+5')!;
      final b = AppVersion.parse('0.1.0+6')!;
      expect(b.compareTo(a), greaterThan(0));
      expect(a.compareTo(b), lessThan(0));
      expect(a.compareTo(AppVersion.parse('v0.1.0+5')!), 0);
    });

    test('主版本优先于构建号，缺段按 0 补齐', () {
      expect(
        AppVersion.parse('0.2.0+1')!.compareTo(AppVersion.parse('0.1.0+99')!),
        greaterThan(0),
      );
      expect(AppVersion.parse('0.1')!.compareTo(AppVersion.parse('0.1.0')!), 0);
      expect(
        AppVersion.parse('1.0.0')!.compareTo(AppVersion.parse('0.9.9+9')!),
        greaterThan(0),
      );
    });
  });

  group('evaluate', () {
    test('有新版 → available 并带资产', () {
      final res = UpdateService.evaluate(_releaseJson('v0.1.0+7'),
          current: AppVersion.parse('0.1.0+6'), abiHint: 'arm64-v8a');
      expect(res.status, UpdateStatus.available);
      expect(res.asset?.name, 'app-arm64-v8a-release.apk');
      expect(res.release?.changelog, contains('更新说明'));
    });

    test('已是最新 → upToDate，不弹更新框', () {
      final res = UpdateService.evaluate(_releaseJson('v0.1.0+6'),
          current: AppVersion.parse('0.1.0+6'));
      expect(res.status, UpdateStatus.upToDate);
      expect(res.hasUpdate, isFalse);
    });

    test('本地比远端新（测试包/回滚）→ 也判为无需更新', () {
      final res = UpdateService.evaluate(_releaseJson('v0.1.0+3'),
          current: AppVersion.parse('0.1.0+6'));
      expect(res.status, UpdateStatus.upToDate);
    });

    test('tag 无法解析 → failed 而非崩', () {
      final res = UpdateService.evaluate(_releaseJson('nightly-latest'),
          current: AppVersion.parse('0.1.0+6'));
      expect(res.status, UpdateStatus.failed);
      expect(res.error, isNotEmpty);
    });

    test('读不到自身版本时不误报有新版', () {
      final res = UpdateService.evaluate(_releaseJson('v9.9.9+9'));
      expect(res.status, UpdateStatus.failed);
      expect(res.hasUpdate, isFalse);
    });
  });

  group('pickAsset', () {
    final assets = [
      'app-debug.apk',
      'app-arm64-v8a-release.apk',
      'app-armeabi-v7a-release.apk',
    ]
        .map((n) => ReleaseAsset(n, 'https://x/$n', 100))
        .toList();

    test('按设备架构选包', () {
      expect(UpdateService.pickAsset(assets, abiHint: 'armeabi-v7a')!.name,
          'app-armeabi-v7a-release.apk');
      expect(UpdateService.pickAsset(assets, abiHint: 'arm64-v8a')!.name,
          'app-arm64-v8a-release.apk');
    });

    test('拿不到架构时默认 arm64 release', () {
      expect(UpdateService.pickAsset(assets)!.name, 'app-arm64-v8a-release.apk');
    });

    test('只有 debug 包时退回任意 APK；无 APK 返回 null', () {
      final onlyDebug = [
        ReleaseAsset('app-debug.apk', 'u', 1),
        ReleaseAsset('notes.txt', 'u', 1),
      ];
      expect(UpdateService.pickAsset(onlyDebug, abiHint: 'riscv64')!.name,
          'app-debug.apk');
      expect(
          UpdateService.pickAsset([ReleaseAsset('source.zip', 'u', 1)]), isNull);
    });
  });

  group('节流与跳过版本', () {
    test('24h 内不重复静默检查', () async {
      SharedPreferences.setMockInitialValues({
        'update_last_check_at': DateTime.now().millisecondsSinceEpoch,
      });
      expect(await UpdateService.shouldAutoCheck(), isFalse);
    });

    test('超过间隔后允许检查', () async {
      SharedPreferences.setMockInitialValues({
        'update_last_check_at': DateTime.now()
                .subtract(const Duration(hours: 25))
                .millisecondsSinceEpoch ~/
            1,
      });
      expect(await UpdateService.shouldAutoCheck(), isTrue);
    });

    test('跳过某版本后该版本不再提示', () async {
      SharedPreferences.setMockInitialValues({});
      await UpdateService.skipVersion('v0.1.0+7');
      expect(await UpdateService.isSkipped('v0.1.0+7'), isTrue);
      expect(await UpdateService.isSkipped('v0.1.0+8'), isFalse);
    });
  });
}

Map<String, dynamic> _releaseJson(String tag) => {
      'tag_name': tag,
      'name': '汇搜 $tag',
      'body': '## 更新说明\n- 应用内检查更新',
      'assets': [
        {
          'name': 'app-debug.apk',
          'browser_download_url': 'https://github.com/x/app-debug.apk',
          'size': 170000000,
        },
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url':
              'https://github.com/x/app-arm64-v8a-release.apk',
          'size': 60000000,
        },
        {
          'name': 'app-armeabi-v7a-release.apk',
          'browser_download_url':
              'https://github.com/x/app-armeabi-v7a-release.apk',
          'size': 55000000,
        },
      ],
    };
