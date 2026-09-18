// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsAdapter extends TypeAdapter<Settings> {
  @override
  final typeId = 2;

  @override
  Settings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Settings(
      soundMode: (fields[0] as num).toInt(),
      snoozeMin: (fields[1] as num).toInt(),
      snoozeCount: (fields[2] as num).toInt(),
      themeMode: (fields[3] as num).toInt(),
      family: (fields[4] as num).toInt(),
      timeFormat: (fields[5] as num).toInt(),
      defaultSoundId: fields[6] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Settings obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.soundMode)
      ..writeByte(1)
      ..write(obj.snoozeMin)
      ..writeByte(2)
      ..write(obj.snoozeCount)
      ..writeByte(3)
      ..write(obj.themeMode)
      ..writeByte(4)
      ..write(obj.family)
      ..writeByte(5)
      ..write(obj.timeFormat)
      ..writeByte(6)
      ..write(obj.defaultSoundId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
