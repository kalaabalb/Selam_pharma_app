// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'medicine.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MedicineAdapter extends TypeAdapter<Medicine> {
  @override
  final int typeId = 0;

  @override
  Medicine read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Medicine(
      id: fields[0] as String,
      name: fields[1] as String,
      totalQty: fields[2] as int,
      buyPrice: fields[3] as int,
      sellPrice: fields[4] as int,
      imageBytes: fields[5] as Uint8List?,
      soldQty: fields[6] as int,
      category: fields[7] as String?,
      barcode: fields[8] as String?,
      imageUrl: fields[9] as String?,
      cloudinaryPublicId: fields[10] as String?,
      lastModifiedMillis: fields[11] as int?,
      deletedAtMillis: fields[12] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Medicine obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.totalQty)
      ..writeByte(3)
      ..write(obj.buyPrice)
      ..writeByte(4)
      ..write(obj.sellPrice)
      ..writeByte(5)
      ..write(obj.imageBytes)
      ..writeByte(6)
      ..write(obj.soldQty)
      ..writeByte(7)
      ..write(obj.category)
      ..writeByte(8)
      ..write(obj.barcode)
      ..writeByte(9)
      ..write(obj.imageUrl)
      ..writeByte(10)
      ..write(obj.cloudinaryPublicId)
      ..writeByte(11)
      ..write(obj.lastModifiedMillis)
      ..writeByte(12)
      ..write(obj.deletedAtMillis);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MedicineAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
