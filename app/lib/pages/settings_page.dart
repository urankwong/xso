import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ua = TextEditingController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _ua.text = p.getString('ua') ?? '';
    });
  }

  @override
  void dispose() {
    _ua.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            title: TextField(
              controller: _ua,
              decoration: const InputDecoration(
                  labelText: 'User-Agent（留空用默认）'),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                final p = await SharedPreferences.getInstance();
                await p.setString('ua', _ua.text);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已保存（重启生效）')));
                }
              },
            ),
          ),
          const ListTile(
            title: Text('关于'),
            subtitle: Text('聚合搜索空壳 App v0.1.0\n不内置任何搜索源，请自行导入源脚本'),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}
