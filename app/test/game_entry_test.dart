import 'package:dosbox_cn/models/game_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameEntry catalog parsing & presets', () {
    const sampleJson = '''
    {
      "games": {
        "仙剑奇侠传": {
          "identifier": "仙剑奇侠传",
          "name": {
            "zh-Hans": "仙剑奇侠传",
            "zh-Hant": "仙劍奇俠傳",
            "en": "The Legend of Sword and Fairy"
          },
          "releaseYear": 1995,
          "type": "RPG",
          "executable": "PAL!.EXE",
          "keymaps": {
            "←→↑↓": "移动",
            "Alt": "菜单"
          },
          "coverFilename": "cover.png",
          "sha256": "ef209d15734a9e2e533d9a73f2550b3524be5c4cfd5b0ed68c82df6638784adb",
          "filesize": 20272189
        },
        "模拟城市2000": {
          "identifier": "模拟城市2000",
          "name": {
            "zh-Hans": "模拟城市 2000",
            "zh-Hant": "模擬城市 2000",
            "en": "SimCity 2000"
          },
          "releaseYear": 1993,
          "type": "SIM",
          "executable": "SC2000.EXE",
          "cheats": {
            "cass": "得到金钱250元"
          },
          "coverFilename": "cover.jpg",
          "filesize": 2912768
        }
      }
    }
    ''';

    test('parses catalog entries and metadata accurately', () {
      final games = GameEntry.parseCatalogJson(sampleJson);
      expect(games.length, 2);

      final pal = games.firstWhere((g) => g.identifier == '仙剑奇侠传');
      expect(pal.displayName, '仙剑奇侠传');
      expect(pal.releaseYear, 1995);
      expect(pal.executable, 'PAL!.EXE');
      expect(pal.defaultControlMode, ControlMode.rpgPad);
      expect(pal.formattedSize, '19.3 MB');
      expect(pal.keymaps['Alt'], '菜单');
      expect(
        pal.downloadUrl('https://dos-bin.zczc.cz/'),
        'https://dos-bin.zczc.cz/%E4%BB%99%E5%89%91%E5%A5%87%E4%BE%A0%E4%BC%A0.zip',
      );
      expect(
        pal.coverUrl('https://raw.githubusercontent.com/rwv/chinese-dos-games/master/img/'),
        'https://raw.githubusercontent.com/rwv/chinese-dos-games/master/img/%E4%BB%99%E5%89%91%E5%A5%87%E4%BE%A0%E4%BC%A0/cover.png',
      );
    });

    test('assigns touchpad mouse mode for SIM games and supports search', () {
      final games = GameEntry.parseCatalogJson(sampleJson);
      final sim = games.firstWhere((g) => g.identifier == '模拟城市2000');
      expect(sim.defaultControlMode, ControlMode.touchpadMouse);
      expect(sim.cheats['cass'], '得到金钱250元');
      expect(sim.matchesQuery('simcity'), isTrue);
      expect(sim.matchesQuery('仙剑'), isFalse);
    });
  });
}
