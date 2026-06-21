import '../../domain/entities/focus_session.dart';

class FocusSessionModel extends FocusSession {
  const FocusSessionModel({
    super.id,
    required super.startTime,
    required super.endTime,
    required super.duration,
  });

  /// Construct from a SQLite row map.
  factory FocusSessionModel.fromMap(Map<String, dynamic> map) {
    return FocusSessionModel(
      id: map['id'] as int?,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      duration: map['duration'] as int,
    );
  }

  /// Convert to a SQLite row map (omits id when null — for INSERT).
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'duration': duration,
    };
  }

  /// Promote a domain entity to a persistable model.
  factory FocusSessionModel.fromEntity(FocusSession entity) {
    return FocusSessionModel(
      id: entity.id,
      startTime: entity.startTime,
      endTime: entity.endTime,
      duration: entity.duration,
    );
  }
}
