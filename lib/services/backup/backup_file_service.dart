import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One backup file discovered on disk.
class BackupFileInfo {
  const BackupFileInfo({required this.file, required this.modifiedAt});

  final File file;
  final DateTime modifiedAt;

  String get name => p.basename(file.path);
}

/// Reads and writes REmind's local backup files.
///
/// Backups live in this app's own private documents directory (no storage
/// permission needed on any Android version) under a `backups/`
/// subfolder, named with a timestamp so multiple backups never collide and
/// sort naturally by name. This is the only backup-feature class that
/// touches `dart:io`/`path_provider` - `BackupRepository` is plain,
/// file-free logic that tests exercise directly with in-memory JSON
/// strings, the same way `NotificationTransport` keeps real platform
/// channel calls out of everything but the transport itself.
class BackupFileService {
  Future<Directory> _backupsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes [jsonContent] to a new timestamped file and returns it.
  Future<File> writeBackup(String jsonContent) async {
    final dir = await _backupsDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file = File(p.join(dir.path, 'remind_backup_$timestamp.json'));
    await file.writeAsString(jsonContent);
    return file;
  }

  /// Writes [jsonContent] as a pre-restore safety copy, distinguishable in
  /// the file listing from a backup the user made on purpose.
  Future<File> writeSafetyBackup(String jsonContent) async {
    final dir = await _backupsDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final file =
        File(p.join(dir.path, 'remind_before_restore_$timestamp.json'));
    await file.writeAsString(jsonContent);
    return file;
  }

  /// Lists every backup file on disk, most recently modified first.
  Future<List<BackupFileInfo>> listBackups() async {
    final dir = await _backupsDirectory();
    final entries = await dir.list().toList();
    final infos = <BackupFileInfo>[];
    for (final entry in entries) {
      if (entry is File && entry.path.endsWith('.json')) {
        final stat = await entry.stat();
        infos.add(BackupFileInfo(file: entry, modifiedAt: stat.modified));
      }
    }
    infos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return infos;
  }

  Future<String> readBackup(File file) => file.readAsString();
}
