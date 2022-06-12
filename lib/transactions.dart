import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_porter/utils/csv_utils.dart';

import 'item.dart';


class TransactionLedger {
  Function refresh;
  List<TransactionRecord> transactionRecords = [];
  Future<Database> database;
  Future<bool> loaded;
  TransactionLedger(this.refresh){
    loadDatabase();
  }

  void addNewTransaction(TransactionRecord transactionRecord) {
    transactionRecords.add(transactionRecord);
    insertTransactionRecordInDB(transactionRecord);
  }

  void removeTransaction(TransactionRecord transactionRecord){
    transactionRecords.remove(transactionRecord);
    deleteItemFromDB(transactionRecord);

  }importFromCSV(filePath) async {
    final input = new File(filePath).openRead();
    final fields = await input.transform(utf8.decoder).transform(CsvToListConverter()).toList();
    final header = fields[0];

    for (final row in fields.sublist(1)){
      Map<String, dynamic> dbRow = Map();
      for (int index = 0; index < header.length; index++){
        dbRow[header[index]] = row[index];
      }
      insertMapInDB(dbRow);
    }
    setTransactionRecordsFromDB();
    refresh();
  }

  Future<String> toCSV() async{
    await loaded;
    var result = await (await database).query('transactionRecords');
    return mapListToCsv(result);
  }

  Future<void> loadDatabase() async {
    database = openDatabase(
      join(await getDatabasesPath(), 'transactions_database.db'),

      onCreate: (db, version) {
        return db.execute(
          "CREATE TABLE transactionRecords(barCode TEXT, name TEXT, buyingPrice REAL, sellingPrice REAL, timeStamp INTEGER PRIMARY KEY)",
        );
      },
      version: 1,
    );
    loaded = setTransactionRecordsFromDB();

  }

  Future<List<TransactionRecord>> dbTransactionRecords() async {
    final Database db = await database;

    final List<Map<String, dynamic>> maps = await db.query('transactionRecords');
    return List.generate(maps.length, (i) {
      var transaction = TransactionRecord(
        maps[i]['barCode'],
        maps[i]['name'],
        maps[i]['sellingPrice'],
        maps[i]['buyingPrice'],
        DateTime.fromMillisecondsSinceEpoch(maps[i]['timeStamp'])
      );
      return transaction;
    });
  }

  Future<bool> setTransactionRecordsFromDB() async {
    transactionRecords = await dbTransactionRecords();
    refresh();
    return true;
  }

  Future<void> insertTransactionRecordInDB(TransactionRecord transactionRecord) async {
    insertMapInDB(transactionRecord.toMap());
  }

  Future<void> insertMapInDB(Map map) async {
    final Database db = await database;
    await db.insert(
      'transactionRecords',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }


  void saveAllItemsToDB() {
    transactionRecords.map((transactionRecord) => insertTransactionRecordInDB(transactionRecord));
  }

  Future<void> deleteItemFromDB(TransactionRecord transactionRecord) async {
    // Get a reference to the database.
    final db = await database;

    await db.delete(
      'transactionRecords',
      where: "time = ?",
      whereArgs: [transactionRecord.time.millisecondsSinceEpoch],
    );
  }
  
}

class TransactionRecord{
  String barCode;
  String name;
  double sellingPrice;
  double buyingPrice;
  DateTime time;
  TransactionRecord(this.barCode, this.name,this.sellingPrice, this.buyingPrice, this.time);

  TransactionRecord.fromItem(Item item, this.time){
    this.barCode = item.barCode;
    this.name = item.name;
    this.sellingPrice = item.sellingPrice;
    this.buyingPrice = item.buyingPrice;
  }


  toMap(){
    return {'barCode':barCode,'name':name,'sellingPrice':sellingPrice,'buyingPrice':buyingPrice,'timeStamp':time.millisecondsSinceEpoch};
  }
}