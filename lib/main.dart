import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const DataAnalyzerApp());
}

class DataAnalyzerApp extends StatelessWidget {
  const DataAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '数据关联分析',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// 全局状态
class AppState {
  String folderPath = '';
  List<String> files = [];
  Map<String, List<String>> tables = {}; // 文件 -> sheet列表
  Map<String, Map<String, List<String>>> sheetFields = {}; // 文件 -> {sheet名: 字段列表}
  List<Map<String, String>> links = []; // 关联配置
  Map<String, dynamic>? queryResult;
  String? selectedConfig;
  String status = '请选择数据目录';

  Map<String, dynamic> toJson() => {
    'folderPath': folderPath,
    'files': files,
    'tables': tables,
    'sheetFields': sheetFields.map((k, v) => MapEntry(k, v)),
    'links': links,
    'selectedConfig': selectedConfig,
  };

  fromJson(Map<String, dynamic> json) {
    folderPath = json['folderPath'] ?? '';
    files = List<String>.from(json['files'] ?? []);
    tables = (json['tables'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, List<String>.from(v)),
    ) ?? {};
    sheetFields = (json['sheetFields'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, (v as Map<String, dynamic>).map(
        (sk, sv) => MapEntry(sk, List<String>.from(sv)),
      )),
    ) ?? {};
    links = (json['links'] as List?)?.cast<Map<String, String>>() ?? [];
    selectedConfig = json['selectedConfig'];
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppState _state = AppState();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  // 加载配置
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configs = prefs.getString('configs');
    if (configs != null) {
      final configMap = jsonDecode(configs) as Map<String, dynamic>;
      if (configMap.isNotEmpty) {
        final configName = configMap.keys.first;
        _state.fromJson(configMap[configName]);
        _state.selectedConfig = configName;
        setState(() {});
        _updateStatus('已加载配置: $configName');
      }
    }
  }

  // 保存配置
  Future<void> _saveConfig(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final configs = prefs.getString('configs');
    final configMap = configs != null 
      ? jsonDecode(configs) as Map<String, dynamic>
      : <String, dynamic>{};
    
    configMap[name] = _state.toJson();
    await prefs.setString('configs', jsonEncode(configMap));
    _updateStatus('配置已保存: $name');
  }

  void _updateStatus(String msg) {
    setState(() {
      _state.status = msg;
    });
  }

  // 选择目录
  // 选择文件（直接选择Excel文件，不扫描目录）
  Future<void> _selectFolder() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        // 获取文件路径
        final validFiles = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
        
        if (validFiles.isEmpty) {
          _updateStatus('无法访问文件路径，请授予存储权限');
          return;
        }
        
        _state.files = validFiles;
        _state.folderPath = '已选择文件';
        _updateStatus('已选择 ${_state.files.length} 个文件');
        
        // 扫描每个文件的表
        await _scanTables();
      }
    } catch (e) {
      _updateStatus('选择失败: $e');
    }
  }

  // 扫描文件表头
  Future<void> _scanTables() async {
    setState(() => _isLoading = true);
    _updateStatus('扫描中...');
    
    _state.tables = {};
    _state.sheetFields = {};
    
    for (final filePath in _state.files) {
      try {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        
        // 获取所有sheet名
        final sheets = excel.tables.keys.toList();
        _state.tables[filePath] = sheets;
        
        // 读取每个sheet的字段
        final fieldsMap = <String, List<String>>{};
        for (final sheetName in sheets) {
          final sheet = excel.tables[sheetName];
          if (sheet != null && sheet.rows.isNotEmpty) {
            final headers = sheet.rows.first
                .map((c) => c?.value?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toList();
            fieldsMap[sheetName] = headers;
          } else {
            fieldsMap[sheetName] = [];
          }
        }
        _state.sheetFields[filePath] = fieldsMap;
        
      } catch (e) {
        _state.tables[filePath] = [];
        _state.sheetFields[filePath] = {};
      }
    }
    
    _updateStatus('找到 ${_state.files.length} 个Excel文件');
    setState(() => _isLoading = false);
  }

  // 添加关联
  void _addLink() {
    if (_state.files.length < 2) {
      _updateStatus('需要至少2个文件');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => LinkDialog(
        files: _state.files,
        tables: _state.tables,
        sheetFields: _state.sheetFields,
        onAdd: (link) {
          setState(() {
            _state.links.add(link);
          });
          _updateStatus('已添加关联');
        },
      ),
    );
  }

  // 执行查询
  Future<void> _executeQuery() async {
    if (_state.links.isEmpty) {
      _updateStatus('请先添加关联');
      return;
    }

    setState(() => _isLoading = true);
    _updateStatus('查询执行中...');

    try {
      // 简化版：只做第一个关联
      final link = _state.links.first;
      final file1 = link['file1']!;
      final table1 = link['table1']!;
      final file2 = link['file2']!;
      final table2 = link['table2']!;
      final key1 = link['key1']!;
      final key2 = link['key2']!;

      // 读取数据
      final data1 = await _readExcel(file1, table1);
      final data2 = await _readExcel(file2, table2);

      // 执行Inner Join
      final result = _innerJoin(data1, key1, data2, key2);
      
      _state.queryResult = {
        'rows': result,
        'count': result.length,
      };
      
      _updateStatus('查询完成: ${result.length} 条记录');
    } catch (e) {
      _updateStatus('查询失败: $e');
    }

    setState(() => _isLoading = false);
  }

  // 读取Excel
  Future<List<Map<String, dynamic>>> _readExcel(String filePath, String tableName) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[tableName];
    
    if (sheet == null) return [];
    
    final result = <Map<String, dynamic>>[];
    final headers = sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
    
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final map = <String, dynamic>{};
      for (var j = 0; j < headers.length; j++) {
        map[headers[j]] = j < row.length ? row[j]?.value?.toString() : '';
      }
      result.add(map);
    }
    
    return result;
  }

  // Inner Join
  List<Map<String, dynamic>> _innerJoin(
    List<Map<String, dynamic>> data1, String key1,
    List<Map<String, dynamic>> data2, String key2,
  ) {
    final result = <Map<String, dynamic>>[];
    
    for (final row1 in data1) {
      for (final row2 in data2) {
        if (row1[key1]?.toString() == row2[key2]?.toString()) {
          result.add({...row1, ...row2});
        }
      }
    }
    
    return result;
  }

  // 导出Excel
  Future<void> _exportExcel() async {
    if (_state.queryResult == null) {
      _updateStatus('没有查询结果');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      
      final rows = _state.queryResult!['rows'] as List<Map<String, dynamic>>;
      if (rows.isEmpty) {
        _updateStatus('没有数据');
        setState(() => _isLoading = false);
        return;
      }

      // 写入表头
      final headers = rows.first.keys.toList();
      for (var i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      // 写入数据
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r];
        for (var c = 0; c < headers.length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = 
            TextCellValue(row[headers[c]]?.toString() ?? '');
        }
      }

      // 保存
      final outputDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${outputDir.path}/result_$timestamp.xlsx';
      final file = File(outputPath);
      await file.writeAsBytes(excel.encode()!);

      _updateStatus('已导出: $outputPath');
    } catch (e) {
      _updateStatus('导出失败: $e');
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据关联分析'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _showSaveDialog(),
            tooltip: '保存配置',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _loadConfig,
            tooltip: '加载配置',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态显示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue.shade50,
              child: Text(_state.status, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 16),
            
            // 功能按钮
            ElevatedButton.icon(
              onPressed: _selectFolder,
              icon: const Icon(Icons.folder),
              label: const Text('选择Excel文件'),
            ),
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              onPressed: _state.files.length >= 2 ? _addLink : null,
              icon: const Icon(Icons.link),
              label: const Text('添加关联'),
            ),
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              onPressed: _state.links.isNotEmpty ? _executeQuery : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('执行查询'),
            ),
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              onPressed: _state.queryResult != null ? _exportExcel : null,
              icon: const Icon(Icons.download),
              label: const Text('导出Excel'),
            ),
            const SizedBox(height: 16),

            // 文件列表
            if (_state.files.isNotEmpty) ...[
              const Text('文件列表:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _state.files.length,
                  itemBuilder: (ctx, i) {
                    final fileName = _state.files[i].split('/').last;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.description),
                      title: Text(fileName),
                      subtitle: Text('表: ${_state.tables[_state.files[i]]?.join(", ") ?? "无"}'),
                    );
                  },
                ),
              ),
            ],

            // 关联列表
            if (_state.links.isNotEmpty) ...[
              const Text('关联配置:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._state.links.asMap().entries.map((e) => ListTile(
                dense: true,
                leading: const Icon(Icons.link),
                title: Text('${e.value['file1']?.split('/').last}.${e.value['table1']} [${e.value['key1']}] = ${e.value['file2']?.split('/').last}.${e.value['table2']} [${e.value['key2']}]'),
              )),
            ],

            // 结果统计
            if (_state.queryResult != null)
              Text('结果: ${_state.queryResult!['count']} 条记录',
                style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showSaveDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存配置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '配置名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _saveConfig(controller.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// 关联配置对话框 - 支持多sheet，选择sheet后显示字段
class LinkDialog extends StatefulWidget {
  final List<String> files;
  final Map<String, List<String>> tables;  // 文件 -> [sheet1, sheet2, ...]
  final Map<String, Map<String, List<String>>> sheetFields;  // 文件 -> {sheet: [字段...]}
  final Function(Map<String, String>) onAdd;

  const LinkDialog({
    super.key, 
    required this.files, 
    required this.tables, 
    required this.sheetFields,
    required this.onAdd
  });

  @override
  State<LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<LinkDialog> {
  String? file1, file2;
  String? table1, table2;
  String? key1, key2;

  @override
  Widget build(BuildContext context) {
    // 获取文件1的sheet列表和字段
    final sheets1 = file1 != null ? (widget.tables[file1] ?? []) : [];
    final fields1 = (file1 != null && table1 != null) 
        ? (widget.sheetFields[file1]?[table1] ?? []) : [];
    
    // 获取文件2的sheet列表和字段
    final sheets2 = file2 != null ? (widget.tables[file2] ?? []) : [];
    final fields2 = (file2 != null && table2 != null) 
        ? (widget.sheetFields[file2]?[table2] ?? []) : [];

    return AlertDialog(
      title: const Text('添加关联'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== 文件1 =====
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: '文件1'),
              value: file1,
              items: widget.files.map((f) => DropdownMenuItem(
                value: f, child: Text(f.split('/').last, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setState(() {
                file1 = v;
                table1 = null;
                key1 = null;
              }),
            ),
            // 选择Sheet1 - 始终显示（如果选择了文件）
            if (file1 != null) ...[
              if (sheets1.isNotEmpty)
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Sheet1'),
                  value: table1,
                  items: sheets1.map<DropdownMenuItem<String>>((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() {
                    table1 = v;
                    key1 = null;
                  }),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('⚠️ 请重新选择文件', style: TextStyle(color: Colors.red)),
                ),
            ],
            // 选择字段1
            if (file1 != null && table1 != null && fields1.isNotEmpty)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '关联字段1'),
                value: key1,
                items: fields1.map<DropdownMenuItem<String>>((h) => DropdownMenuItem(
                  value: h, child: Text(h, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => key1 = v),
              ),
            
            const SizedBox(height: 12),
            const Center(child: Text('=', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
            const SizedBox(height: 12),
            
            // ===== 文件2 =====
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: '文件2'),
              value: file2,
              items: widget.files.map((f) => DropdownMenuItem(
                value: f, child: Text(f.split('/').last, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setState(() {
                file2 = v;
                table2 = null;
                key2 = null;
              }),
            ),
            // 选择Sheet2 - 始终显示（如果选择了文件）
            if (file2 != null) ...[
              if (sheets2.isNotEmpty)
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Sheet2'),
                  value: table2,
                  items: sheets2.map<DropdownMenuItem<String>>((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() {
                    table2 = v;
                    key2 = null;
                  }),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('⚠️ 请重新选择文件', style: TextStyle(color: Colors.red)),
                ),
            ],
            // 选择字段2
            if (file2 != null && table2 != null && fields2.isNotEmpty)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '关联字段2'),
                value: key2,
                items: fields2.map<DropdownMenuItem<String>>((h) => DropdownMenuItem(
                  value: h, child: Text(h, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => key2 = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () {
            if (file1 != null && table1 != null && key1 != null &&
                file2 != null && table2 != null && key2 != null) {
              widget.onAdd({
                'file1': file1!, 'table1': table1!, 'key1': key1!,
                'file2': file2!, 'table2': table2!, 'key2': key2!,
              });
              Navigator.pop(context);
            }
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}