import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.appName,
    required this.icon,
  });

  final String packageName;
  final String appName;
  final Uint8List icon;
}

class AppService {
  static const MethodChannel _platform = MethodChannel(
    'com.appbox.app/installed_apps',
  );
  static const EventChannel _stream = EventChannel('com.appbox.app/app_stream');

  static Stream<List<InstalledApp>> streamApps() {
    return _stream.receiveBroadcastStream().map((dynamic app) {
      if (app is List<dynamic>) {
        return app.map((dynamic item) {
          final Map<dynamic, dynamic> rawMap = item as Map<dynamic, dynamic>;
          return InstalledApp(
            packageName: rawMap['packageName'] as String,
            appName: rawMap['appName'] as String,
            icon: Uint8List.fromList(
              (rawMap['icon'] as List<dynamic>).cast<int>(),
            ),
          );
        }).toList();
      }

      // Backward-compatible handling if native sends a single app map.
      final Map<dynamic, dynamic> rawMap = app as Map<dynamic, dynamic>;
      return <InstalledApp>[
        InstalledApp(
          packageName: rawMap['packageName'] as String,
          appName: rawMap['appName'] as String,
          icon: Uint8List.fromList(
            (rawMap['icon'] as List<dynamic>).cast<int>(),
          ),
        ),
      ];
    });
  }

  static Future<List<InstalledApp>> getInstalledApps() async {
    try {
      debugPrint('AppService: Calling getInstalledApps');
      final List<dynamic> result = await _platform.invokeMethod(
        'getInstalledApps',
      );
      debugPrint('AppService: Received ${result.length} apps from native');
      return await compute(parseApps, result);
    } catch (e, stack) {
      debugPrint('REAL ERROR: $e');
      debugPrint('STACK: $stack');
      return []; // TEMP: no mock apps
    }
  }

  static List<InstalledApp> parseApps(List<dynamic> result) {
    return result.map((dynamic app) {
      final Map<dynamic, dynamic> rawMap = app as Map;
      final Map<String, dynamic> appMap = rawMap.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      return InstalledApp(
        packageName: appMap['packageName'] as String,
        appName: appMap['appName'] as String,
        icon: Uint8List.fromList((appMap['icon'] as List<dynamic>).cast<int>()),
      );
    }).toList();
  }

  static Future<void> launchApp(String packageName) async {
    try {
      await _platform.invokeMethod('launchApp', {'packageName': packageName});
    } catch (e) {
      debugPrint('Error launching app: $e');
    }
  }

  static Future<void> preWarmIntents(List<String> packageNames) async {
    try {
      await _platform.invokeMethod('preWarmIntents', {
        'packageNames': packageNames,
      });
    } catch (e) {
      debugPrint('Error pre-warming intents: $e');
    }
  }

  static Future<bool> canLaunchApp(String packageName) async {
    try {
      final List<InstalledApp> apps = await getInstalledApps();
      return apps.any((InstalledApp app) => app.packageName == packageName);
    } catch (e) {
      debugPrint('Error checking if app can be launched: $e');
      return false;
    }
  }
}

const Color bg = Color(0xFF131313);
const Color surface = Color(0xFF1A1A1A);
const Color tile = Color(0xFF2D2D2D);
const Color border = Colors.white;
const Color mint = Color(0xFF3CFFD0);
const Color purple = Color(0xFF5200FF);
const Color textPrimary = Colors.white;
const Color textSecondary = Color(0xFF949494);

void main() {
  runApp(const AppBoxApp());
}

class AppBoxApp extends StatefulWidget {
  const AppBoxApp({super.key});

  @override
  State<AppBoxApp> createState() => _AppBoxAppState();
}

class _AppBoxAppState extends State<AppBoxApp> {
  bool _isDarkMode = true;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = _isDarkMode
        ? AppPalette.dark()
        : AppPalette.light();

    return MaterialApp(
      title: 'AppBox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: palette.bg,
        useMaterial3: true,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      ),
      home: MainScreen(
        palette: palette,
        isDarkMode: _isDarkMode,
        onThemeToggle: _toggleTheme,
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({
    required this.palette,
    required this.isDarkMode,
    required this.onThemeToggle,
    super.key,
  });

  final AppPalette palette;
  final bool isDarkMode;
  final VoidCallback onThemeToggle;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<AppGroupData> groups = <AppGroupData>[];
  final Map<String, bool> _launchingApps = <String, bool>{};
  final Set<String> _selectedWorkspaces = <String>{};
  bool _skipDeleteConfirmation = false;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final List<AppGroupData> loadedGroups =
        await PersistenceManager.loadGroups();
    final bool skipDeleteConfirmation =
        await PersistenceManager.loadSkipDeleteConfirmation();
    setState(() {
      groups = loadedGroups.isNotEmpty ? loadedGroups : <AppGroupData>[];
      _skipDeleteConfirmation = skipDeleteConfirmation;
    });
    await _preWarmIntents();
  }

  Future<void> _preWarmIntents() async {
    final Set<String> packageNames = <String>{};
    for (final AppGroupData group in groups) {
      for (final AppData app in group.apps) {
        packageNames.add(app.packageName);
      }
    }
    if (packageNames.isNotEmpty) {
      await AppService.preWarmIntents(packageNames.toList());
    }
  }

  Future<void> _saveGroups() async {
    await PersistenceManager.saveGroups(groups);
  }

  bool get _hasSelectedWorkspaces => _selectedWorkspaces.isNotEmpty;

  String _workspaceIdForIndex(int index) => groups[index].name;

  void _onGroupLongPress(int index) {
    if (!_isEditMode) return;

    HapticFeedback.mediumImpact();
    setState(() {
      final String workspaceId = _workspaceIdForIndex(index);
      if (_selectedWorkspaces.contains(workspaceId)) {
        _selectedWorkspaces.remove(workspaceId);
      } else {
        _selectedWorkspaces.add(workspaceId);
      }
    });
  }

  void _onGroupTap(int index) {
    if (!_isEditMode) return;

    setState(() {
      final String workspaceId = _workspaceIdForIndex(index);
      if (_selectedWorkspaces.contains(workspaceId)) {
        _selectedWorkspaces.remove(workspaceId);
      } else {
        _selectedWorkspaces.add(workspaceId);
      }
    });
  }

  void _clearSelectionMode() {
    if (!_isEditMode || !_hasSelectedWorkspaces) return;
    setState(() {
      _selectedWorkspaces.clear();
    });
  }

  void _toggleEditMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) {
        _selectedWorkspaces.clear();
      }
    });
  }

  Future<void> _onDeleteSelected() async {
    if (!_hasSelectedWorkspaces) return;

    bool shouldDelete = _skipDeleteConfirmation;

    if (!shouldDelete) {
      final DeleteConfirmationResult? result =
          await _showDeleteConfirmationDialog();
      if (result == null || !result.confirmed) {
        return;
      }

      shouldDelete = true;
      if (result.skipNextTime != _skipDeleteConfirmation) {
        _skipDeleteConfirmation = result.skipNextTime;
        await PersistenceManager.saveSkipDeleteConfirmation(
          result.skipNextTime,
        );
      }
    }

    if (!shouldDelete) return;

    HapticFeedback.heavyImpact();

    setState(() {
      final List<int> sortedIndexes =
          groups
              .asMap()
              .entries
              .where(
                (MapEntry<int, AppGroupData> entry) =>
                    _selectedWorkspaces.contains(entry.value.name),
              )
              .map((MapEntry<int, AppGroupData> entry) => entry.key)
              .toList()
            ..sort((int a, int b) => b.compareTo(a));
      for (final int index in sortedIndexes) {
        if (index >= 0 && index < groups.length) {
          groups.removeAt(index);
        }
      }
      _selectedWorkspaces.clear();
      _isEditMode = false;
    });
    await _saveGroups();
  }

  Future<DeleteConfirmationResult?> _showDeleteConfirmationDialog() async {
    bool skipNextTime = false;
    final int selectedCount = _selectedWorkspaces.length;

    return showDialog<DeleteConfirmationResult>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: widget.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: widget.palette.border.withValues(alpha: 0.25),
                ),
              ),
              title: Text(
                'Delete selected workspaces?',
                style: TextStyle(
                  color: widget.palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    selectedCount > 1
                        ? 'This action will permanently remove selected workspaces.'
                        : 'This action will permanently remove the selected workspace.',
                    style: TextStyle(
                      color: widget.palette.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Checkbox(
                        value: skipNextTime,
                        activeColor: const Color(0xFFC35E5E),
                        side: BorderSide(
                          color: widget.palette.border.withValues(alpha: 0.4),
                        ),
                        onChanged: (bool? value) {
                          setDialogState(() {
                            skipNextTime = value ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          "Don't ask again",
                          style: TextStyle(
                            color: widget.palette.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      const DeleteConfirmationResult(
                        confirmed: false,
                        skipNextTime: false,
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: widget.palette.textSecondary,
                  ),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      DeleteConfirmationResult(
                        confirmed: true,
                        skipNextTime: skipNextTime,
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC35E5E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('DELETE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.palette.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final LayoutScale scale = LayoutScale.fromWidth(
              constraints.maxWidth,
            );

            return Column(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    scale.screenPadding,
                    16,
                    scale.screenPadding,
                    0,
                  ),
                  child: HeaderWidget(
                    scale: scale,
                    palette: widget.palette,
                    isDarkMode: widget.isDarkMode,
                    onThemeToggle: widget.onThemeToggle,
                    isEditMode: _isEditMode,
                    onEditToggle: _toggleEditMode,
                  ),
                ),
                SizedBox(height: scale.sectionGap),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _clearSelectionMode,
                    child: groups.isEmpty
                        ? Center(
                            child: Text(
                              'No workspaces yet',
                              style: TextStyle(
                                color: widget.palette.textSecondary,
                                fontSize: 13,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            padding: EdgeInsets.symmetric(
                              horizontal: scale.screenPadding,
                            ),
                            itemCount: groups.length,
                            onReorder: _onReorder,
                            onReorderStart: (_) {
                              if (_isEditMode) return;
                              HapticFeedback.mediumImpact();
                            },
                            proxyDecorator:
                                (
                                  Widget child,
                                  int index,
                                  Animation<double> animation,
                                ) {
                                  return AnimatedBuilder(
                                    animation: animation,
                                    child: child,
                                    builder:
                                        (BuildContext context, Widget? child) {
                                          final double t = Curves.easeOut
                                              .transform(animation.value);
                                          return Transform.scale(
                                            scale: 1.02 + (0.03 * t),
                                            child: Material(
                                              type: MaterialType.transparency,
                                              color: Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        scale.cardRadius,
                                                      ),
                                                  boxShadow: <BoxShadow>[
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.18 * t,
                                                          ),
                                                      blurRadius: 10 + (10 * t),
                                                      spreadRadius: 0.5,
                                                    ),
                                                  ],
                                                ),
                                                child: child,
                                              ),
                                            ),
                                          );
                                        },
                                  );
                                },
                            buildDefaultDragHandles: false,
                            itemBuilder: (BuildContext context, int index) {
                              final AppGroupData group = groups[index];
                              final String workspaceId = group.name;
                              final Key itemKey = ObjectKey(group);

                              final Widget card = GroupCard(
                                data: group,
                                scale: scale,
                                palette: widget.palette,
                                launchingApps: _launchingApps,
                                onAppTap: (String app) => _onAppTap(app),
                                onAddTap: () => _onAddTap(group.name),
                                isEditMode: _isEditMode,
                                isSelected: _selectedWorkspaces.contains(
                                  workspaceId,
                                ),
                                onCardTap: () => _onGroupTap(index),
                                onCardLongPress: () => _onGroupLongPress(index),
                              );

                              final Widget item = Container(
                                margin: EdgeInsets.only(
                                  bottom: scale.sectionGap,
                                ),
                                child: card,
                              );

                              if (_isEditMode) {
                                return KeyedSubtree(key: itemKey, child: item);
                              }

                              return ReorderableDelayedDragStartListener(
                                key: itemKey,
                                index: index,
                                child: item,
                              );
                            },
                          ),
                  ),
                ),
                BottomCTA(
                  scale: scale,
                  palette: widget.palette,
                  isDeleteMode: _isEditMode,
                  isEnabled: !_isEditMode || _hasSelectedWorkspaces,
                  onTap: _isEditMode ? _onDeleteSelected : _onAddWorkspace,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onAppTap(String packageName) {
    final DateTime now = DateTime.now();

    setState(() {
      _launchingApps[packageName] = true;

      for (int i = 0; i < groups.length; i++) {
        final AppGroupData group = groups[i];
        final List<AppData> updatedApps = group.apps.map((AppData app) {
          if (app.packageName == packageName) {
            return app.copyWith(usageCount: app.usageCount + 1, lastUsed: now);
          }
          return app;
        }).toList();

        groups[i] = AppGroupData(
          icon: group.icon,
          name: group.name,
          accent: group.accent,
          apps: updatedApps,
        );
      }
    });

    unawaited(_saveGroups());
    AppService.launchApp(packageName);

    // Delay reordering to avoid immediate tile jumping right at tap time.
    Future<void>.delayed(const Duration(seconds: 1), () async {
      if (!mounted) return;

      bool didReorder = false;
      setState(() {
        for (int i = 0; i < groups.length; i++) {
          final AppGroupData group = groups[i];
          final List<String> originalOrder = group.apps
              .map((AppData app) => app.packageName)
              .toList();

          final List<AppData> sortedApps = List<AppData>.from(group.apps)
            ..sort(_smartSort);

          final List<String> sortedOrder = sortedApps
              .map((AppData app) => app.packageName)
              .toList();

          if (!listEquals(originalOrder, sortedOrder)) {
            didReorder = true;
            groups[i] = AppGroupData(
              icon: group.icon,
              name: group.name,
              accent: group.accent,
              apps: sortedApps,
            );
          }
        }
      });

      if (didReorder) {
        await _saveGroups();
      }
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _launchingApps.remove(packageName);
      });
    });
  }

  int _smartSort(AppData a, AppData b) {
    final double bScore = _smartScore(b);
    final double aScore = _smartScore(a);
    final int scoreCompare = bScore.compareTo(aScore);
    if (scoreCompare != 0) {
      return scoreCompare;
    }

    // Stable tie-breakers for deterministic ordering.
    if (a.usageCount != b.usageCount) {
      return b.usageCount.compareTo(a.usageCount);
    }

    if (a.lastUsed != null && b.lastUsed != null) {
      return b.lastUsed!.compareTo(a.lastUsed!);
    }

    if (a.lastUsed == null && b.lastUsed != null) {
      return 1;
    }

    if (a.lastUsed != null && b.lastUsed == null) {
      return -1;
    }

    return 0;
  }

  double _smartScore(AppData app) {
    if (app.lastUsed == null) {
      return app.usageCount.toDouble();
    }

    final DateTime now = DateTime.now();
    final Duration sinceUse = now.difference(app.lastUsed!);
    final double hoursAgo = sinceUse.inMinutes / 60;
    final double recencyBoost = 3 / (1 + hoursAgo);

    return app.usageCount + recencyBoost;
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_isEditMode) return;

    setState(() {
      if (newIndex > oldIndex) newIndex--;

      final AppGroupData item = groups.removeAt(oldIndex);
      groups.insert(newIndex, item);
    });

    await _saveGroups();
  }

  Future<void> _onAddTap(String groupName) async {
    if (_isEditMode) return;

    AppGroupData? existingGroup;
    try {
      existingGroup = groups.firstWhere(
        (AppGroupData group) => group.name == groupName,
      );
    } catch (e) {
      return; // Group not found
    }

    final AppGroupData? result = await Navigator.push<AppGroupData>(
      context,
      MaterialPageRoute<AppGroupData>(
        builder: (_) => CreateWorkspaceScreen(
          palette: widget.palette,
          initialGroup: existingGroup,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        final int index = groups.indexWhere(
          (AppGroupData group) => group.name == groupName,
        );
        if (index != -1) {
          groups[index] = result;
        }
      });
      await _saveGroups();
    }
  }

  Future<void> _onAddWorkspace() async {
    if (_isEditMode) {
      await _onDeleteSelected();
      return;
    }

    final AppGroupData? result = await Navigator.push<AppGroupData>(
      context,
      MaterialPageRoute<AppGroupData>(
        builder: (_) => CreateWorkspaceScreen(palette: widget.palette),
      ),
    );
    if (result != null) {
      setState(() {
        groups.add(result);
      });
      await _saveGroups();
    }
  }
}

class HeaderWidget extends StatelessWidget {
  const HeaderWidget({
    required this.scale,
    required this.palette,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.isEditMode,
    required this.onEditToggle,
    super.key,
  });

  final LayoutScale scale;
  final AppPalette palette;
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final bool isEditMode;
  final VoidCallback onEditToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        GestureDetector(
          onTap: onEditToggle,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            style: TextStyle(
              color: isEditMode ? palette.mint : palette.textSecondary,
              fontSize: 12,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
            child: Text(isEditMode ? 'DONE' : 'EDIT'),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onThemeToggle,
          child: Container(
            width: scale.toggleSize,
            height: scale.toggleSize,
            decoration: BoxDecoration(
              color: palette.toggleBackground,
              borderRadius: BorderRadius.circular(scale.toggleSize / 2),
              border: Border.all(color: palette.toggleBorder),
            ),
            alignment: Alignment.center,
            child: Icon(
              isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_rounded,
              color: palette.textPrimary,
              size: scale.toggleIconSize,
            ),
          ),
        ),
      ],
    );
  }
}

class GroupCard extends StatelessWidget {
  const GroupCard({
    required this.data,
    required this.scale,
    required this.palette,
    required this.launchingApps,
    required this.onAppTap,
    required this.onAddTap,
    required this.isEditMode,
    required this.isSelected,
    required this.onCardTap,
    required this.onCardLongPress,
    super.key,
  });

  final AppGroupData data;
  final LayoutScale scale;
  final AppPalette palette;
  final Map<String, bool> launchingApps;
  final ValueChanged<String> onAppTap;
  final Future<void> Function() onAddTap;
  final bool isEditMode;
  final bool isSelected;
  final VoidCallback onCardTap;
  final VoidCallback onCardLongPress;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isSelected ? 0.988 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCardTap,
        onLongPress: isEditMode ? onCardLongPress : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.all(scale.cardPadding),
          decoration: BoxDecoration(
            color: isSelected
                ? Color.alphaBlend(
                    palette.mint.withValues(alpha: 0.08),
                    palette.surface,
                  )
                : palette.surface,
            borderRadius: BorderRadius.circular(scale.cardRadius),
            border: Border.all(
              color: isSelected ? palette.mint : palette.surfaceBorder,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? <BoxShadow>[
                    BoxShadow(
                      color: palette.mint.withValues(alpha: 0.16),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            Icon(data.icon, color: data.accent, size: 16),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                data.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: data.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: <Widget>[
                          Text(
                            '${data.apps.length} APPS',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: scale.cardPadding),
                  IgnorePointer(
                    ignoring: isEditMode,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          ...data.apps.map(
                            (AppData app) => Padding(
                              padding: EdgeInsets.only(right: scale.tileGap),
                              child: AppTileCreate(
                                app: InstalledApp(
                                  packageName: app.packageName,
                                  appName: app.appName,
                                  icon: app.icon,
                                ),
                                palette: palette,
                                isSelected: false,
                                isLaunching:
                                    launchingApps[app.packageName] ?? false,
                                onTap: () => onAppTap(app.packageName),
                              ),
                            ),
                          ),
                          AddTile(
                            tileSize: scale.tileSize,
                            palette: palette,
                            onTap: onAddTap,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (isEditMode)
                Align(
                  alignment: Alignment.topRight,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isSelected ? palette.mint : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: isSelected
                            ? palette.mint
                            : palette.border.withValues(alpha: 0.4),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: isSelected ? 1 : 0,
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: widgetForegroundFor(palette.mint),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppTile extends StatelessWidget {
  const AppTile({
    required this.label,
    required this.icon,
    required this.palette,
    required this.tileSize,
    required this.onTap,
    super.key,
  });

  final String label;
  final Uint8List icon;
  final AppPalette palette;
  final double tileSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: tileSize,
        child: Column(
          children: <Widget>[
            Container(
              width: tileSize,
              height: tileSize,
              decoration: BoxDecoration(
                color: palette.tile,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.tileBorder),
              ),
              alignment: Alignment.center,
              child: Image.memory(
                icon,
                width: tileSize * 0.6,
                height: tileSize * 0.6,
                fit: BoxFit.contain,
                errorBuilder:
                    (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) {
                      return Icon(
                        Icons.apps,
                        size: tileSize * 0.4,
                        color: palette.textSecondary,
                      );
                    },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddTile extends StatelessWidget {
  const AddTile({
    required this.tileSize,
    required this.palette,
    required this.onTap,
    super.key,
  });

  final double tileSize;
  final AppPalette palette;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: tileSize,
        child: Column(
          children: <Widget>[
            Container(
              width: tileSize,
              height: tileSize,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.addTileBorder),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add_rounded,
                color: palette.textSecondary,
                size: tileSize * 0.33,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ADD',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BottomCTA extends StatelessWidget {
  const BottomCTA({
    required this.scale,
    required this.palette,
    required this.isDeleteMode,
    required this.isEnabled,
    required this.onTap,
    super.key,
  });

  final LayoutScale scale;
  final AppPalette palette;
  final bool isDeleteMode;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        scale.ctaHorizontalPadding,
        8,
        scale.ctaHorizontalPadding,
        16,
      ),
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: scale.ctaHeight,
          decoration: BoxDecoration(
            color: isDeleteMode
                ? (isEnabled
                      ? const Color(0xFFC35E5E)
                      : const Color(0xFF6A4343))
                : palette.ctaBackground,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: isDeleteMode
                  ? (isEnabled
                        ? const Color(0xFFC35E5E)
                        : const Color(0xFF6A4343))
                  : palette.ctaBackground,
            ),
            boxShadow: isDeleteMode
                ? <BoxShadow>[
                    BoxShadow(
                      color:
                          (isEnabled
                                  ? const Color(0xFFC35E5E)
                                  : const Color(0xFF6A4343))
                              .withValues(alpha: 0.22),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
              child: Text(
                isDeleteMode ? 'DELETE' : 'ADD MORE +',
                key: ValueKey<bool>(isDeleteMode),
                style: TextStyle(
                  color: isDeleteMode ? Colors.white : palette.ctaText,
                  fontSize: scale.ctaTextSize,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGroupData {
  const AppGroupData({
    required this.icon,
    required this.name,
    required this.accent,
    required this.apps,
  });

  final IconData icon;
  final String name;
  final Color accent;
  final List<AppData> apps;
}

class AppData {
  const AppData({
    required this.packageName,
    required this.appName,
    required this.icon,
    this.usageCount = 0,
    this.lastUsed,
  });

  final String packageName;
  final String appName;
  final Uint8List icon;
  final int usageCount;
  final DateTime? lastUsed;

  AppData copyWith({int? usageCount, DateTime? lastUsed}) {
    return AppData(
      packageName: packageName,
      appName: appName,
      icon: icon,
      usageCount: usageCount ?? this.usageCount,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

const List<Color> accentColors = <Color>[
  Color(0xFF3CFFD0), // mint
  Color(0xFFFF6B6B), // red
  Color(0xFF4ECDC4), // teal
  Color(0xFF45B7D1), // blue
  Color(0xFFF9CA24), // yellow
  Color(0xFFF0932B), // orange
  Color(0xFFEB4D4B), // pink
  Color(0xFF6C5CE7), // purple
];

const List<IconData> groupIcons = <IconData>[
  Icons.work_rounded,
  Icons.home_rounded,
  Icons.favorite_rounded,
  Icons.star_rounded,
  Icons.business_rounded,
  Icons.school_rounded,
  Icons.sports_soccer_rounded,
  Icons.music_note_rounded,
  Icons.camera_alt_rounded,
  Icons.restaurant_rounded,
  Icons.local_shipping_rounded,
  Icons.health_and_safety_rounded,
];

// Serialization helpers
class AppDataPersistence {
  static Map<String, dynamic> toJson(AppData app) {
    return <String, dynamic>{
      'packageName': app.packageName,
      'appName': app.appName,
      'icon': app.icon,
      'usageCount': app.usageCount,
      'lastUsed': app.lastUsed?.millisecondsSinceEpoch,
    };
  }

  static AppData fromJson(Map<String, dynamic> json) {
    return AppData(
      packageName: json['packageName'] as String,
      appName: json['appName'] as String,
      icon: Uint8List.fromList((json['icon'] as List<dynamic>).cast<int>()),
      usageCount: json['usageCount'] as int? ?? 0,
      lastUsed: json['lastUsed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastUsed'] as int)
          : null,
    );
  }
}

class AppGroupDataPersistence {
  static Map<String, dynamic> toJson(AppGroupData group) {
    final int iconIndex = groupIcons.indexOf(group.icon);
    return <String, dynamic>{
      'iconIndex': iconIndex != -1 ? iconIndex : 0, // fallback to first icon
      'name': group.name,
      'accentValue': group.accent.toARGB32(),
      'apps': group.apps.map(AppDataPersistence.toJson).toList(),
    };
  }

  static AppGroupData fromJson(Map<String, dynamic> json) {
    final int iconIndex = json['iconIndex'] as int? ?? 0;
    final IconData icon = iconIndex < groupIcons.length
        ? groupIcons[iconIndex]
        : groupIcons[0];
    return AppGroupData(
      icon: icon,
      name: json['name'] as String,
      accent: Color(json['accentValue'] as int),
      apps: (json['apps'] as List<dynamic>)
          .map(
            (dynamic app) =>
                AppDataPersistence.fromJson(app as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class PersistenceManager {
  static const String _groupsKey = 'app_groups';
  static const String _appsKey = 'installed_apps_cache';
  static const String _skipDeleteConfirmationKey =
      'skip_workspace_delete_confirmation';

  static Future<void> saveGroups(List<AppGroupData> groups) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> groupsJson = groups
        .map(
          (AppGroupData group) =>
              jsonEncode(AppGroupDataPersistence.toJson(group)),
        )
        .toList();
    await prefs.setStringList(_groupsKey, groupsJson);
  }

  static Future<List<AppGroupData>> loadGroups() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? groupsJson = prefs.getStringList(_groupsKey);
    if (groupsJson == null) return <AppGroupData>[];

    return groupsJson
        .map(
          (String groupJson) => AppGroupDataPersistence.fromJson(
            jsonDecode(groupJson) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  static Future<void> saveApps(List<InstalledApp> apps) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> appsJson = apps
        .map(
          (InstalledApp app) => jsonEncode(<String, dynamic>{
            'packageName': app.packageName,
            'appName': app.appName,
            'icon': base64Encode(app.icon),
          }),
        )
        .toList();
    await prefs.setStringList(_appsKey, appsJson);
  }

  static Future<List<InstalledApp>> loadApps() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? appsJson = prefs.getStringList(_appsKey);
    if (appsJson == null) return <InstalledApp>[];

    return appsJson.map((String appJson) {
      final Map<String, dynamic> decoded =
          jsonDecode(appJson) as Map<String, dynamic>;
      return InstalledApp(
        packageName: decoded['packageName'] as String,
        appName: decoded['appName'] as String,
        icon: base64Decode(decoded['icon'] as String),
      );
    }).toList();
  }

  static Future<void> saveSkipDeleteConfirmation(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipDeleteConfirmationKey, value);
  }

  static Future<bool> loadSkipDeleteConfirmation() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_skipDeleteConfirmationKey) ?? false;
  }
}

class DeleteConfirmationResult {
  const DeleteConfirmationResult({
    required this.confirmed,
    required this.skipNextTime,
  });

  final bool confirmed;
  final bool skipNextTime;
}

Color widgetForegroundFor(Color background) {
  return background.computeLuminance() > 0.52 ? Colors.black : Colors.white;
}

class CreateWorkspaceScreen extends StatefulWidget {
  const CreateWorkspaceScreen({
    required this.palette,
    this.initialGroup,
    super.key,
  });

  final AppPalette palette;
  final AppGroupData? initialGroup;

  @override
  State<CreateWorkspaceScreen> createState() => _CreateWorkspaceScreenState();
}

class _CreateWorkspaceScreenState extends State<CreateWorkspaceScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  StreamSubscription<List<InstalledApp>>? _sub;
  final Set<String> _visibleFadeInPackages = <String>{};
  List<InstalledApp> _allApps = <InstalledApp>[];
  List<InstalledApp> _visibleApps = <InstalledApp>[];
  String _searchQuery = '';
  bool _isLoadingApps = true;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<Set<String>> _selectedAppsNotifier =
      ValueNotifier<Set<String>>(<String>{});
  late Color _selectedColor;
  late IconData _selectedIcon;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialGroup?.accent ?? accentColors.first;
    _selectedIcon = widget.initialGroup?.icon ?? groupIcons.first;
    if (widget.initialGroup != null) {
      _nameController.text = widget.initialGroup!.name;
      _selectedAppsNotifier.value.addAll(
        widget.initialGroup!.apps.map((AppData app) => app.packageName),
      );
    }
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _loadInstalledApps();
  }

  List<InstalledApp> _filterApps(List<InstalledApp> source) {
    final String query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return List<InstalledApp>.from(source);

    return source.where((InstalledApp app) {
      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();
  }

  void _onSearchChanged() {
    final String query = _searchController.text;
    if (query == _searchQuery) return;

    setState(() {
      _searchQuery = query;
      _visibleApps = _filterApps(_allApps);
    });
  }

  void _clearSearch() {
    _searchController.clear();
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadInstalledApps() async {
    debugPrint('CreateWorkspaceScreen: Loading cached apps then streaming');

    final List<InstalledApp> cachedApps = await PersistenceManager.loadApps();
    if (!mounted) return;

    if (cachedApps.isNotEmpty) {
      setState(() {
        _allApps = List<InstalledApp>.from(cachedApps);
        _visibleApps = _filterApps(_allApps);
        _visibleFadeInPackages
          ..clear()
          ..addAll(cachedApps.map((InstalledApp app) => app.packageName));
        _isLoadingApps = false;
      });
    }

    _sub?.cancel();
    _sub = AppService.streamApps().listen(
      (List<InstalledApp> batch) {
        if (!mounted) return;

        final List<InstalledApp> newlyAdded = <InstalledApp>[];

        setState(() {
          for (final InstalledApp app in batch) {
            final int allIndex = _allApps.indexWhere(
              (InstalledApp existing) =>
                  existing.packageName == app.packageName,
            );
            if (allIndex == -1) {
              _allApps.add(app);
              newlyAdded.add(app);
            } else {
              _allApps[allIndex] = app;
            }
          }
          _visibleApps = _filterApps(_allApps);
          _isLoadingApps = false;
        });

        if (newlyAdded.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _visibleFadeInPackages.addAll(
                newlyAdded.map((InstalledApp app) => app.packageName),
              );
            });
          });
        }
      },
      onDone: () async {
        await PersistenceManager.saveApps(_allApps);
        if (!mounted) return;
        setState(() {
          _isLoadingApps = false;
        });
      },
      onError: (Object e, StackTrace stack) {
        debugPrint('CreateWorkspaceScreen: stream error $e');
        debugPrint('CreateWorkspaceScreen: stream stack $stack');
        if (!mounted) return;
        setState(() {
          _isLoadingApps = false;
        });
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _nameController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _selectedAppsNotifier.dispose();
    super.dispose();
  }

  void _toggleApp(String appName) {
    final Set<String> current = _selectedAppsNotifier.value;
    if (current.contains(appName)) {
      _selectedAppsNotifier.value = Set<String>.from(current)..remove(appName);
    } else {
      _selectedAppsNotifier.value = Set<String>.from(current)..add(appName);
    }
  }

  void _confirm() {
    final String name = _nameController.text.trim();
    debugPrint(
      'Confirm: name="$name", selected=${_selectedAppsNotifier.value.length}',
    );
    if (name.isEmpty || _selectedAppsNotifier.value.isEmpty) {
      debugPrint('Confirm: conditions not met - showing error');
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a workspace name and select at least one app',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final List<AppData> selectedAppData = _allApps
        .where(
          (InstalledApp app) =>
              _selectedAppsNotifier.value.contains(app.packageName),
        )
        .map(
          (InstalledApp app) => AppData(
            packageName: app.packageName,
            appName: app.appName,
            icon: app.icon,
          ),
        )
        .toList();

    debugPrint('Confirm: selected apps count=${selectedAppData.length}');

    final AppGroupData updatedGroup = AppGroupData(
      icon: _selectedIcon,
      name: name,
      accent: _selectedColor,
      apps: selectedAppData,
    );

    debugPrint('Confirm: popping with group "${updatedGroup.name}"');
    Navigator.pop(context, updatedGroup);
  }

  Future<void> _showWorkspaceStylePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: widget.palette.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(
                  color: widget.palette.border.withValues(alpha: 0.18),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.palette.textSecondary.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'STYLE WORKSPACE',
                      style: TextStyle(
                        color: widget.palette.textSecondary,
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: accentColors.map((Color color) {
                        final bool isSelected = _selectedColor == color;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              setState(() {
                                _selectedColor = color;
                              });
                              setModalState(() {});
                              HapticFeedback.selectionClick();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? widgetForegroundFor(color)
                                      : widget.palette.border.withValues(
                                          alpha: 0.2,
                                        ),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 140),
                                opacity: isSelected ? 1 : 0,
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 17,
                                  color: widgetForegroundFor(color),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      color: widget.palette.border.withValues(alpha: 0.16),
                      height: 1,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ICON',
                      style: TextStyle(
                        color: widget.palette.textSecondary,
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: groupIcons.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 52,
                          ),
                      itemBuilder: (BuildContext context, int index) {
                        final IconData icon = groupIcons[index];
                        final bool isSelected = _selectedIcon == icon;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              setState(() {
                                _selectedIcon = icon;
                              });
                              setModalState(() {});
                              HapticFeedback.selectionClick();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _selectedColor.withValues(alpha: 0.16)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? _selectedColor
                                      : widget.palette.border.withValues(
                                          alpha: 0.22,
                                        ),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                icon,
                                color: isSelected
                                    ? _selectedColor
                                    : widget.palette.textSecondary,
                                size: 22,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.palette.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: <Widget>[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'WORKSPACE NAME',
                                style: TextStyle(
                                  color: widget.palette.textSecondary,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  GestureDetector(
                                    onTap: _showWorkspaceStylePicker,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: widget.palette.border,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        _selectedIcon,
                                        color: _selectedColor,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: widget.palette.border,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      alignment: Alignment.center,
                                      child: TextField(
                                        controller: _nameController,
                                        style: TextStyle(
                                          color: widget.palette.textPrimary,
                                          fontSize: 14,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'E.G. DESIGN OPS',
                                          hintStyle: TextStyle(
                                            color: widget.palette.textSecondary,
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap the icon to choose style',
                                style: TextStyle(
                                  color: widget.palette.textSecondary
                                      .withValues(alpha: 0.78),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                'SELECT APPS',
                                style: TextStyle(
                                  color: widget.palette.textSecondary,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              ValueListenableBuilder<Set<String>>(
                                valueListenable: _selectedAppsNotifier,
                                builder:
                                    (
                                      BuildContext context,
                                      Set<String> selectedApps,
                                      Widget? child,
                                    ) {
                                      return Text(
                                        '${selectedApps.length} SELECTED',
                                        style: TextStyle(
                                          color: widget.palette.mint,
                                          fontSize: 10,
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      );
                                    },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: widget.palette.tile.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: _searchFocusNode.hasFocus
                                    ? widget.palette.mint.withValues(
                                        alpha: 0.65,
                                      )
                                    : widget.palette.border.withValues(
                                        alpha: 0.35,
                                      ),
                              ),
                              boxShadow: _searchFocusNode.hasFocus
                                  ? <BoxShadow>[
                                      BoxShadow(
                                        color: widget.palette.mint.withValues(
                                          alpha: 0.14,
                                        ),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : const <BoxShadow>[],
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.search,
                                  size: 19,
                                  color: widget.palette.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    focusNode: _searchFocusNode,
                                    style: TextStyle(
                                      color: widget.palette.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Search apps',
                                      hintStyle: TextStyle(
                                        color: widget.palette.textSecondary,
                                        fontSize: 13,
                                        letterSpacing: 0.6,
                                      ),
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                    ),
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 160),
                                  child: _searchQuery.trim().isEmpty
                                      ? const SizedBox(width: 18, height: 18)
                                      : GestureDetector(
                                          key: const ValueKey<String>('clear'),
                                          onTap: _clearSearch,
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: widget.palette.textSecondary,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isLoadingApps)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) =>
                              const SkeletonAppTile(),
                          childCount: 20,
                        ),
                      ),
                    )
                  else if (_visibleApps.isNotEmpty)
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedAppsNotifier,
                      builder:
                          (
                            BuildContext context,
                            Set<String> selectedApps,
                            Widget? child,
                          ) {
                            return SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  BuildContext context,
                                  int index,
                                ) {
                                  final InstalledApp app = _visibleApps[index];
                                  return AnimatedOpacity(
                                    opacity:
                                        _visibleFadeInPackages.contains(
                                          app.packageName,
                                        )
                                        ? 1
                                        : 0,
                                    duration: const Duration(milliseconds: 300),
                                    child: AppTileCreate(
                                      app: app,
                                      palette: widget.palette,
                                      isSelected: selectedApps.contains(
                                        app.packageName,
                                      ),
                                      isLaunching: false,
                                      onTap: () => _toggleApp(app.packageName),
                                    ),
                                  );
                                }, childCount: _visibleApps.length),
                              ),
                            );
                          },
                    )
                  else
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 280),
                          tween: Tween<double>(begin: 0, end: 1),
                          builder:
                              (
                                BuildContext context,
                                double opacity,
                                Widget? child,
                              ) {
                                return Opacity(opacity: opacity, child: child);
                              },
                          child: Text(
                            'Nothing here',
                            style: TextStyle(
                              color: widget.palette.textSecondary.withValues(
                                alpha: 0.72,
                              ),
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: widget.palette.bg,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.45 - 8,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: widget.palette.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'CANCEL',
                        style: TextStyle(
                          color: widget.palette.textPrimary,
                          fontSize: 14,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _confirm,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.45 - 8,
                      height: 48,
                      decoration: BoxDecoration(
                        color: widget.palette.ctaBackground,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.initialGroup != null ? 'SAVE' : 'CONFIRM',
                        style: TextStyle(
                          color: widget.palette.ctaText,
                          fontSize: 14,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppTileCreate extends StatelessWidget {
  const AppTileCreate({
    required this.app,
    required this.palette,
    required this.isSelected,
    required this.isLaunching,
    required this.onTap,
    super.key,
  });

  final InstalledApp app;
  final AppPalette palette;
  final bool isSelected;
  final bool isLaunching;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: palette.tile,
              borderRadius: BorderRadius.circular(16),
              border: isSelected
                  ? Border.all(color: palette.mint, width: 1.5)
                  : Border.all(color: Colors.transparent),
            ),
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Image.memory(
                  app.icon,
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                  errorBuilder:
                      (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) {
                        return Icon(
                          Icons.android,
                          size: 24,
                          color: palette.textSecondary,
                        );
                      },
                ),
                if (isLaunching)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 60,
            child: Text(
              app.appName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 9,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonAppTile extends StatelessWidget {
  const SkeletonAppTile({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.dark(); // or get from context
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: palette.tile,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 4),
        Container(width: 60, height: 10, color: palette.tile),
      ],
    );
  }
}

class MoreTile extends StatelessWidget {
  const MoreTile({required this.palette, super.key});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.addTileBorder),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.add_rounded,
            color: palette.textSecondary,
            size: 22,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: Text(
            'MORE',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 9,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class AppPalette {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.tile,
    required this.textPrimary,
    required this.textSecondary,
    required this.surfaceBorder,
    required this.tileBorder,
    required this.addTileBorder,
    required this.toggleBackground,
    required this.toggleBorder,
    required this.ctaBackground,
    required this.ctaText,
    required this.border,
    required this.mint,
    required this.purple,
  });

  const AppPalette.dark()
    : bg = const Color(0xFF131313),
      surface = const Color(0xFF1A1A1A),
      tile = const Color(0xFF2D2D2D),
      textPrimary = Colors.white,
      textSecondary = const Color(0xFF949494),
      surfaceBorder = const Color.fromRGBO(255, 255, 255, 0.1),
      tileBorder = const Color.fromRGBO(255, 255, 255, 0.2),
      addTileBorder = const Color.fromRGBO(255, 255, 255, 0.2),
      toggleBackground = const Color(0xFF131313),
      toggleBorder = const Color(0xFF2D2D2D),
      ctaBackground = const Color(0xFF3CFFD0),
      ctaText = Colors.black,
      border = Colors.white,
      mint = const Color(0xFF3CFFD0),
      purple = const Color(0xFF6C5CE7);

  const AppPalette.light()
    : bg = const Color(0xFFF3F5F7),
      surface = const Color(0xFFFFFFFF),
      tile = const Color(0xFFE7EBEF),
      textPrimary = const Color(0xFF14171C),
      textSecondary = const Color(0xFF5E6670),
      surfaceBorder = const Color(0x22000000),
      tileBorder = const Color(0x24000000),
      addTileBorder = const Color(0x30000000),
      toggleBackground = const Color(0xFFFFFFFF),
      toggleBorder = const Color(0x22000000),
      ctaBackground = const Color(0xFF14171C),
      ctaText = const Color(0xFF3CFFD0),
      border = Colors.black,
      mint = const Color(0xFF3CFFD0),
      purple = const Color(0xFF6C5CE7);

  final Color bg;
  final Color surface;
  final Color tile;
  final Color textPrimary;
  final Color textSecondary;
  final Color surfaceBorder;
  final Color tileBorder;
  final Color addTileBorder;
  final Color toggleBackground;
  final Color toggleBorder;
  final Color ctaBackground;
  final Color ctaText;
  final Color border;
  final Color mint;
  final Color purple;
}

class LayoutScale {
  const LayoutScale({
    required this.screenPadding,
    required this.sectionGap,
    required this.cardPadding,
    required this.cardRadius,
    required this.tileSize,
    required this.tileGap,
    required this.avatarSize,
    required this.avatarIconSize,
    required this.consoleTextSize,
    required this.rootTextSize,
    required this.toggleSize,
    required this.toggleIconSize,
    required this.ctaHorizontalPadding,
    required this.ctaHeight,
    required this.ctaTextSize,
  });

  factory LayoutScale.fromWidth(double width) {
    final bool compact = width < 360;
    final double adaptivePadding = _clamp(width * 0.045, 12, 20);

    return LayoutScale(
      screenPadding: adaptivePadding,
      sectionGap: compact ? 14 : 16,
      cardPadding: compact ? 14 : 16,
      cardRadius: compact ? 18 : 20,
      tileSize: _clamp(width * 0.18, 64, 72),
      tileGap: compact ? 10 : 12,
      avatarSize: _clamp(width * 0.11, 40, 46),
      avatarIconSize: compact ? 20 : 22,
      consoleTextSize: compact ? 10 : 11,
      rootTextSize: compact ? 16 : 18,
      toggleSize: compact ? 38 : 40,
      toggleIconSize: compact ? 17 : 18,
      ctaHorizontalPadding: _clamp(width * 0.06, 16, 28),
      ctaHeight: _clamp(width * 0.15, 56, 64),
      ctaTextSize: compact ? 14 : 15,
    );
  }

  final double screenPadding;
  final double sectionGap;
  final double cardPadding;
  final double cardRadius;
  final double tileSize;
  final double tileGap;
  final double avatarSize;
  final double avatarIconSize;
  final double consoleTextSize;
  final double rootTextSize;
  final double toggleSize;
  final double toggleIconSize;
  final double ctaHorizontalPadding;
  final double ctaHeight;
  final double ctaTextSize;
}

double _clamp(double value, double min, double max) =>
    value.clamp(min, max).toDouble();
