import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

class FileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String mimeType;

  FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.mimeType,
  });

  String get formattedSize {
    if (isDirectory) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData get icon {
    if (isDirectory) return Icons.folder;
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf;
    if (mimeType.startsWith('text/')) return Icons.text_snippet;
    if (mimeType == 'application/zip' ||
        mimeType == 'application/x-rar-compressed' ||
        mimeType == 'application/x-7z-compressed') return Icons.archive;
    if (mimeType == 'application/vnd.android.package-archive') return Icons.android;
    return Icons.insert_drive_file;
  }

  Color get iconColor {
    if (isDirectory) return Colors.amber.shade700;
    if (mimeType.startsWith('image/')) return Colors.blue;
    if (mimeType.startsWith('video/')) return Colors.purple;
    if (mimeType.startsWith('audio/')) return Colors.orange;
    if (mimeType == 'application/pdf') return Colors.red;
    if (mimeType.startsWith('text/')) return Colors.green;
    if (mimeType == 'application/vnd.android.package-archive') return Colors.green.shade700;
    return Colors.grey.shade600;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentPath = '';
  List<FileItem> _items = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  String _sortBy = 'name';
  bool _sortAscending = true;
  bool _selectMode = false;
  Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _initStorage();
  }

  Future<void> _initStorage() async {
    await _requestPermissions();
    final dir = await getExternalStorageDirectory();
    if (dir != null) {
      _currentPath = dir.path;
      _loadDirectory();
    }
  }

  Future<void> _requestPermissions() async {
    if (await Permission.manageExternalStorage.isGranted) return;
    if (await Permission.storage.isGranted) return;
    
    await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();
  }

  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);
    
    try {
      final dir = Directory(_currentPath);
      if (!await dir.exists()) {
        _showError('Folder tidak ditemukan');
        return;
      }

      final entities = await dir.list().toList();
      final items = <FileItem>[];

      for (final entity in entities) {
        try {
          final stat = await entity.stat();
          final name = p.basename(entity.path);
          
          // Skip hidden files
          if (name.startsWith('.')) continue;

          String mimeType = 'unknown';
          if (!stat.type == FileSystemEntityType.directory) {
            mimeType = lookupMimeType(entity.path) ?? 'application/octet-stream';
          }

          items.add(FileItem(
            name: name,
            path: entity.path,
            isDirectory: stat.type == FileSystemEntityType.directory,
            size: stat.size,
            modified: stat.modified,
            mimeType: mimeType,
          ));
        } catch (e) {
          // Skip files we can't read
        }
      }

      _sortItems(items);
      setState(() {
        _items = items;
        _isLoading = false;
        _selectMode = false;
        _selectedPaths.clear();
      });
    } catch (e) {
      _showError('Gagal baca folder: $e');
    }
  }

  void _sortItems(List<FileItem> items) {
    items.sort((a, b) {
      int compare = 0;
      if (_sortBy == 'name') {
        compare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      } else if (_sortBy == 'size') {
        compare = a.size.compareTo(b.size);
      } else if (_sortBy == 'date') {
        compare = a.modified.compareTo(b.modified);
      } else if (_sortBy == 'type') {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        compare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? compare : -compare;
    });
  }

  List<FileItem> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;
    return _items.where((item) => 
      item.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  void _onItemTap(FileItem item) {
    if (_selectMode) {
      _toggleSelect(item.path);
      return;
    }

    if (item.isDirectory) {
      setState(() {
        _currentPath = item.path;
      });
      _loadDirectory();
    } else {
      _openFile(item);
    }
  }

  void _onItemLongPress(FileItem item) {
    if (!_selectMode) {
      setState(() => _selectMode = true);
    }
    _toggleSelect(item.path);
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
      if (_selectedPaths.isEmpty) _selectMode = false;
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedPaths.length == _filteredItems.length) {
        _selectedPaths.clear();
        _selectMode = false;
      } else {
        _selectedPaths = _filteredItems.map((e) => e.path).toSet();
      }
    });
  }

  Future<void> _openFile(FileItem item) async {
    try {
      await Process.run('xdg-open', [item.path]);
    } catch (e) {
      _showError('Tidak bisa buka file');
    }
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus file?'),
        content: Text('Yakin hapus ${_selectedPaths.length} item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );

    if (confirm != true) return;

    for (final path in _selectedPaths) {
      try {
        final entity = FileSystemEntity.typeSync(path);
        if (entity == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
        } else {
          await File(path).delete();
        }
      } catch (e) {
        _showError('Gagal hapus $path: $e');
      }
    }
    _loadDirectory();
  }

  Future<void> _renameItem(FileItem item) async {
    final controller = TextEditingController(text: item.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nama baru'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty && result != item.name) {
      final newPath = p.join(p.dirname(item.path), result.trim());
      try {
        if (item.isDirectory) {
          await Directory(item.path).rename(newPath);
        } else {
          await File(item.path).rename(newPath);
        }
        _loadDirectory();
      } catch (e) {
        _showError('Gagal rename: $e');
      }
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buat Folder Baru'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nama folder'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Buat')),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      try {
        await Directory(p.join(_currentPath, result.trim())).create();
        _loadDirectory();
      } catch (e) {
        _showError('Gagal buat folder: $e');
      }
    }
  }

  Future<void> _pasteFiles() async {
    // TODO: implement copy/move
  }

  void _goUp() {
    final parent = p.dirname(_currentPath);
    if (parent != _currentPath) {
      setState(() => _currentPath = parent);
      _loadDirectory();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Cari file...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectMode ? '${_selectedPaths.length} dipilih' : 'File Manager'),
                  Text(
                    _currentPath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        leading: _showSearch
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _showSearch = false;
                  _searchQuery = '';
                  _searchController.clear();
                }),
              )
            : (_currentPath != (Platform.isAndroid ? '/storage/emulated/0' : '/')
                ? IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _goUp)
                : null),
        actions: [
          if (!_showSearch && !_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _showSearch = true),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                setState(() {
                  _sortBy = v;
                  _sortAscending = true;
                  _sortItems(_items);
                });
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'name', child: Text('Nama')),
                const PopupMenuItem(value: 'size', child: Text('Ukuran')),
                const PopupMenuItem(value: 'date', child: Text('Tanggal')),
                const PopupMenuItem(value: 'type', child: Text('Tipe')),
              ],
              icon: const Icon(Icons.sort),
            ),
            IconButton(
              icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
              onPressed: () => setState(() {
                _sortAscending = !_sortAscending;
                _sortItems(_items);
              }),
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              onPressed: _createFolder,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'theme') {
                  // theme handled by system
                } else if (v == 'about') {
                  showAboutDialog(
                    context: context,
                    applicationName: 'APK File Manager',
                    applicationVersion: '1.0.0',
                    children: [const Text('File manager sederhana, tanpa iklan')],
                  );
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'theme', child: Text('Tema (System)')),
                const PopupMenuItem(value: 'about', child: Text('Tentang')),
              ],
            ),
          ],
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _selectedPaths.isNotEmpty ? _deleteSelected : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedPaths.clear();
              }),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('Folder kosong', style: theme.textTheme.titleMedium),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredItems.length,
                  itemBuilder: (ctx, i) {
                    final item = _filteredItems[i];
                    final isSelected = _selectedPaths.contains(item.path);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected 
                            ? theme.colorScheme.primary 
                            : item.iconColor.withOpacity(0.15),
                        child: Icon(
                          isSelected ? Icons.check : item.icon,
                          color: isSelected ? Colors.white : item.iconColor,
                        ),
                      ),
                      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: item.isDirectory 
                          ? null 
                          : Text('${item.formattedSize} • ${_formatDate(item.modified)}'),
                      trailing: _selectMode ? null : PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'rename') _renameItem(item);
                          if (v == 'delete') _deleteItem(item);
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'rename', child: Text('Rename')),
                          const PopupMenuItem(value: 'delete', child: Text('Hapus')),
                        ],
                      ),
                      selected: isSelected,
                      onTap: () => _onItemTap(item),
                      onLongPress: () => _onItemLongPress(item),
                    );
                  },
                ),
      floatingActionButton: _selectMode ? null : FloatingActionButton(
        onPressed: _createFolder,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _deleteItem(FileItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus?'),
        content: Text('Yakin hapus ${item.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        if (item.isDirectory) {
          await Directory(item.path).delete(recursive: true);
        } else {
          await File(item.path).delete();
        }
        _loadDirectory();
      } catch (e) {
        _showError('Gagal hapus: $e');
      }
    }
  }

  String _formatDate(DateTime d) {
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}