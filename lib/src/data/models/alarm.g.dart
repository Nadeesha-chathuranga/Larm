// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alarm.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AlarmAdapter extends TypeAdapter<Alarm> {
  @override
  final typeId = 0;

  @override
  Alarm read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Alarm(
      id: fields[0] as String,
      title: fields[1] as String,
      isUtc: fields[2] as bool,
      hour: (fields[3] as num).toInt(),
      minute: (fields[4] as num).toInt(),
      year: (fields[5] as num?)?.toInt(),
      month: (fields[6] as num?)?.toInt(),
      day: (fields[7] as num?)?.toInt(),
      repeat: (fields[8] as num).toInt(),
      days: (fields[9] as List).cast<bool>(),
      enabled: fields[10] as bool,
      soundId: fields[11] as String,
      vibId: fields[12] as String,
      createdAtUtc: fields[13] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Alarm obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.isUtc)
      ..writeByte(3)
      ..write(obj.hour)
      ..writeByte(4)
      ..write(obj.minute)
      ..writeByte(5)
      ..write(obj.year)
      ..writeByte(6)
      ..write(obj.month)
      ..writeByte(7)
      ..write(obj.day)
      ..writeByte(8)
      ..write(obj.repeat)
      ..writeByte(9)
      ..write(obj.days)
      ..writeByte(10)
      ..write(obj.enabled)
      ..writeByte(11)
      ..write(obj.soundId)
      ..writeByte(12)
      ..write(obj.vibId)
      ..writeByte(13)
      ..write(obj.createdAtUtc);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
