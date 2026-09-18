// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'larm_timer.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LarmTimerAdapter extends TypeAdapter<LarmTimer> {
  @override
  final typeId = 1;

  @override
  LarmTimer read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LarmTimer(
      id: fields[0] as String,
      title: fields[1] as String,
      durationSec: (fields[2] as num).toInt(),
      remainingSec: (fields[3] as num).toInt(),
      status: (fields[4] as num).toInt(),
      targetUtc: fields[5] as DateTime?,
      enabled: fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LarmTimer obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.durationSec)
      ..writeByte(3)
      ..write(obj.remainingSec)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.targetUtc)
      ..writeByte(6)
      ..write(obj.enabled);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LarmTimerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
