import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_porter/utils/csv_utils.dart';


import 'item.dart';

class Stock {
  Function refresh;
  List<Item> items;
  Future<Database> database;
  Future<bool> loaded;
  Future<bool> pathLoaded;
  Map<Item,ImageProvider>  itemImages = Map();
  String _path;
  Stock(this.refresh) {
    pathLoaded = initPath();
    loadDatabase();
  }

  Future<bool> initPath() async {
    _path = (await getApplicationDocumentsDirectory()).path;
    return true;
  }

  Future<String> toCSV() async{
    await loaded;
    var result = await (await database).query('items');
    return mapListToCsv(result);
  }

  importFromCSV(filePath) async {
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
    setItemsFromDB();
    refresh();
  }

  void increment(String barCode) {
    var item = items.firstWhere((stockItem) => stockItem.barCode == barCode);
    item.increment();
    insertItemInDB(item);
  }

  void decrement(String barCode) {
    var item = items.firstWhere((stockItem) => stockItem.barCode == barCode);
    item.decrement();
    insertItemInDB(item);
  }

  void addNewItem(Item item) {
    items.add(item);
    insertItemInDB(item);
  }

  void incrementBy(String barCode, int number) {
    var item = items.firstWhere((stockItem) => stockItem.barCode == barCode);
    item.incrementBy(number);
    insertItemInDB(item);
  }

  String getName(barCode) {
    return items.firstWhere((item) => item.barCode == barCode).name;
  }

  bool hasName(String name) {
    return items.any((item) => item.name == name);
  }

  bool hasBarCode(String barCode) {
    return items.any((item) => item.barCode == barCode);
  }
  
  Item getItem(String barCode){
    return items.firstWhere((item) => item.barCode==barCode);
  }

  Future<void> loadDatabase() async {
    database = openDatabase(
      join(await getDatabasesPath(), 'items_database.db'),

      onCreate: (db, version) {
        return db.execute(
          "CREATE TABLE items(barCode TEXT PRIMARY KEY, name TEXT, count INTEGER, buyingPrice REAL, sellingPrice REAL)",
        );
      },
      version: 1,
    );
    loaded = setItemsFromDB();

  }

  Future<List<Item>> dbItems() async {
    final Database db = await database;

    final List<Map<String, dynamic>> maps = await db.query('items');
    return List.generate(maps.length, (i) {
      var item = Item(
        maps[i]['barCode'],
        maps[i]['name'],
      );
      item.count = maps[i]['count'];
      item.buyingPrice = maps[i]['buyingPrice'];
      item.sellingPrice = maps[i]['sellingPrice'];
      return item;
    });
  }

  
  
  Future<bool> setItemsFromDB() async {
    items = await dbItems();
    print('ITEMS: $items');
    setItemImages();
    refresh();
    return true;
  }

  Future<void> insertItemInDB(Item item) async {
    insertMapInDB(item.toMap());
  }

  Future<void> insertMapInDB(Map map) async {
    final Database db = await database;
    await db.insert(
      'items',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void saveAllItemsToDB() {
    items.map((item) => insertItemInDB(item));
  }

  void removeItem(Item item) {
    items.remove(item);
    deleteItemFromDB(item);
  }

  Future<void> deleteItemFromDB(Item item) async {
    // Get a reference to the database.
    final db = await database;

    await db.delete(
      'items',
      where: "barCode = ?",
      whereArgs: [item.barCode],
    );
  }

  String imageFilePath(Item item) {
    return '$_path/${item.barCode}.png';
  }
  
  Future<bool> _hasImage(Item item){
    return File(imageFilePath(item)).exists();
  }

  bool hasImage(Item item){
    return itemImages.containsKey(item);
  }
  
  void setItemImages() async{
    await pathLoaded;
    for (var item in items){
      if (await _hasImage(item)){
        itemImages[item] = FileImage(File(imageFilePath(item)));
      }
    }
  }
  
  
}
