import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const CopyCrafterApp());
}

class CopyCrafterApp extends StatelessWidget {
  const CopyCrafterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CopyCrafter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Project types supported by the app
enum ProjectType {
  none,
  xcode,
  dotNet,
  android,
  flutter,
  // Add more project types as needed
}

// Custom file tree node
class FileNode {
  final String path;
  final String name;
  final bool isDirectory;
  List<FileNode> children;
  bool isExpanded;
  bool isSelected;

  FileNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.children = const [],
    this.isExpanded = false,
    this.isSelected = false,
  });
}

// Project-specific node (base class)
class ProjectNode {
  final String id;
  final String name;
  final String? path;
  final String? fullPath;
  final String type; // 'group' or 'file'
  List<ProjectNode> children;
  bool isExpanded;
  bool isSelected;

  ProjectNode({
    required this.id,
    required this.name,
    this.path,
    this.fullPath,
    required this.type,
    this.children = const [],
    this.isExpanded = false,
    this.isSelected = false,
  });
}

// Xcode Project Node
class XcodeNode extends ProjectNode {
  XcodeNode({
    required super.id,
    required super.name,
    super.path,
    super.fullPath,
    required super.type,
    super.children,
    super.isExpanded,
    super.isSelected,
  });

  // Factory constructor to create from JSON
  factory XcodeNode.fromJson(Map<String, dynamic> json) {
    List<ProjectNode> childrenNodes = [];

    if (json.containsKey('children') && json['children'] is List) {
      for (var child in json['children']) {
        childrenNodes.add(XcodeNode.fromJson(child));
      }
    }

    return XcodeNode(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      path: json['path'],
      fullPath: json['fullPath'],
      type: json['type'] ?? 'unknown',
      children: childrenNodes,
    );
  }
}

// .NET Project Node
class DotNetNode extends ProjectNode {
  DotNetNode({
    required super.id,
    required super.name,
    super.path,
    super.fullPath,
    required super.type,
    super.children,
    super.isExpanded,
    super.isSelected,
  });

  // Factory constructor to create from JSON
  factory DotNetNode.fromJson(Map<String, dynamic> json) {
    List<ProjectNode> childrenNodes = [];

    if (json.containsKey('children') && json['children'] is List) {
      for (var child in json['children']) {
        childrenNodes.add(DotNetNode.fromJson(child));
      }
    }

    return DotNetNode(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      path: json['path'],
      fullPath: json['fullPath'],
      type: json['type'] ?? 'unknown',
      children: childrenNodes,
    );
  }
}

enum ViewMode { fileSystem, projectStructure }

class _HomePageState extends State<HomePage> {
  String? _selectedDirectory;
  List<FileNode> _nodes = [];
  ProjectNode? _projectNode;
  List<String> _selectedFiles = [];
  List<String> _selectedFolders = []; // Track selected folders
  bool _isLoading = false;
  bool _isCopying = false;
  int _linesToSkip = 7;
  ViewMode _viewMode = ViewMode.fileSystem;
  ProjectType _projectType = ProjectType.none;
  String _searchQuery = ''; // Add search query
  final TextEditingController _searchController = TextEditingController(); // Add search controller
  int _totalTokenCount = 0; // Add token count
  Map<String, int> _fileTokenCounts = {}; // Store token counts per file
  bool _isProcessingFolder = false; // Track if folder is being processed
  String _processingStatus = ''; // Current processing status message
  int _processedFiles = 0; // Number of files processed
  int _totalFilesToProcess = 0; // Total files to process
  bool _progressDialogShown = false; // Track if progress dialog is shown

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showProgressDialog() {
    if (!_progressDialogShown && mounted) {
      _progressDialogShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ProgressDialogWidget(
          getProcessedFiles: () => _processedFiles,
          getTotalFiles: () => _totalFilesToProcess,
          getStatus: () => _processingStatus,
          getIsProcessing: () => _isProcessingFolder,
        ),
      );
    }
  }

  void _hideProgressDialog() {
    if (_progressDialogShown && mounted) {
      _progressDialogShown = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show/hide progress dialog when processing folder
    if (_isProcessingFolder && !_progressDialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showProgressDialog());
    } else if (!_isProcessingFolder && _progressDialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideProgressDialog());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CopyCrafter'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Directory selection
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _selectDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose Folder'),
                ),
                const SizedBox(width: 16),
                if (_selectedDirectory != null)
                  Expanded(
                    child: Text(
                      'Selected: ${_selectedDirectory!}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // View mode toggle and project info
            if (_projectType != ProjectType.none)
              Row(
                children: [
                  const Text('View Mode: '),
                  const SizedBox(width: 8),
                  SegmentedButton<ViewMode>(
                    segments: const [
                      ButtonSegment<ViewMode>(
                        value: ViewMode.projectStructure,
                        label: Text('Project Structure'),
                        icon: Icon(Icons.folder_special),
                      ),
                      ButtonSegment<ViewMode>(
                        value: ViewMode.fileSystem,
                        label: Text('File System'),
                        icon: Icon(Icons.folder),
                      ),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (Set<ViewMode> newSelection) {
                      setState(() {
                        _viewMode = newSelection.first;
                      });
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Project Type: ${_getProjectTypeString()}',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.blue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Lines to skip configuration and Search box
            Row(
              children: [
                const Text('Skip lines for .swift, .m, .h files:'),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    initialValue: _linesToSkip.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _linesToSkip = int.tryParse(value) ?? 7;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search files and folders...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Folder/File tree
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_viewMode == ViewMode.fileSystem
                      ? (_nodes.isEmpty
                          ? const Center(child: Text('Select a folder to view its contents'))
                          : _buildFileSystemView())
                      : (_projectNode == null
                          ? const Center(child: Text('No project structure found'))
                          : _buildProjectView())),
            ),
            const SizedBox(height: 16),

            // Copy button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_selectedFiles.isEmpty && _selectedFolders.isEmpty) || _isCopying
                    ? null
                    : _copySelectedToClipboard,
                icon: _isCopying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.copy),
                label: Text(
                  _isCopying
                      ? 'Copying...'
                      : 'Copy Selected to Clipboard (${_selectedFiles.length} files, ${_selectedFolders.length} folders)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  String _getProjectTypeString() {
    switch (_projectType) {
      case ProjectType.xcode:
        return 'Xcode';
      case ProjectType.dotNet:
        return '.NET';
      case ProjectType.android:
        return 'Android';
      case ProjectType.flutter:
        return 'Flutter';
      case ProjectType.none:
        return 'Unknown';
    }
  }

  Widget _buildFileSystemView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select files/folders (${_selectedFiles.length + _selectedFolders.length} selected):',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_selectedFiles.isNotEmpty || _selectedFolders.isNotEmpty)
              TextButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear All'),
              ),
          ],
        ),
        // Token count display
        if (_totalTokenCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
            child: Text(
              'Estimated token count: $_totalTokenCount tokens',
              style: const TextStyle(
                color: Colors.blueGrey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildFileTree(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select files/folders (${_selectedFiles.length + _selectedFolders.length} selected):',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_selectedFiles.isNotEmpty || _selectedFolders.isNotEmpty)
              TextButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear All'),
              ),
          ],
        ),
        // Token count display
        if (_totalTokenCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
            child: Text(
              'Estimated token count: $_totalTokenCount tokens',
              style: const TextStyle(
                color: Colors.blueGrey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildProjectTree(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileTree() {
    List<FileNode> nodesToDisplay;

    // Determine which nodes to display based on search
    if (_searchQuery.isEmpty) {
      nodesToDisplay = _nodes;
    } else {
      // Filter nodes based on search query
      nodesToDisplay = _getFilteredFileNodes(_nodes);

      if (nodesToDisplay.isEmpty) {
        return const Center(child: Text('No matching files or folders found'));
      }
    }

    return ListView.builder(
      itemCount: nodesToDisplay.length,
      itemBuilder: (context, index) {
        return _buildFileTreeItem(nodesToDisplay[index], 0);
      },
    );
  }

  Widget _buildProjectTree() {
    if (_projectNode == null) {
      return const Center(child: Text('No project structure available'));
    }

    List<ProjectNode> nodesToDisplay;

    // Determine which nodes to display based on search
    if (_searchQuery.isEmpty) {
      nodesToDisplay = [_projectNode!];
    } else {
      // Filter project nodes based on search query
      nodesToDisplay = _getFilteredProjectNodes(_projectNode!);

      if (nodesToDisplay.isEmpty) {
        return const Center(child: Text('No matching files or folders found'));
      }
    }

    return ListView.builder(
      itemCount: nodesToDisplay.length,
      itemBuilder: (context, index) {
        return _buildProjectTreeItem(nodesToDisplay[index], 0);
      },
    );
  }

  Widget _buildFileTreeItem(FileNode node, int depth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            if (node.isDirectory) {
              setState(() {
                node.isExpanded = !node.isExpanded;
              });
            } else {
              _toggleFileSelection(node);
            }
          },
          onLongPress: () {
            // Allow selection of directories on long press
            if (node.isDirectory) {
              _toggleFolderSelection(node);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: depth * 20.0, top: 4.0, bottom: 4.0),
            child: Row(
              children: [
                if (node.isDirectory)
                  Icon(
                    node.isExpanded ? Icons.folder_open : Icons.folder,
                    color: node.isSelected ? Colors.green.shade700 : Colors.blue.shade300,
                  )
                else if (node.isSelected)
                  Icon(
                    Icons.check_box,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  const Icon(
                    Icons.check_box_outline_blank,
                    color: Colors.grey,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontWeight: node.isDirectory ? FontWeight.bold : FontWeight.normal,
                      color: node.isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Display token count for selected files
                if (!node.isDirectory && node.isSelected && _fileTokenCounts.containsKey(node.path))
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      '${_fileTokenCounts[node.path]} tokens',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                if (node.isDirectory)
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: IconButton(
                      icon: Icon(
                        node.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color:
                            node.isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                      ),
                      onPressed: () => _toggleFolderSelection(node),
                      tooltip: 'Select entire folder',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (node.isDirectory && node.isExpanded)
          for (var child in node.children) _buildFileTreeItem(child, depth + 1),
      ],
    );
  }

  Widget _buildProjectTreeItem(ProjectNode node, int depth) {
    // Skip files with no full path (e.g., generated files)
    if (node.type == 'file' && (node.fullPath == null || node.fullPath!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            if (node.type == 'group') {
              setState(() {
                node.isExpanded = !node.isExpanded;
              });
            } else if (node.fullPath != null) {
              _toggleProjectFileSelection(node);
            }
          },
          onLongPress: () {
            // Allow selection of directories on long press
            if (node.type == 'group' && node.fullPath != null) {
              _toggleProjectFolderSelection(node);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(left: depth * 20.0, top: 4.0, bottom: 4.0),
            child: Row(
              children: [
                if (node.type == 'group')
                  Icon(
                    node.isExpanded ? Icons.folder_open : Icons.folder,
                    color: node.isSelected ? Colors.green.shade700 : Colors.indigo.shade300,
                  )
                else if (node.isSelected)
                  Icon(
                    Icons.check_box,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  const Icon(
                    Icons.check_box_outline_blank,
                    color: Colors.grey,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontWeight: node.type == 'group' ? FontWeight.bold : FontWeight.normal,
                      color: node.isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Display token count for selected files
                if (node.type == 'file' &&
                    node.isSelected &&
                    node.fullPath != null &&
                    _fileTokenCounts.containsKey(node.fullPath))
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      '${_fileTokenCounts[node.fullPath]} tokens',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                if (node.type == 'group' && node.fullPath != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: IconButton(
                      icon: Icon(
                        node.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color:
                            node.isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                      ),
                      onPressed: () => _toggleProjectFolderSelection(node),
                      tooltip: 'Select entire folder',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (node.type == 'group' && node.isExpanded && node.children.isNotEmpty)
          for (var child in node.children) _buildProjectTreeItem(child, depth + 1),
      ],
    );
  }

  void _toggleFileSelection(FileNode node) {
    if (node.isDirectory) return;

    setState(() {
      // Toggle the node's selected state
      node.isSelected = !node.isSelected;

      if (node.isSelected) {
        if (!_selectedFiles.contains(node.path)) {
          _selectedFiles.add(node.path);
          // Calculate token count for newly selected file
          _calculateTokenCountForFile(node.path);
        }
        _propagateSelectionUpwards(node.path);
      } else {
        _selectedFiles.remove(node.path);
        // Update total token count by removing this file's tokens
        if (_fileTokenCounts.containsKey(node.path)) {
          _totalTokenCount -= _fileTokenCounts[node.path]!;
          _fileTokenCounts.remove(node.path);
        }
        _propagateDeselectionUpwards(node.path);
      }

      // Update the selection state in the original data structure
      _updateNodeSelectionState(node.path, node.isSelected);

      // If we're in search mode, refresh filtered nodes to reflect selection changes
      if (_searchQuery.isNotEmpty) {
        // This will trigger a rebuild with updated selection states
      }
    });
  }

  Future<void> _toggleFolderSelection(FileNode node) async {
    if (!node.isDirectory) return;

    if (node.isSelected) {
      // Deselecting is fast, do it synchronously
      setState(() {
        node.isSelected = false;
        _selectedFolders.remove(node.path);
        _selectAllChildrenRecursively(node, false);
        _propagateDeselectionUpwards(node.path);
        _updateFolderSelectionState(node.path, false);
      });
      return;
    }

    // Selecting requires processing, show progress
    setState(() {
      node.isSelected = true;
      if (!_selectedFolders.contains(node.path)) {
        _selectedFolders.add(node.path);
      }
      _isProcessingFolder = true;
      _processedFiles = 0;
      _totalFilesToProcess = 0;
      _processingStatus = 'Scanning folder...';
    });

    try {
      // First, count total files to process
      _totalFilesToProcess = await _countTextFilesInFolder(node.path);

      setState(() {
        _processingStatus = 'Processing files...';
      });

      // Now process files with progress updates
      await _selectAllChildrenRecursivelyAsync(node, true);

      if (mounted) {
        setState(() {
          _isProcessingFolder = false;
          _processingStatus = '';
          _updateFolderSelectionState(node.path, true);
        });
      }
    } catch (e) {
      setState(() {
        _isProcessingFolder = false;
        _processingStatus = '';
        node.isSelected = false;
        _selectedFolders.remove(node.path);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing folder: $e')),
        );
      }
    }
  }

  // Get folders to skip based on project type
  Set<String> _getFoldersToSkip() {
    final folders = <String>{
      // Common build and dependency folders
      'build',
      '.dart_tool',
      '.gradle',
      '.idea',
      'node_modules',
      'vendor',
      '.nuget',
      'bin',
      'obj',
      '.vs',
      'DerivedData',
      '.swiftpm',
      '.pub-cache',
      '.fvm',
      'Pods',
      '.cocoapods',
      '.git',
      '.svn',
      '.hg',
      '.symlinks', // Flutter iOS symlinks
    };

    // Add project-specific folders
    switch (_projectType) {
      case ProjectType.flutter:
        folders.addAll({
          '.dart_tool',
          'build',
          '.pub-cache',
          '.fvm',
          'packages', // Legacy Flutter packages
        });
        break;
      case ProjectType.android:
        folders.addAll({
          'build',
          '.gradle',
          '.idea',
        });
        break;
      case ProjectType.xcode:
        folders.addAll({
          'build',
          'DerivedData',
          '.swiftpm',
          'Pods',
          '.cocoapods',
          '.xcodebuild',
        });
        break;
      case ProjectType.dotNet:
        folders.addAll({
          'bin',
          'obj',
          '.vs',
          '.nuget',
          'packages', // NuGet packages
        });
        break;
      case ProjectType.none:
        // For unknown projects, skip common folders
        break;
    }

    return folders;
  }

  // Check if a directory should be skipped
  bool _shouldSkipDirectory(String dirName) {
    return _getFoldersToSkip().contains(dirName);
  }

  // Check if a file is a text file (non-binary) based on extension
  bool _isTextFile(String filePath) {
    final extension = path_util.extension(filePath).toLowerCase();

    // Common binary file extensions to exclude
    final binaryExtensions = {
      // Images
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.ico', '.webp',
      '.tiff', '.tif', '.heic', '.heif', '.raw', '.cr2', '.nef', '.orf',
      '.sr2', '.psd', '.ai', '.eps', '.avif', '.dng', '.arw', '.rw2',
      '.raf', '.x3f', '.srw', '.pef', '.mrw',
      // Videos
      '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv', '.m4v',
      '.3gp', '.ogv', '.mpg', '.mpeg', '.m2v', '.mts', '.m2ts',
      // Audio
      '.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma', '.m4a', '.opus',
      '.aiff', '.au', '.ra', '.amr',
      // Archives
      '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.dmg', '.iso',
      '.cab', '.deb', '.rpm', '.pkg', '.apk', '.ipa',
      // Documents (binary formats)
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
      // Fonts
      '.ttf', '.otf', '.woff', '.woff2', '.eot', '.fon',
      // Executables and libraries
      '.exe', '.dll', '.so', '.dylib', '.app',
      // Databases
      '.db', '.sqlite', '.sqlite3', '.mdb', '.accdb',
      // Other binary
      '.bin', '.dat', '.jar', '.war', '.ear', '.class', '.pyc', '.pyo',
      '.o', '.obj', '.a', '.lib', '.framework',
    };

    return !binaryExtensions.contains(extension);
  }

  // Check if a path contains any skipped directory
  bool _pathContainsSkippedDirectory(String filePath, Set<String> foldersToSkip) {
    // Get relative path segments
    final normalizedPath = path_util.normalize(filePath);
    final segments = normalizedPath.split(path_util.separator);
    for (final segment in segments) {
      if (foldersToSkip.contains(segment)) {
        return true;
      }
    }
    return false;
  }

  // Count text files in a folder recursively
  Future<int> _countTextFilesInFolder(String folderPath) async {
    int count = 0;
    try {
      final directory = Directory(folderPath);
      if (await directory.exists()) {
        final foldersToSkip = _getFoldersToSkip();
        await for (var entity in directory.list(recursive: true)) {
          if (entity is File) {
            final name = path_util.basename(entity.path);
            if (!name.startsWith('.') && _isTextFile(entity.path)) {
              // Check if file is in a skipped directory
              if (!_pathContainsSkippedDirectory(entity.path, foldersToSkip)) {
                count++;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error counting files in folder: $e');
    }
    return count;
  }

  // Async version for selecting children with progress updates
  Future<void> _selectAllChildrenRecursivelyAsync(FileNode node, bool selected) async {
    for (var child in node.children) {
      if (child.isDirectory) {
        child.isSelected = selected;
        if (selected) {
          if (!_selectedFolders.contains(child.path)) {
            _selectedFolders.add(child.path);
          }
          _propagateSelectionUpwards(child.path);
        } else {
          _selectedFolders.remove(child.path);
        }
        await _selectAllChildrenRecursivelyAsync(child, selected);
      } else {
        // Only select text files (non-binary)
        if (!_isTextFile(child.path)) {
          continue;
        }
        child.isSelected = selected;
        if (selected) {
          if (!_selectedFiles.contains(child.path)) {
            _selectedFiles.add(child.path);

            // Update progress
            setState(() {
              _processedFiles++;
              _processingStatus = 'Processing: ${path_util.basename(child.path)}';
            });
            
            // Calculate token count for newly selected file
            await _calculateTokenCountForFile(child.path);

            // Allow UI to update
            await Future.delayed(const Duration(milliseconds: 1));
          }
          _propagateSelectionUpwards(child.path);
        } else {
          _selectedFiles.remove(child.path);
          // Update total token count by removing this file's tokens
          if (_fileTokenCounts.containsKey(child.path)) {
            _totalTokenCount -= _fileTokenCounts[child.path]!;
            _fileTokenCounts.remove(child.path);
          }
        }
      }
    }
  }

  void _selectAllChildrenRecursively(FileNode node, bool selected) {
    for (var child in node.children) {
      if (child.isDirectory) {
        child.isSelected = selected;
        if (selected) {
          if (!_selectedFolders.contains(child.path)) {
            _selectedFolders.add(child.path);
          }
          _propagateSelectionUpwards(child.path);
        } else {
          _selectedFolders.remove(child.path);
        }
        _selectAllChildrenRecursively(child, selected);
      } else {
        // Only select text files (non-binary)
        if (!_isTextFile(child.path)) {
          continue;
        }
        child.isSelected = selected;
        if (selected) {
          if (!_selectedFiles.contains(child.path)) {
            _selectedFiles.add(child.path);
            // Calculate token count for newly selected file
            _calculateTokenCountForFile(child.path);
          }
          _propagateSelectionUpwards(child.path);
        } else {
          _selectedFiles.remove(child.path);
          // Update total token count by removing this file's tokens
          if (_fileTokenCounts.containsKey(child.path)) {
            _totalTokenCount -= _fileTokenCounts[child.path]!;
            _fileTokenCounts.remove(child.path);
          }
        }
      }
    }
  }

  void _toggleProjectFileSelection(ProjectNode node) {
    if (node.type == 'group' || node.fullPath == null) return;

    setState(() {
      node.isSelected = !node.isSelected;

      if (node.isSelected) {
        if (!_selectedFiles.contains(node.fullPath)) {
          _selectedFiles.add(node.fullPath!);
          // Calculate token count for newly selected file
          _calculateTokenCountForFile(node.fullPath!);
        }
        _propagateSelectionUpwards(node.fullPath!);
      } else {
        _selectedFiles.remove(node.fullPath);
        // Update total token count by removing this file's tokens
        if (_fileTokenCounts.containsKey(node.fullPath)) {
          _totalTokenCount -= _fileTokenCounts[node.fullPath]!;
          _fileTokenCounts.remove(node.fullPath);
        }
        _propagateDeselectionUpwards(node.fullPath!);
      }

      // Update the selection state in the original project structure
      if (_projectNode != null) {
        _updateProjectNodeSelectionState(_projectNode!, node.fullPath!, node.isSelected);
      }

      // Force rebuild in search mode
      if (_searchQuery.isNotEmpty) {
        // This will trigger a rebuild with updated selection states
      }
    });
  }

  Future<void> _toggleProjectFolderSelection(ProjectNode node) async {
    if (node.type != 'group' || node.fullPath == null) return;

    if (node.isSelected) {
      // Deselecting is fast, do it synchronously
      setState(() {
        node.isSelected = false;
        _selectedFolders.remove(node.fullPath);
        _selectAllProjectChildrenRecursively(node, false);
        _propagateDeselectionUpwards(node.fullPath!);
        if (_projectNode != null) {
          _updateProjectFolderSelectionState(_projectNode!, node.fullPath!, false);
        }
      });
      return;
    }

    // Selecting requires processing, show progress
    setState(() {
      node.isSelected = true;
      if (!_selectedFolders.contains(node.fullPath)) {
        _selectedFolders.add(node.fullPath!);
      }
      _isProcessingFolder = true;
      _processedFiles = 0;
      _totalFilesToProcess = 0;
      _processingStatus = 'Scanning folder...';
    });

    try {
      // First, count total files to process
      _totalFilesToProcess = await _countTextFilesInFolder(node.fullPath!);
      
      setState(() {
        _processingStatus = 'Processing files...';
      });

      // Now process files with progress updates
      await _selectAllProjectChildrenRecursivelyAsync(node, true);

      if (mounted) {
        setState(() {
          _isProcessingFolder = false;
          _processingStatus = '';
          if (_projectNode != null) {
            _updateProjectFolderSelectionState(_projectNode!, node.fullPath!, true);
          }
        });
      }
    } catch (e) {
      setState(() {
        _isProcessingFolder = false;
        _processingStatus = '';
        node.isSelected = false;
        _selectedFolders.remove(node.fullPath);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing folder: $e')),
        );
      }
    }
  }

  // Async version for selecting project children with progress updates
  Future<void> _selectAllProjectChildrenRecursivelyAsync(ProjectNode node, bool selected) async {
    for (var child in node.children) {
      if (child.type == 'group') {
        child.isSelected = selected;
        if (child.fullPath != null) {
          if (selected) {
            if (!_selectedFolders.contains(child.fullPath)) {
              _selectedFolders.add(child.fullPath!);
            }
            _propagateSelectionUpwards(child.fullPath!);
          } else {
            _selectedFolders.remove(child.fullPath);
          }
        }
        await _selectAllProjectChildrenRecursivelyAsync(child, selected);
      } else if (child.fullPath != null) {
        // Only select text files (non-binary)
        if (!_isTextFile(child.fullPath!)) {
          continue;
        }
        child.isSelected = selected;
        if (selected) {
          if (!_selectedFiles.contains(child.fullPath)) {
            _selectedFiles.add(child.fullPath!);

            // Update progress
            setState(() {
              _processedFiles++;
              _processingStatus = 'Processing: ${path_util.basename(child.fullPath!)}';
            });
            
            // Calculate token count for newly selected file
            await _calculateTokenCountForFile(child.fullPath!);

            // Allow UI to update
            await Future.delayed(const Duration(milliseconds: 1));
          }
          _propagateSelectionUpwards(child.fullPath!);
        } else {
          _selectedFiles.remove(child.fullPath);
          // Update total token count by removing this file's tokens
          if (_fileTokenCounts.containsKey(child.fullPath)) {
            _totalTokenCount -= _fileTokenCounts[child.fullPath]!;
            _fileTokenCounts.remove(child.fullPath);
          }
        }
      }
    }
  }

  void _selectAllProjectChildrenRecursively(ProjectNode node, bool selected) {
    for (var child in node.children) {
      if (child.type == 'group') {
        child.isSelected = selected;
        if (child.fullPath != null) {
          if (selected) {
            if (!_selectedFolders.contains(child.fullPath)) {
              _selectedFolders.add(child.fullPath!);
            }
            _propagateSelectionUpwards(child.fullPath!);
          } else {
            _selectedFolders.remove(child.fullPath);
          }
        }
        _selectAllProjectChildrenRecursively(child, selected);
      } else if (child.fullPath != null) {
        // Only select text files (non-binary)
        if (!_isTextFile(child.fullPath!)) {
          continue;
        }
        child.isSelected = selected;
        if (selected) {
          if (!_selectedFiles.contains(child.fullPath)) {
            _selectedFiles.add(child.fullPath!);
            // Calculate token count for newly selected file
            _calculateTokenCountForFile(child.fullPath!);
          }
          _propagateSelectionUpwards(child.fullPath!);
        } else {
          _selectedFiles.remove(child.fullPath);
          // Update total token count by removing this file's tokens
          if (_fileTokenCounts.containsKey(child.fullPath)) {
            _totalTokenCount -= _fileTokenCounts[child.fullPath]!;
            _fileTokenCounts.remove(child.fullPath);
          }
        }
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedFiles = [];
      _selectedFolders = [];
      _fileTokenCounts = {};
      _totalTokenCount = 0;
      _updateNodeSelection();
    });
  }

  void _updateNodeSelection() {
    _updateNodeSelectionRecursive(_nodes);
    if (_projectNode != null) {
      _updateProjectNodeSelectionRecursive(_projectNode!);
    }
  }

  void _updateNodeSelectionRecursive(List<FileNode> nodes) {
    for (var node in nodes) {
      if (node.isDirectory) {
        node.isSelected = _selectedFolders.contains(node.path);
      } else {
        node.isSelected = _selectedFiles.contains(node.path);
      }

      if (node.children.isNotEmpty) {
        _updateNodeSelectionRecursive(node.children);
      }
    }
  }

  void _updateProjectNodeSelectionRecursive(ProjectNode node) {
    if (node.type == 'group') {
      node.isSelected = node.fullPath != null && _selectedFolders.contains(node.fullPath);
    } else {
      node.isSelected = node.fullPath != null && _selectedFiles.contains(node.fullPath);
    }

    for (var child in node.children) {
      _updateProjectNodeSelectionRecursive(child);
    }
  }

  Future<void> _selectDirectory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        setState(() {
          _selectedDirectory = selectedDirectory;
          _selectedFiles = [];
          _selectedFolders = [];
          _projectNode = null;
          _projectType = ProjectType.none;
          _viewMode = ViewMode.fileSystem;
        });

        // First look for projects
        bool foundProject = await _detectProject(selectedDirectory);

        // Then scan the directory for the file system tree view
        await _scanDirectory(selectedDirectory);

        // Set the view mode to project structure if found
        if (foundProject) {
          setState(() {
            _viewMode = ViewMode.projectStructure;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting directory: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _detectProject(String directoryPath) async {
    // Try to detect Xcode project first
    if (await _findXcodeProject(directoryPath)) {
      return true;
    }

    // Try to detect .NET project
    if (await _findDotNetProject(directoryPath)) {
      return true;
    }

    // Try to detect Android project
    if (await _findAndroidProject(directoryPath)) {
      return true;
    }

    // Try to detect Flutter project
    if (await _findFlutterProject(directoryPath)) {
      return true;
    }

    // Add more project type detection here

    return false;
  }

  Future<bool> _findXcodeProject(String directoryPath) async {
    try {
      Directory directory = Directory(directoryPath);
      List<FileSystemEntity> entities = await directory.list().toList();

      // Look for .xcodeproj directories
      for (var entity in entities) {
        if (entity is Directory && path_util.extension(entity.path) == '.xcodeproj') {
          String pbxprojPath = path_util.join(entity.path, 'project.pbxproj');
          File pbxprojFile = File(pbxprojPath);

          if (await pbxprojFile.exists()) {
            await _parseXcodeProject(pbxprojPath);
            setState(() {
              _projectType = ProjectType.xcode;
            });
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error finding Xcode project: $e');
      return false;
    }
  }

  Future<bool> _findDotNetProject(String directoryPath) async {
    try {
      Directory directory = Directory(directoryPath);
      List<FileSystemEntity> entities = await directory.list().toList();

      // Look for .csproj, .vbproj, or .sln files
      for (var entity in entities) {
        if (entity is File) {
          String extension = path_util.extension(entity.path).toLowerCase();
          if (['.csproj', '.vbproj', '.sln'].contains(extension)) {
            // Parse the .NET project file
            await _parseDotNetProject(entity.path);
            setState(() {
              _projectType = ProjectType.dotNet;
            });
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error finding .NET project: $e');
      return false;
    }
  }

  Future<bool> _findAndroidProject(String directoryPath) async {
    try {
      // Check for build.gradle, AndroidManifest.xml and/or app/src/main
      final gradlePath = path_util.join(directoryPath, 'build.gradle');
      final manifestPath = path_util.join(directoryPath, 'AndroidManifest.xml');
      final appSrcMainPath = path_util.join(directoryPath, 'app', 'src', 'main');

      // Also check for the app module pattern in Android projects
      final appGradlePath = path_util.join(directoryPath, 'app', 'build.gradle');
      final appManifestPath =
          path_util.join(directoryPath, 'app', 'src', 'main', 'AndroidManifest.xml');

      if ((await File(gradlePath).exists()) ||
          (await File(manifestPath).exists()) ||
          (await Directory(appSrcMainPath).exists()) ||
          (await File(appGradlePath).exists()) ||
          (await File(appManifestPath).exists())) {
        await _createAndroidProjectStructure(directoryPath);
        setState(() {
          _projectType = ProjectType.android;
        });
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error finding Android project: $e');
      return false;
    }
  }

  Future<bool> _findFlutterProject(String directoryPath) async {
    try {
      // Check for pubspec.yaml with flutter dependency
      final pubspecPath = path_util.join(directoryPath, 'pubspec.yaml');

      if (await File(pubspecPath).exists()) {
        final content = await File(pubspecPath).readAsString();

        // Simple check for Flutter dependency - could be more sophisticated
        if (content.contains('flutter:') &&
            (content.contains('sdk: flutter') ||
                await Directory(path_util.join(directoryPath, 'lib')).exists())) {
          await _createFlutterProjectStructure(directoryPath);
          setState(() {
            _projectType = ProjectType.flutter;
          });
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error finding Flutter project: $e');
      return false;
    }
  }

  Future<void> _parseXcodeProject(String pbxprojPath) async {
    try {
      debugPrint('Parsing Xcode project at: $pbxprojPath');

      // Get the application support directory
      final appSupportDir = await getApplicationSupportDirectory();
      final scriptsDir = Directory(path_util.join(appSupportDir.path, 'scripts'));

      // Create scripts directory if it doesn't exist
      if (!await scriptsDir.exists()) {
        await scriptsDir.create(recursive: true);
        debugPrint('Created scripts directory: ${scriptsDir.path}');
      }

      // Copy the script from the app bundle to the scripts directory
      const scriptName = 'parse_pbxproj.py';
      final scriptPath = path_util.join(scriptsDir.path, scriptName);

      // Check if we need to copy the script
      if (!await File(scriptPath).exists()) {
        debugPrint('Script does not exist, copying from assets');
        // Get the script content from the app bundle
        final scriptContent = await rootBundle.loadString('scripts/$scriptName');
        debugPrint('Script content length: ${scriptContent.length}');

        // Write it to the scripts directory
        await File(scriptPath).writeAsString(scriptContent);
        debugPrint('Wrote script to: $scriptPath');

        // Make it executable
        try {
          await Process.run('chmod', ['+x', scriptPath]);
          debugPrint('Made script executable');
        } catch (e) {
          debugPrint('Warning: Could not make script executable: $e');
        }
      } else {
        debugPrint('Script already exists at: $scriptPath');
      }

      // Read the project file directly in Dart instead of using Python
      debugPrint('Reading project file directly in Dart');
      final projectFile = File(pbxprojPath);
      if (!await projectFile.exists()) {
        debugPrint('Project file does not exist: $pbxprojPath');
        return;
      }

      final projectContent = await projectFile.readAsString();
      debugPrint('Project file read, content length: ${projectContent.length}');

      // Create a simple structure for the project
      final projectName =
          path_util.basename(path_util.dirname(pbxprojPath)).replaceAll('.xcodeproj', '');
      final projectDir = path_util.dirname(path_util.dirname(pbxprojPath));

      // Create a root node
      final rootNode = {
        'id': 'root',
        'name': projectName,
        'type': 'group',
        'children': <Map<String, dynamic>>[]
      };

      // Scan the project directory to build a file structure
      final projectDirectory = Directory(projectDir);
      if (await projectDirectory.exists()) {
        debugPrint('Scanning project directory: $projectDir');

        // Simple function to scan directory
        Future<List<Map<String, dynamic>>> scanDir(Directory dir, String basePath) async {
          final result = <Map<String, dynamic>>[];
          try {
            final List<FileSystemEntity> entities = await dir.list().toList();

            // Sort directories first, then files
            entities.sort((a, b) {
              final aIsDir = a is Directory;
              final bIsDir = b is Directory;
              if (aIsDir && !bIsDir) return -1;
              if (!aIsDir && bIsDir) return 1;
              return path_util.basename(a.path).compareTo(path_util.basename(b.path));
            });

            for (final entity in entities) {
              final name = path_util.basename(entity.path);

              // Skip hidden files and directories
              if (name.startsWith('.')) continue;

              if (entity is Directory) {
                // Skip dependency and build folders
                if (_shouldSkipDirectory(name)) continue;
                
                final children = await scanDir(entity, entity.path);
                if (children.isNotEmpty) {
                  result.add({
                    'id': entity.path.hashCode.toString(),
                    'name': name,
                    'path': name,
                    'fullPath': entity.path,
                    'type': 'group',
                    'children': children
                  });
                }
              } else if (entity is File) {
                result.add({
                  'id': entity.path.hashCode.toString(),
                  'name': name,
                  'path': name,
                  'fullPath': entity.path,
                  'type': 'file'
                });
              }
            }
          } catch (e) {
            debugPrint('Error scanning directory: $e');
          }
          return result;
        }

        rootNode['children'] = await scanDir(projectDirectory, projectDir);
        debugPrint(
            'Scanned project structure with ${(rootNode['children'] as List).length} top-level items');
      }

      // Set project path and create node
      setState(() {
        _projectNode = XcodeNode.fromJson(rootNode);
        debugPrint('Project structure created successfully');
      });
    } catch (e, stackTrace) {
      debugPrint('Error parsing Xcode project: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _parseDotNetProject(String projectFilePath) async {
    try {
      // Get path to the script
      final scriptPath = path_util.join(Directory.current.path, 'scripts', 'parse_csproj.py');

      // Run the Python script
      final result = await Process.run(
        'python3',
        [scriptPath, projectFilePath],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        debugPrint('Error parsing .NET project: ${result.stderr}');
        return;
      }

      final jsonStr = result.stdout.toString().trim();
      if (jsonStr.isEmpty) {
        debugPrint('Empty result from .NET project parser');
        return;
      }

      // Parse the JSON
      final jsonData = jsonDecode(jsonStr);

      // Create DotNetNode from JSON
      setState(() {
        _projectNode = DotNetNode.fromJson(jsonData);
      });
    } catch (e) {
      debugPrint('Error parsing .NET project: $e');
    }
  }

  Future<void> _scanDirectory(String directoryPath) async {
    // Clear existing data
    _nodes = [];

    try {
      Directory directory = Directory(directoryPath);
      _nodes = await _buildDirectoryTree(directory);
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning directory: $e')),
        );
      }
    }
  }

  Future<List<FileNode>> _buildDirectoryTree(Directory directory) async {
    List<FileNode> result = [];
    List<FileSystemEntity> entities = [];

    try {
      entities = await directory.list().toList();

      // Sort entries: directories first, then files, both alphabetically
      entities.sort((a, b) {
        bool aIsDir = a is Directory;
        bool bIsDir = b is Directory;

        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;

        return path_util.basename(a.path).compareTo(path_util.basename(b.path));
      });

      for (var entity in entities) {
        final name = path_util.basename(entity.path);
        
        // Skip hidden files and directories
        if (name.startsWith('.')) {
          continue;
        }

        if (entity is Directory) {
          // Skip dependency and build folders
          if (_shouldSkipDirectory(name)) {
            continue;
          }
          
          List<FileNode> children = await _buildDirectoryTree(entity);

          result.add(FileNode(
            path: entity.path,
            name: name,
            isDirectory: true,
            children: children,
          ));
        } else if (entity is File) {
          result.add(FileNode(
            path: entity.path,
            name: name,
            isDirectory: false,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error processing directory ${directory.path}: $e');
    }

    return result;
  }

  Future<void> _copySelectedToClipboard() async {
    if (_selectedFiles.isEmpty && _selectedFolders.isEmpty) return;

    setState(() {
      _isCopying = true;
    });

    try {
      StringBuffer buffer = StringBuffer();

      // First process individual files
      for (String filePath in _selectedFiles) {
        await _processFileForCopy(filePath, buffer);
      }

      // Now process all files within selected folders
      for (String folderPath in _selectedFolders) {
        await _processFolderForCopy(folderPath, buffer);
      }

      // Get the final text for clipboard
      final clipboardText = buffer.toString();

      // Calculate and show token count before copying
      final totalTokens = SimpleTokenizer.countTokens(clipboardText);

      await Clipboard.setData(ClipboardData(text: clipboardText));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied content to clipboard (approx. $totalTokens tokens)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error copying to clipboard: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCopying = false;
        });
      }
    }
  }

  Future<void> _processFileForCopy(String filePath, StringBuffer buffer) async {
    File file = File(filePath);
    if (await file.exists()) {
      // Skip binary files
      if (!_isTextFile(filePath)) {
        return;
      }

      try {
        String content = await file.readAsString();
        List<String> lines = content.split('\n');

        // Check if we need to skip lines for this file type
        String extension = path_util.extension(filePath).toLowerCase();
        int skipLines = 0;
        if (['.swift', '.m', '.h'].contains(extension)) {
          skipLines = _linesToSkip;
        }

        // Add a file header
        buffer.writeln('');
        buffer.writeln('// File: ${path_util.relative(filePath, from: _selectedDirectory!)}');
        buffer.writeln('// ${'-' * 50}');

        // Add content starting from the appropriate line
        if (lines.length > skipLines) {
          buffer.writeln(lines.skip(skipLines).join('\n'));
        } else {
          buffer.writeln(content); // If file is shorter than skip lines, include everything
        }

        buffer.writeln('');
      } catch (e) {
        // Silently skip binary files that can't be read as text
        // This is expected for binary files that weren't caught by extension check
        return;
      }
    }
  }

  Future<void> _processFolderForCopy(String folderPath, StringBuffer buffer) async {
    try {
      Directory directory = Directory(folderPath);
      if (await directory.exists()) {
        final foldersToSkip = _getFoldersToSkip();
        // Process files in this directory and subdirectories
        await for (var entity in directory.list(recursive: true)) {
          if (entity is File) {
            // Skip hidden files
            if (path_util.basename(entity.path).startsWith('.')) {
              continue;
            }

            // Check if file is in a skipped directory
            if (_pathContainsSkippedDirectory(entity.path, foldersToSkip)) {
              continue;
            }

            // Skip binary files (images, videos, etc.)
            if (!_isTextFile(entity.path)) {
              continue;
            }

            // Skip files that are already in the selected files list to avoid duplicates
            if (_selectedFiles.contains(entity.path)) {
              continue;
            }

            // Process the file
            await _processFileForCopy(entity.path, buffer);
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing folder $folderPath: $e');
    }
  }

  Future<void> _createAndroidProjectStructure(String directoryPath) async {
    try {
      final rootNode = ProjectNode(
        id: 'root',
        name: path_util.basename(directoryPath),
        path: directoryPath,
        fullPath: directoryPath,
        type: 'group',
        isExpanded: true,
      );

      // Check if this is a root Android project or an app module
      final isAppModule = await Directory(path_util.join(directoryPath, 'app')).exists() &&
          await File(path_util.join(directoryPath, 'settings.gradle')).exists();

      final String appDir = isAppModule ? path_util.join(directoryPath, 'app') : directoryPath;
      final String srcMainDir = path_util.join(appDir, 'src', 'main');

      // Common Android project directories
      List<ProjectNode> topLevelGroups = [];

      // Add source directories if they exist
      if (await Directory(srcMainDir).exists()) {
        // Add Java/Kotlin source files
        final javaDir = path_util.join(srcMainDir, 'java');
        if (await Directory(javaDir).exists()) {
          final javaChildren = await _scanDirectoryForProject(javaDir, false);
          topLevelGroups.add(
            ProjectNode(
              id: 'java',
              name: 'Java',
              path: 'java',
              fullPath: javaDir,
              type: 'group',
              children: javaChildren,
            ),
          );
        }

        // Add Kotlin files
        final kotlinDir = path_util.join(srcMainDir, 'kotlin');
        if (await Directory(kotlinDir).exists()) {
          final kotlinChildren = await _scanDirectoryForProject(kotlinDir, false);
          topLevelGroups.add(
            ProjectNode(
              id: 'kotlin',
              name: 'Kotlin',
              path: 'kotlin',
              fullPath: kotlinDir,
              type: 'group',
              children: kotlinChildren,
            ),
          );
        }

        // Add res directory
        final resDir = path_util.join(srcMainDir, 'res');
        if (await Directory(resDir).exists()) {
          final resChildren = await _scanDirectoryForProject(resDir, false);
          topLevelGroups.add(
            ProjectNode(
              id: 'res',
              name: 'Resources',
              path: 'res',
              fullPath: resDir,
              type: 'group',
              children: resChildren,
            ),
          );
        }

        // Add AndroidManifest.xml
        final manifestFile = path_util.join(srcMainDir, 'AndroidManifest.xml');
        if (await File(manifestFile).exists()) {
          topLevelGroups.add(
            ProjectNode(
              id: 'manifest',
              name: 'AndroidManifest.xml',
              path: 'AndroidManifest.xml',
              fullPath: manifestFile,
              type: 'file',
            ),
          );
        }
      }

      // Add build.gradle files
      final List<String> gradleFiles = [
        path_util.join(directoryPath, 'build.gradle'),
        path_util.join(directoryPath, 'settings.gradle'),
        path_util.join(appDir, 'build.gradle'),
      ];

      for (final gradlePath in gradleFiles) {
        if (await File(gradlePath).exists()) {
          topLevelGroups.add(
            ProjectNode(
              id: path_util.basename(gradlePath),
              name: path_util.basename(gradlePath),
              path: path_util.basename(gradlePath),
              fullPath: gradlePath,
              type: 'file',
            ),
          );
        }
      }

      // Add other directories if in app module structure
      if (isAppModule) {
        // Look for other modules
        final entities = await Directory(directoryPath).list().toList();
        for (var entity in entities) {
          if (entity is Directory &&
              path_util.basename(entity.path) != 'app' &&
              path_util.basename(entity.path) != 'build' &&
              !path_util.basename(entity.path).startsWith('.')) {
            // Check if it's a module (has build.gradle)
            if (await File(path_util.join(entity.path, 'build.gradle')).exists()) {
              final moduleChildren = await _scanDirectoryForProject(entity.path, false);
              topLevelGroups.add(
                ProjectNode(
                  id: path_util.basename(entity.path),
                  name: '${path_util.basename(entity.path)} (module)',
                  path: path_util.basename(entity.path),
                  fullPath: entity.path,
                  type: 'group',
                  children: moduleChildren,
                ),
              );
            }
          }
        }
      }

      rootNode.children.addAll(topLevelGroups);

      setState(() {
        _projectNode = rootNode;
      });
    } catch (e) {
      debugPrint('Error creating Android project structure: $e');
    }
  }

  Future<void> _createFlutterProjectStructure(String directoryPath) async {
    try {
      final rootNode = ProjectNode(
        id: 'root',
        name: path_util.basename(directoryPath),
        path: directoryPath,
        fullPath: directoryPath,
        type: 'group',
        isExpanded: true,
      );

      // Common Flutter project directories
      List<ProjectNode> mainGroups = [];

      // Check for standard Flutter directories
      final commonDirs = [
        {'path': 'lib', 'name': 'lib'},
        {'path': 'test', 'name': 'test'},
        {'path': 'android', 'name': 'android'},
        {'path': 'ios', 'name': 'ios'},
        {'path': 'web', 'name': 'web'},
        {'path': 'windows', 'name': 'windows'},
        {'path': 'macos', 'name': 'macos'},
        {'path': 'linux', 'name': 'linux'},
      ];

      for (var dir in commonDirs) {
        final dirPath = path_util.join(directoryPath, dir['path']!);
        if (await Directory(dirPath).exists()) {
          final children = await _scanDirectoryForProject(dirPath, false);
          mainGroups.add(
            ProjectNode(
              id: dir['path']!,
              name: dir['name']!,
              path: dir['path'],
              fullPath: dirPath,
              type: 'group',
              children: children,
            ),
          );
        }
      }

      // Add important files at the root level
      final importantFiles = [
        'pubspec.yaml',
        'pubspec.lock',
        'README.md',
        'analysis_options.yaml',
        '.gitignore'
      ];

      for (var fileName in importantFiles) {
        final filePath = path_util.join(directoryPath, fileName);
        if (await File(filePath).exists()) {
          mainGroups.add(
            ProjectNode(
              id: fileName,
              name: fileName,
              path: fileName,
              fullPath: filePath,
              type: 'file',
            ),
          );
        }
      }

      rootNode.children.addAll(mainGroups);

      setState(() {
        _projectNode = rootNode;
      });
    } catch (e) {
      debugPrint('Error creating Flutter project structure: $e');
    }
  }

  // Helper function to scan directory for project structure
  Future<List<ProjectNode>> _scanDirectoryForProject(String directoryPath, bool skipHidden) async {
    final List<ProjectNode> nodes = [];
    try {
      final dir = Directory(directoryPath);
      final entities = await dir.list().toList();

      // Sort entries: directories first, then files
      entities.sort((a, b) {
        bool aIsDir = a is Directory;
        bool bIsDir = b is Directory;

        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;

        return path_util.basename(a.path).compareTo(path_util.basename(b.path));
      });

      for (var entity in entities) {
        final name = path_util.basename(entity.path);

        // Skip hidden files if requested
        if (skipHidden && name.startsWith('.')) continue;

        if (entity is Directory) {
          // Skip dependency and build folders
          if (_shouldSkipDirectory(name)) continue;
          
          final children = await _scanDirectoryForProject(entity.path, skipHidden);
          if (children.isNotEmpty || !skipHidden) {
            nodes.add(ProjectNode(
              id: name,
              name: name,
              path: name,
              fullPath: entity.path,
              type: 'group',
              children: children,
            ));
          }
        } else if (entity is File) {
          nodes.add(ProjectNode(
            id: name,
            name: name,
            path: name,
            fullPath: entity.path,
            type: 'file',
          ));
        }
      }
    } catch (e) {
      debugPrint('Error scanning directory $directoryPath: $e');
    }
    return nodes;
  }

  // Helper method to filter file nodes based on search query
  List<FileNode> _getFilteredFileNodes(List<FileNode> nodes) {
    final List<FileNode> result = [];
    final lowerQuery = _searchQuery.toLowerCase();

    for (var node in nodes) {
      if (node.name.toLowerCase().contains(lowerQuery)) {
        // Create a copy of the node that matches the search
        final matchedNode = FileNode(
          path: node.path,
          name: node.name,
          isDirectory: node.isDirectory,
          isSelected: node.isDirectory
              ? _selectedFolders.contains(node.path)
              : _selectedFiles.contains(node.path),
          isExpanded: true, // Always expand matched nodes for better UX
          children: [], // Initialize with empty list
        );

        // If it's a directory, also search its children
        if (node.isDirectory) {
          final matchedChildren = _getFilteredFileNodes(node.children);
          if (matchedChildren.isNotEmpty) {
            matchedNode.children = matchedChildren; // Assign new list
          }
        }

        result.add(matchedNode);
      } else if (node.isDirectory) {
        // For directories, search its children even if the directory itself doesn't match
        final matchedChildren = _getFilteredFileNodes(node.children);
        if (matchedChildren.isNotEmpty) {
          // Create a copy of the parent node with only the matching children
          final matchedNode = FileNode(
            path: node.path,
            name: node.name,
            isDirectory: true,
            isSelected: _selectedFolders.contains(node.path),
            isExpanded: true, // Always expand parent nodes with matching children
            children: matchedChildren, // Assign matched children directly
          );
          result.add(matchedNode);
        }
      }
    }

    return result;
  }

  // Helper method to filter project nodes based on search query
  List<ProjectNode> _getFilteredProjectNodes(ProjectNode rootNode) {
    final List<ProjectNode> result = [];
    final lowerQuery = _searchQuery.toLowerCase();

    // Create a recursive function to search the project tree
    List<ProjectNode> searchNodes(ProjectNode node) {
      final List<ProjectNode> matches = [];

      if (node.name.toLowerCase().contains(lowerQuery)) {
        // Create a copy of the matched node with minimal info
        final matchedNode = ProjectNode(
          id: node.id,
          name: node.name,
          path: node.path,
          fullPath: node.fullPath,
          type: node.type,
          isSelected: node.type == 'group' && node.fullPath != null
              ? _selectedFolders.contains(node.fullPath)
              : (node.fullPath != null ? _selectedFiles.contains(node.fullPath) : false),
          isExpanded: true, // Always expand matched nodes
          children: [], // Initialize with empty list
        );

        // If it's a group, also search its children
        if (node.type == 'group') {
          final List<ProjectNode> childMatches = [];
          for (var child in node.children) {
            childMatches.addAll(searchNodes(child));
          }

          if (childMatches.isNotEmpty) {
            matchedNode.children = childMatches; // Assign new list
          }
        }

        matches.add(matchedNode);
      } else if (node.type == 'group') {
        // For groups, search its children even if the group itself doesn't match
        final List<ProjectNode> childMatches = [];
        for (var child in node.children) {
          childMatches.addAll(searchNodes(child));
        }

        if (childMatches.isNotEmpty) {
          // Create a copy of the parent node with only the matching children
          final matchedNode = ProjectNode(
            id: node.id,
            name: node.name,
            path: node.path,
            fullPath: node.fullPath,
            type: 'group',
            isSelected: node.fullPath != null ? _selectedFolders.contains(node.fullPath) : false,
            isExpanded: true, // Always expand parents with matching children
            children: childMatches, // Assign matched children directly
          );
          matches.add(matchedNode);
        }
      }

      return matches;
    }

    // Start the search from the root node's children
    for (var child in rootNode.children) {
      result.addAll(searchNodes(child));
    }

    return result;
  }

  // Helper method to update file selection state across all views
  void _updateNodeSelectionState(String path, bool isSelected) {
    // Update in the original file tree
    _updateNodeSelectionStateRecursive(_nodes, path, isSelected);
  }

  // Recursively search and update node selection state
  void _updateNodeSelectionStateRecursive(List<FileNode> nodes, String path, bool isSelected) {
    for (var node in nodes) {
      if (!node.isDirectory && node.path == path) {
        node.isSelected = isSelected;
      } else if (node.isDirectory) {
        _updateNodeSelectionStateRecursive(node.children, path, isSelected);
      }
    }
  }

  // Helper method to update folder selection state across all views
  void _updateFolderSelectionState(String path, bool isSelected) {
    // Update in the original file tree
    _updateFolderSelectionStateRecursive(_nodes, path, isSelected);
  }

  // Recursively search and update folder selection state
  void _updateFolderSelectionStateRecursive(List<FileNode> nodes, String path, bool isSelected) {
    for (var node in nodes) {
      if (node.isDirectory) {
        if (node.path == path) {
          node.isSelected = isSelected;
          // If we found the folder, we need to update its children too
          _selectAllChildrenRecursively(node, isSelected);
          return;
        }
        _updateFolderSelectionStateRecursive(node.children, path, isSelected);
      }
    }
  }

  // Helper method to update file selection state in the project view
  void _updateProjectNodeSelectionState(ProjectNode root, String path, bool isSelected) {
    if (root.type == 'file' && root.fullPath == path) {
      root.isSelected = isSelected;
      return;
    }

    for (var child in root.children) {
      _updateProjectNodeSelectionState(child, path, isSelected);
    }
  }

  // Helper method to update folder selection state in the project view
  void _updateProjectFolderSelectionState(ProjectNode root, String path, bool isSelected) {
    if (root.type == 'group' && root.fullPath == path) {
      root.isSelected = isSelected;
      _selectAllProjectChildrenRecursively(root, isSelected);
      return;
    }

    for (var child in root.children) {
      _updateProjectFolderSelectionState(child, path, isSelected);
    }
  }

  // Calculate token count for a file
  Future<void> _calculateTokenCountForFile(String filePath) async {
    try {
      // Skip binary files
      if (!_isTextFile(filePath)) {
        return;
      }

      File file = File(filePath);
      if (await file.exists()) {
        String content = await file.readAsString();
        List<String> lines = content.split('\n');

        // Check if we need to skip lines for this file type
        String extension = path_util.extension(filePath).toLowerCase();
        int skipLines = 0;
        if (['.swift', '.m', '.h'].contains(extension)) {
          skipLines = _linesToSkip;
        }

        // Get content starting from the appropriate line
        String effectiveContent;
        if (lines.length > skipLines) {
          effectiveContent = lines.skip(skipLines).join('\n');
        } else {
          effectiveContent = content; // If file is shorter than skip lines, include everything
        }

        // Calculate token count
        int tokenCount = SimpleTokenizer.countTokens(effectiveContent);

        setState(() {
          _fileTokenCounts[filePath] = tokenCount;

          // Update total count
          _totalTokenCount = 0;
          for (var count in _fileTokenCounts.values) {
            _totalTokenCount += count;
          }
        });
      }
    } catch (e) {
      // Silently skip binary files that can't be read as text
      // This is expected for binary files that weren't caught by extension check
      return;
    }
  }

  // Propagate selection up the hierarchy
  void _propagateSelectionUpwards(String path) {
    List<String> parentsToSelect = [];

    // File system view
    FileNode? currentFileParent = _findParentFileNode(_nodes, path);
    while (currentFileParent != null) {
      if (!_selectedFolders.contains(currentFileParent.path) && _areAllChildrenSelected(currentFileParent)) {
        parentsToSelect.add(currentFileParent.path);
      }
      currentFileParent = _findParentFileNode(_nodes, currentFileParent.path);
    }

    // Project view
    ProjectNode? currentProjectParent = _findParentProjectNode(_projectNode, path);
    while (currentProjectParent != null) {
      if (currentProjectParent.fullPath != null &&
          !_selectedFolders.contains(currentProjectParent.fullPath!) &&
          _areAllProjectChildrenSelected(currentProjectParent)) {
        parentsToSelect.add(currentProjectParent.fullPath!);
      }
      // The path to find the next parent is the current parent's fullPath
      currentProjectParent = currentProjectParent.fullPath != null
          ? _findParentProjectNode(_projectNode, currentProjectParent.fullPath!)
          : null;
    }

    if (parentsToSelect.isNotEmpty) {
      setState(() {
        _selectedFolders.addAll(parentsToSelect);
        _updateNodeSelection();
      });
    }
  }

  // Check if all children of a file node are selected
  bool _areAllChildrenSelected(FileNode node) {
    for (var child in node.children) {
      if (child.isDirectory) {
        if (!_selectedFolders.contains(child.path) || !_areAllChildrenSelected(child)) {
          return false;
        }
      } else {
        if (!_selectedFiles.contains(child.path)) {
          return false;
        }
      }
    }
    return true;
  }

  // Check if all children of a project node are selected
  bool _areAllProjectChildrenSelected(ProjectNode node) {
    for (var child in node.children) {
      if (child.type == 'group') {
        if (child.fullPath == null ||
            !_selectedFolders.contains(child.fullPath!) ||
            !_areAllProjectChildrenSelected(child)) {
          return false;
        }
      } else {
        if (child.fullPath == null || !_selectedFiles.contains(child.fullPath!)) {
          return false;
        }
      }
    }
    return true;
  }

  // Propagate deselection up the hierarchy
  void _propagateDeselectionUpwards(String path) {
    List<String> parentsToDeselect = [];

    // File system view
    FileNode? currentFileParent = _findParentFileNode(_nodes, path);
    while (currentFileParent != null) {
      if (_selectedFolders.contains(currentFileParent.path)) {
        parentsToDeselect.add(currentFileParent.path);
      }
      currentFileParent = _findParentFileNode(_nodes, currentFileParent.path);
    }

    // Project view
    ProjectNode? currentProjectParent = _findParentProjectNode(_projectNode, path);
    while (currentProjectParent != null) {
      if (currentProjectParent.fullPath != null && _selectedFolders.contains(currentProjectParent.fullPath!)) {
        parentsToDeselect.add(currentProjectParent.fullPath!);
      }
      // The path to find the next parent is the current parent's fullPath
      currentProjectParent = currentProjectParent.fullPath != null
          ? _findParentProjectNode(_projectNode, currentProjectParent.fullPath!)
          : null;
    }

    if (parentsToDeselect.isNotEmpty) {
      setState(() {
        _selectedFolders.removeWhere((folderPath) => parentsToDeselect.contains(folderPath));
        _updateNodeSelection();
      });
    }
  }

  // Find parent of a file node
  FileNode? _findParentFileNode(List<FileNode> nodes, String path) {
    for (var node in nodes) {
      if (node.isDirectory) {
        for (var child in node.children) {
          if (child.path == path) {
            return node;
          }
        }
        final found = _findParentFileNode(node.children, path);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  // Find parent of a project node
  ProjectNode? _findParentProjectNode(ProjectNode? node, String path) {
    if (node == null) return null;

    for (var child in node.children) {
      if (child.fullPath == path) {
        return node;
      }
      if (child.type == 'group') {
        final found = _findParentProjectNode(child, path);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }
}

// Progress dialog widget that updates itself
class _ProgressDialogWidget extends StatefulWidget {
  final int Function() getProcessedFiles;
  final int Function() getTotalFiles;
  final String Function() getStatus;
  final bool Function() getIsProcessing;

  const _ProgressDialogWidget({
    required this.getProcessedFiles,
    required this.getTotalFiles,
    required this.getStatus,
    required this.getIsProcessing,
  });

  @override
  State<_ProgressDialogWidget> createState() => _ProgressDialogWidgetState();
}

class _ProgressDialogWidgetState extends State<_ProgressDialogWidget> {
  @override
  void initState() {
    super.initState();
    // Update dialog periodically while processing
    _updateDialog();
  }

  void _updateDialog() {
    if (widget.getIsProcessing() && mounted) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && widget.getIsProcessing()) {
          setState(() {});
          _updateDialog();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final processedFiles = widget.getProcessedFiles();
    final totalFiles = widget.getTotalFiles();
    final status = widget.getStatus();
    final progress = totalFiles > 0 ? processedFiles / totalFiles : 0.0;

    return PopScope(
      canPop: false, // Prevent dismissing while processing
      child: AlertDialog(
        title: const Text('Processing Folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(status),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Text(
              '$processedFiles / $totalFiles files',
              style: const TextStyle(fontSize: 12),
            ),
            if (progress > 0)
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
}

// Simple regex-based tokenizer for approximating GPT tokenization
class SimpleTokenizer {
  static int countTokens(String text) {
    // Very simple heuristic: for English text, tokens are roughly 4 chars on average
    // This is a very rough approximation
    return max(1, (text.length / 4).round());
  }
}
