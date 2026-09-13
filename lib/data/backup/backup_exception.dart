/// Thrown when a backup file fails validation during restore - malformed
/// JSON, a missing or unsupported schema version, a missing or wrong-typed
/// required field, a duplicate id within a table, or a relationship that
/// points at an id the backup doesn't actually contain. Restore never lets
/// a problem like this reach the database layer; every failure mode is
/// caught in [BackupRepository.parseAndValidate] and turned into one clear
/// [message] the UI can show as-is.
class BackupValidationException implements Exception {
  const BackupValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
