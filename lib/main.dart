import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 请求存储权限 (Android)
  if (Platform.isAndroid) {
    try {
      // 尝试请求存储权限
      const methodChannel = MethodChannel('com.example.data_analyzer/permissions');
      await methodChannel.invokeMethod('requestStoragePermission');
    } catch (e) {
      // 权限请求失败忽略，继续尝试
    }
  }
  
  runApp(const DataAnalyzerApp());
}

class DataAnalyzerApp extends StatelessWidget {
  const DataAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '数据关联分析',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = '请选择CSV文件';
  List<String> _files = [];
  Map<String, List<String>> _headers = {};  // file -> headers
  Map<String, List<List<dynamic>>> _data = {};  // file -> rows
  List<Map<String, String>> _links = [];
  List<Map<String, dynamic>>? _queryResult;
  bool _loading = false;

  void _updateStatus(String msg) {
    setState(() => _status = msg);
  }

  Future<void> _selectFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        _files = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
        
        if (_files.isEmpty) {
          _updateStatus('无法访问文件路径');
          return;
        }
        
        _updateStatus('已选择 ${_files.length} 个文件');
        await _scanFiles();
      }
    } catch (e) {
      _updateStatus('选择失败: $e');
    }
  }

  Future<void> _scanFiles() async {
    if (_files.isEmpty) return;
    
    setState(() => _loading = true);
    _updateStatus('扫描中...');
    
    _headers = {};
    _data = {};

    for (final filePath in _files) {
      try {
        final file = File(filePath);
        final content = await file.readAsString();
        final rows = const CsvToListConverter().convert(content);
        
        if (rows.isNotEmpty) {
          _headers[filePath] = rows.first.map((e) => e.toString()).toList();
          _data[filePath] = rows;
        }
      } catch (e) {
        _headers[filePath] = [];
        _data[filePath] = [];
      }
    }

    setState(() {
      _loading = false;
      _status = '找到 ${_files.length} 个CSV文件';
    });
  }

  void _addLink() {
    if (_files.length < 2) {
      _updateStatus('需要至少2个文件');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => LinkDialog(
        files: _files,
        headers: _headers,
        onAdd: (link) {
          setState(() => _links.add(link));
          _updateStatus('已添加关联 (${_links.length})');
        },
      ),
    );
  }

  Future<void> _executeQuery() async {
    if (_links.isEmpty) {
      _updateStatus('请先添加关联');
      return;
    }

    setState(() {
      _loading = true;
      _status = '查询中...';
    });

    try {
      List<Map<String, dynamic>> result = [];
      
      for (final link in _links) {
        final file1 = link['file1']!;
        final file2 = link['file2']!;
        final key1 = link['key1']!;
        final key2 = link['key2']!;
        
        final data1 = _parseData(file1);
        final data2 = _parseData(file2);
        
        final joined = _innerJoin(data1, key1, data2, key2);
        
        if (result.isEmpty) {
          result = joined;
        } else if (joined.isNotEmpty) {
          // 多重关联
          final lastLink = _links.last;
          result = _innerJoin(result, lastLink['key2']!, joined, key1);
        }
      }
      
      setState(() {
        _queryResult = result;
        _status = '查询完成: ${result.length} 条记录';
      });
    } catch (e) {
      _updateStatus('查询失败: $e');
    }

    setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _parseData(String filePath) {
    final rows = _data[filePath];
    if (rows == null || rows.isEmpty) return [];
    
    final headers = _headers[filePath] ?? [];
    final result = <Map<String, dynamic>>[];
    
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final map = <String, dynamic>{};
      for (var j = 0; j < headers.length; j++) {
        map[headers[j]] = j < row.length ? row[j].toString() : '';
      }
      result.add(map);
    }
    
    return result;
  }

  List<Map<String, dynamic>> _innerJoin(
    List<Map<String, dynamic>> data1, String key1,
    List<Map<String, dynamic>> data2, String key2,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final row1 in data1) {
      for (final row2 in data2) {
        if (row1[key1]?.toString().trim() == row2[key2]?.toString().trim()) {
          result.add({...row1, ...row2});
        }
      }
    }
    return result;
  }

  void _previewResult() {
    if (_queryResult == null || _queryResult!.isEmpty) {
      _updateStatus('没有查询结果');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => ResultDialog(result: _queryResult!),
    );
  }

  void _clearAll() {
    setState(() {
      _files = [];
      _headers = {};
      _data = {};
      _links = [];
      _queryResult = null;
      _status = '已清空';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据关联分析'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearAll, tooltip: '清空'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.blue.shade50,
                    child: Text(_status),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _selectFiles,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('选择CSV文件'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_files.isNotEmpty) ...[
                    const Text('📁 文件列表:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._files.asMap().entries.map((e) {
                      final file = e.value;
                      final name = file.split('/').last;
                      final hdrs = _headers[file] ?? [];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.description),
                          title: Text(name),
                          subtitle: Text('字段: ${hdrs.take(5).join(", ")}${hdrs.length > 5 ? "..." : ""}'),
                          dense: true,
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                  ElevatedButton.icon(
                    onPressed: _files.length >= 2 ? _addLink : null,
                    icon: const Icon(Icons.link),
                    label: Text('添加关联 (${_links.length})'),
                  ),
                  const SizedBox(height: 8),
                  if (_links.isNotEmpty) ...[
                    const Text('🔗 关联配置:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ..._links.asMap().entries.map((e) {
                      final link = e.value;
                      final f1 = link['file1']!.split('/').last;
                      final f2 = link['file2']!.split('/').last;
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.link),
                          title: Text('$f1 [${link['key1']}] = $f2 [${link['key2']}]'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => setState(() => _links.removeAt(e.key)),
                          ),
                          dense: true,
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _links.isNotEmpty ? _executeQuery : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('执行查询'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _queryResult != null ? _previewResult : null,
                          icon: const Icon(Icons.visibility),
                          label: Text('预览${_queryResult != null ? "(${_queryResult!.length})" : ""}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey.shade100,
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('📖 使用说明:', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('1. 选择CSV文件（支持多选）'),
                        Text('2. 点击"添加关联"选择两个文件的关联字段'),
                        Text('3. 点击"执行查询"进行Inner Join'),
                        Text('4. 点击"预览"查看结果'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// 关联配置对话框 - 让用户选择字段
class LinkDialog extends StatefulWidget {
  final List<String> files;
  final Map<String, List<String>> headers;
  final Function(Map<String, String>) onAdd;

  const LinkDialog({super.key, required this.files, required this.headers, required this.onAdd});

  @override
  State<LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<LinkDialog> {
  String? _file1;
  String? _file2;
  String? _key1;
  String? _key2;

  @override
  Widget build(BuildContext context) {
    final List<String> headers1 = _file1 != null ? (widget.headers[_file1] ?? []) : [];
    final List<String> headers2 = _file2 != null ? (widget.headers[_file2] ?? []) : [];

    return AlertDialog(
      title: const Text('添加关联'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 文件1选择
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: '文件1'),
              value: _file1,
              items: widget.files.map((f) => DropdownMenuItem(
                value: f, 
                child: Text(f.split('/').last, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setState(() { _file1 = v; _key1 = null; }),
            ),
            // 文件1的字段选择
            if (_file1 != null && headers1.isNotEmpty)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '关联字段1'),
                value: _key1,
                items: headers1.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                onChanged: (v) => setState(() => _key1 = v),
              ),
            
            const SizedBox(height: 12),
            const Center(child: Text('=', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
            const SizedBox(height: 12),
            
            // 文件2选择
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: '文件2'),
              value: _file2,
              items: widget.files.map((f) => DropdownMenuItem(
                value: f, 
                child: Text(f.split('/').last, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setState(() { _file2 = v; _key2 = null; }),
            ),
            // 文件2的字段选择
            if (_file2 != null && headers2.isNotEmpty)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '关联字段2'),
                value: _key2,
                items: headers2.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                onChanged: (v) => setState(() => _key2 = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () {
            if (_file1 != null && _file2 != null && _key1 != null && _key2 != null) {
              widget.onAdd({
                'file1': _file1!, 
                'key1': _key1!,
                'file2': _file2!, 
                'key2': _key2!,
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

// 结果预览对话框
class ResultDialog extends StatelessWidget {
  final List<Map<String, dynamic>> result;

  const ResultDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) {
      return const AlertDialog(title: Text('结果'), content: Text('无数据'));
    }

    final headers = result.first.keys.toList();

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('结果 (${result.length}条)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: Table(
                    border: TableBorder.all(color: Colors.grey),
                    defaultColumnWidth: const FixedColumnWidth(100),
                    children: [
                      // 表头
                      TableRow(
                        children: headers.map((h) => Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.grey.shade200,
                          child: Text(h, style: const TextStyle(fontWeight: FontWeight.bold)),
                        )).toList(),
                      ),
                      // 数据行（最多显示50条）
                      ...result.take(50).map((row) => TableRow(
                        children: headers.map((h) => Container(
                          padding: const EdgeInsets.all(8),
                          child: Text(row[h]?.toString() ?? '', overflow: TextOverflow.ellipsis),
                        )).toList(),
                      )),
                    ],
                  ),
                ),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      ),
    );
  }
}