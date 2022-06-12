import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audio_cache.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:barcode_scan/barcode_scan.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:date_range_picker/date_range_picker.dart' as DateRagePicker;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:kljscanner/transactions.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share/share.dart';

import 'item.dart';
import 'stock.dart';

bool isInt(String s) {
  try {
    int.parse(s);
    return true;
  } catch (e) {
    return false;
  }
}

bool isDouble(String s) {
  try {
    double.parse(s);
    return true;
  } catch (e) {
    return false;
  }
}

void main() async {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KLJ Stock Scanner',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.red,
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'KLJ Stock Scanner'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Stock _stock;
  TransactionLedger _transactionLedger;
  String _barCodeToAdd = "";
  Item itemToEdit;
  TransactionAnalyser _transactionAnalyser;
  bool meeting = false;
  String _path;
  Future<bool> _pathLoaded;

  final _formKey = GlobalKey<FormState>();

  DateTime _dateStart = DateTime.fromMicrosecondsSinceEpoch(0);
  DateTime _dateEnd = DateTime.now().add(Duration(days: 1));

  TransactionRecord _transactionToDelete;

  final _imagePicker = ImagePicker();

  Future<AudioPlayer> _playLocalAsset() async {
    AudioCache cache = new AudioCache();
    return await cache.play("beep.mp3");
  }

  @override
  void initState() {
    _stock = Stock(refresh);
    _transactionLedger = TransactionLedger(refresh);
    _pathLoaded = initPath();

    super.initState();
  }

  String _stockCsvFilePath;
  String _transactionsFilePath;

  writeStockAndTransactionsToCSV() async {
    await _pathLoaded;
    _stockCsvFilePath = '$_path/stock.csv';
    _transactionsFilePath = '$_path/transactions.csv';
    var stockFile = File(_stockCsvFilePath);
    var stockCSV = await _stock.toCSV();
    var transactionsFile = File(_transactionsFilePath);
    var transactionsCSV = await _transactionLedger.toCSV();
    stockFile.writeAsString(stockCSV);
    transactionsFile.writeAsString(transactionsCSV);
  }

  _onShare(BuildContext context) async {
    await writeStockAndTransactionsToCSV();
    // A builder is used to retrieve the context immediately
    // surrounding the RaisedButton.
    //
    // The context's `findRenderObject` returns the first
    // RenderObject in its descendent tree when it's not
    // a RenderObjectWidget. The RaisedButton's RenderObject
    // has its position and size after it's built.
    final RenderBox box = context.findRenderObject();
    await Share.shareFiles([_stockCsvFilePath, _transactionsFilePath],
        text: "Stock",
        subject: "stocks",
        sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size);
  }

  void _scanToAdd() async {
    var result = await _getScan();
    if (result.type == ResultType.Barcode) {
      var barcode = result.rawContent;
      setState(() {
        _barCodeToAdd = barcode;
      });
    }
  }

  void _scanToRemove() async {
    var result = await _getScan();
    if (result.type == ResultType.Barcode) {
      var barcode = result.rawContent;
      if (_stock.hasBarCode(barcode)) {
        setState(() {
          _stock.decrement(barcode);
          if (!meeting) {
            _transactionLedger.addNewTransaction(
                TransactionRecord.fromItem(_stock.getItem(barcode), DateTime.now()));
          } else {
            var item = _stock.getItem(barcode);
            _transactionLedger.addNewTransaction(
                TransactionRecord(item.barCode, item.name, 0, item.buyingPrice, DateTime.now()));
          }
        });
        _scanToRemove();
      } else {
        setState(() {
          _barCodeToAdd = barcode;
        });
      }
    }
  }

  Future<ScanResult> _getScan() async {
    var result = await BarcodeScanner.scan(
      options: ScanOptions(
        useCamera: 0,
        // android: AndroidOptions(
        //   aspectTolerance: 100,
        //   useAutoFocus: true,
        // ),
      ),
    );
    if (result.type == ResultType.Barcode) _playLocalAsset();
    return result;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void refresh() {
    setState(() {});
  }

  bool somethingNeedsToChange() {
    return _barCodeToAdd != '' || itemToEdit != null || _transactionToDelete != null;
  }

  void importStockAndTransactions() async {
    FilePickerResult result1 = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    FilePickerResult result2 = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result1 != null && result2 != null) {
      final paths = result1.paths..addAll(result2.paths);
      var stockPath = paths.firstWhere((element) => element.endsWith('stock.csv'));
      var transactionsPath = paths.firstWhere((element) => element.endsWith('transactions.csv'));
      _stock.importFromCSV(stockPath);
      _transactionLedger.importFromCSV(transactionsPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    _transactionAnalyser = TransactionAnalyser.fromLedger(_transactionLedger, _dateStart, _dateEnd);

    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return FutureBuilder<bool>(
        future: _stock.loaded,
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (snapshot.hasData)
            return _app(context);
          else {
            return Container(
              color: Colors.white,
              child: Center(
                child: Image(image: AssetImage('assets/icon.png')),
              ),
            );
          }
        });
  }

  String formatDate(DateTime date) {
    return DateFormat("dd/MM/yyyy").format(date);
  }

  Widget _analyticsView(context) {
    return ListView(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text('Periode:'),
                  RaisedButton(
                      onPressed: () async {
                        final List<DateTime> picked = await DateRagePicker.showDatePicker(
                          context: context,
                          initialFirstDate: _dateStart,
                          initialLastDate: _dateEnd,
                          firstDate: DateTime.fromMicrosecondsSinceEpoch(0),
                          lastDate: DateTime.now().add(Duration(days: 1)),
                        );
                        if (picked != null && picked.length == 2) {
                          setState(() {
                            _dateStart = picked[0];
                            _dateEnd = picked[1];
                          });
                        }
                      },
                      child: Text(
                          '${_dateStart.isAtSameMomentAs(DateTime.fromMicrosecondsSinceEpoch(0)) ? '' : formatDate(_dateStart)} - ${formatDate(_dateEnd)}')),
                ],
              ),
              Divider(),
              _barChartTitle('Winst: totaal €${_transactionAnalyser.totalProfit.toStringAsFixed(2)}'),
              _barChart(_transactionAnalyser.getItemProfitSeries()),
              Divider(),
              _barChartTitle('Aantal verkocht'),
              _barChart(_transactionAnalyser.getItemCountSeries()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _barChartTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            )),
      );

  Widget _barChart(series) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Container(
          width: double.infinity,
          height: 200.0,
          child: charts.BarChart(
            series,
            vertical: false,
            barRendererDecorator: charts.BarLabelDecorator<String>(),

            //domainAxis: new charts.OrdinalAxisSpec(renderSpec: new charts.NoneRenderSpec()),
          )),
    );
  }
  
  Widget _transactionLogView(context) {
    return ListView.separated(
        controller: ScrollController(
            initialScrollOffset: (_transactionLedger.transactionRecords.length * 70.0)),
        separatorBuilder: (context, index) => Divider(
              indent: 80,
              color: Colors.grey,
            ),
        itemCount: _transactionLedger.transactionRecords.length,
        itemBuilder: (context, index) {
          final transaction = _transactionLedger.transactionRecords[index];

          return ListTile(
            title: Row(
              children: [
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      children: [
                        Text(DateFormat('dd-MM-yyyy').format(transaction.time)),
                        Text(DateFormat('HH:mm:ss').format(transaction.time)),
                      ],
                    )),
                priceRowTransaction(transaction.buyingPrice, transaction.sellingPrice),
                Text(transaction.name),
              ],
            ),
            onLongPress: () => showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text('Transactie verwijderen?'),
                  actions: [
                    FlatButton(
                        child: Text("Annuleren"),
                        onPressed: () {
                          Navigator.of(context).pop();
                        }),
                    FlatButton(
                        child: Text("Bevestigen"),
                        onPressed: () {
                          setState(() => _transactionLedger.removeTransaction(transaction));
                          Navigator.of(context).pop();
                        })
                  ],
                );
              },
            ),
            leading: _stock.hasBarCode(transaction.barCode)
                ? listItemImage(_stock.getItem(transaction.barCode), height: 50)
                : defaultItemImage,
          );
        });
  }

  Widget _inventoryView() {
    if (itemToEdit != null) return _editItemForm();
    if (_barCodeToAdd != '') return _newItemForm();
    if (_transactionToDelete != null) return _passwordForm();
    return _stockItemList();
  }

  FutureBuilder<Widget> _imageInput() {
    return FutureBuilder(
      future: _imageInputFuture(),
      builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
        if (snapshot.hasData) {
          return snapshot.data;
        } else if (snapshot.hasError)
          return Container(child: Text(snapshot.error.toString()));
        else
          return Container(height: 140);
      },
    );
  }

  Key _imageKey = UniqueKey();
  String tempFilePath = "";

  Future<Widget> _imageInputFuture() async {
    var imageFilePath;

    if (_barCodeToAdd != "") {
      imageFilePath = '$_path/$_barCodeToAdd.png';
    } else if (itemToEdit != null) {
      imageFilePath = '$_path/${itemToEdit.barCode}.png';
    }

    return GestureDetector(
      key: _imageKey,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: tempImage != null
              ? headerImage(tempImage)
              : Container(
                  child: Icon(Icons.add_a_photo),
                  width: 100,
                  height: 100,
                ),
        ),
      ),
      onLongPress: () {
        setState(() {
          tempImage = null;
        });
      },
      onTap: () async {
        var imageSource;
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Selecteer afbeelding of maak er een nieuwe'),
              actions: [
                IconButton(
                    icon: Icon(Icons.photo),
                    onPressed: () async {
                      imageSource = ImageSource.gallery;
                      Navigator.of(context).pop();
                    }),
                IconButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    imageSource = ImageSource.camera;
                  },
                  icon: Icon(Icons.photo_camera),
                ),
              ],
            );
          },
        );
        var pickedFile =
            (await _imagePicker.getImage(source: imageSource, maxHeight: 480, maxWidth: 640));
        if (pickedFile != null) {
          print('FILE FOUND: $imageFilePath');
          setState(() {
            tempFilePath = pickedFile.path;
            tempImage = MemoryImage(Uint8List.fromList(File(pickedFile.path).readAsBytesSync()));
          });
        }
      },
    );
  }

  Future<Widget> listItemImageFuture(Item item, {double height: 100.0}) async {
    await _pathLoaded;

    return _stock.hasImage(item)
        ? itemImage(_stock.itemImages[item], height: height)
        : defaultItemImage;
  }

  FutureBuilder<Widget> listItemImage(Item item, {double height: 100.0}) {
    return FutureBuilder(
        future: listItemImageFuture(item, height: height),
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.hasData) {
            return snapshot.data;
          } else if (snapshot.hasError) {
            return Text(snapshot.error.toString());
          } else {
            return Container(
              height: 50,
              width: 50,
            );
          }
        });
  }

  headerImage(ImageProvider image) {
    return Container(
      height: 200,
      width: double.infinity,
      child: FittedBox(
        child: Image(image: image),
        fit: BoxFit.cover,
      ),
    );
  }

  Container itemImage(ImageProvider image, {double height: 100.0}) {
    return Container(
      width: height,
      height: height,
      decoration: BoxDecoration(
        image: DecorationImage(
          fit: BoxFit.cover,
          alignment: FractionalOffset.center,
          image: image,
        ),
      ),
    );
  }

  final defaultItemImage = Container(
    width: 50.0,
    height: 50.0,
  );

  ImageProvider tempImage;

  Widget _editItemForm() {
    return SingleChildScrollView(
      child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _imageInput(),
              _productNameTextField(itemToEdit.name),
              _productCountTextField(itemToEdit.count),
              _productBuyingPriceTextField(itemToEdit.buyingPrice),
              _productSellingPriceTextField(itemToEdit.sellingPrice),
              _cancelOrSubmit(
                () {
                  setState(() {
                    itemToEdit = null;
                  });
                },
                () {
                  // Validate returns true if the form is valid, or false
                  // otherwise.
                  if (_formKey.currentState.validate()) {
                    if (tempImage == null) {
                      File('$_path/${itemToEdit.barCode}.png').delete();
                      setState(() {
                        _stock.itemImages.remove(itemToEdit);
                      });
                    } else if (tempFilePath != "") {
                      print("TEMPFILE != \"\"???");
                      File(tempFilePath).copy('$_path/${itemToEdit.barCode}.png');
                      _stock.itemImages[itemToEdit] =
                          MemoryImage(Uint8List.fromList(File(tempFilePath).readAsBytesSync()));
                    }
                    _formKey.currentState.save();
                    tempImage = null;
                    tempFilePath = "";
                    itemToEdit = null;
                    setState(() {});
                  }
                },
              )
            ],
          )),
    );
  }

  Widget _passwordForm() {
    return Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _passwordTextField(),
            _cancelOrSubmit(() {
              setState(() {
                _transactionToDelete = null;
              });
            }, () {
              if (_formKey.currentState.validate()) {
                _formKey.currentState.save();
                _transactionToDelete = null;
              }
            }),
          ],
        ));
  }

  SingleChildScrollView _newItemForm() {
    return SingleChildScrollView(
      child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _imageInput(),
              !_stock.hasBarCode(_barCodeToAdd)
                  ? _productNameTextField('')
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                          child: Text(_stock.getItem(_barCodeToAdd).name,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                    ),
              _productCountTextField(null),
              !_stock.hasBarCode(_barCodeToAdd) ? _productBuyingPriceTextField(null) : Container(),
              !_stock.hasBarCode(_barCodeToAdd) ? _productSellingPriceTextField(null) : Container(),
              _cancelOrSubmit(() {
                setState(() {
                  _barCodeToAdd = "";
                });
              }, () {
                if (_formKey.currentState.validate()) {
                  _formKey.currentState.save();
                  if (tempFilePath != ""){
                  File(tempFilePath).copy('$_path/$_barCodeToAdd.png');
                  _stock.itemImages[_stock.getItem(_barCodeToAdd)] =
                      MemoryImage(Uint8List.fromList(File(tempFilePath).readAsBytesSync()));}
                  tempImage = null;
                  tempFilePath = "";
                  _barCodeToAdd = "";
                  setState(() {});
                }

              }),
            ],
          )),
    );
  }

  Row _cancelOrSubmit(onCancel, onSubmit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 10),
          child: RaisedButton(
            onPressed: onCancel,
            child: Text('Annuleren'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 10),
          child: RaisedButton(
            onPressed: onSubmit,
            child: Text('Bevestigen'),
          ),
        ),
      ],
    );
  }

  Widget _stockItemList() {
    return ListView.separated(
      separatorBuilder: (context, index) => index != 0
          ? Divider(
              indent: 80,
              height: 0,
              color: Colors.grey,
            )
          : Divider(
              height: 1,
              thickness: 1,
              color: Colors.black,
            ),
      itemCount: _stock.items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // return the header
          return SwitchListTile(
            title: Text('Momenteel alles gratis'),
            secondary: const Icon(Icons.money_off),
            onChanged: (value) => setState(() => meeting = value),
            value: meeting,
          );
        }
        index -= 1;
        final item = _stock.items[index];

        return Container(
          child: Dismissible(
            key: Key(item.barCode),
            onDismissed: (direction) {
              setState(() {
                _stock.removeItem(item);
              });
              Scaffold.of(context).showSnackBar(SnackBar(
                content: Text("${item.name} verwijderd"),
                action: SnackBarAction(
                  label: 'Ongedaan maken',
                  onPressed: () => setState(() => _stock.addNewItem(item)),
                ),
              ));
            },
            background: Container(color: Colors.redAccent),
            child: ListTile(
              leading: listItemImage(item, height: 50),
              title: Text(item.name),
              trailing: Text('${item.count}'),
              subtitle: priceRow(item.buyingPrice, item.sellingPrice),
              onLongPress: () {
                setState(() {
                  itemToEdit = item;
                  tempImage = _stock.itemImages[item];
                });
              },
            ),
          ),
        );
      },
    );
  }

  TextFormField _productSellingPriceTextField(double sellingPrice) {
    return TextFormField(
        initialValue: sellingPrice != null ? sellingPrice.toString() : '',
        decoration: const InputDecoration(
          icon: Icon(
            Icons.account_balance_wallet,
            color: Colors.green,
          ),
          hintText: 'Wat is de verkoopprijs van het product?',
          labelText: 'Verkoopprijs in €',
        ),
        validator: (value) {
          if (value.isEmpty) {
            return 'Voeg een prijs in';
          } else if (!isDouble(value)) {
            return 'Voeg een getal in, bv: 1.5';
          }
          return null;
        },
        onSaved: (String value) {
          setState(() {
            if (itemToEdit != null) {
              itemToEdit.sellingPrice = double.parse(value);
              _stock.insertItemInDB(itemToEdit);
            } else
              _stock.getItem(_barCodeToAdd).sellingPrice = double.parse(value);
          });
        });
  }

  TextFormField _productBuyingPriceTextField(double buyingPrice) {
    return TextFormField(
        initialValue: buyingPrice != null ? buyingPrice.toString() : '',
        decoration: const InputDecoration(
          icon: Icon(
            Icons.account_balance_wallet,
            color: Colors.redAccent,
          ),
          hintText: 'Wat is de inkoopprijs van het product?',
          labelText: 'Inkoopprijs in €',
        ),
        validator: (value) {
          if (value.isEmpty) {
            return 'Voeg een prijs in';
          } else if (!isDouble(value)) {
            return 'Voeg een getal in, bv: 1.5';
          }
          return null;
        },
        onSaved: (String value) {
          setState(() {
            if (itemToEdit != null) {
              itemToEdit.buyingPrice = double.parse(value);
              _stock.insertItemInDB(itemToEdit);
            } else
              _stock.getItem(_barCodeToAdd).buyingPrice = double.parse(value);
          });
        });
  }

  TextFormField _productCountTextField(int count) {
    return TextFormField(
        initialValue: count != null ? '$count' : '',
        decoration: const InputDecoration(
          icon: Icon(Icons.archive),
          hintText: 'Hoeveel producten wil je toevoegen?',
          labelText: '# producten',
        ),
        validator: (value) {
          if (value.isEmpty) {
            return 'Voeg een aantal in';
          } else if (!isInt(value)) {
            return 'Voeg een getal in';
          }
          return null;
        },
        onSaved: (String value) {
          setState(() {
            if (itemToEdit != null) {
              itemToEdit.count = int.parse(value);
              _stock.insertItemInDB(itemToEdit);
            } else if (_barCodeToAdd != '') {
              _stock.incrementBy(_barCodeToAdd, int.parse(value));
            }
          });
        });
  }

  TextFormField _productNameTextField(String productName) {
    return TextFormField(
        initialValue: productName,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          icon: Icon(Icons.label),
          hintText: 'Wat is de naam van het product?',
          labelText: 'Productnaam',
        ),
        validator: (value) {
          if (value.isEmpty) {
            return 'Voeg een naam in';
          } else if (_stock.hasName(value) && itemToEdit == null) {
            return 'Naam bestaat al';
          }
          return null;
        },
        onSaved: (String value) {
          setState(() {
            if (itemToEdit != null) {
              itemToEdit.name = value;
              _stock.insertItemInDB(itemToEdit);
            } else if (_barCodeToAdd != '') {
              _stock.addNewItem(Item(_barCodeToAdd, value));
            }
          });
        });
  }

  TextFormField _passwordTextField() {
    return TextFormField(
        textCapitalization: TextCapitalization.sentences,
        obscureText: true,
        decoration: const InputDecoration(
          icon: Icon(Icons.label),
          hintText: 'Voeg het wachtwoord in',
          labelText: 'Wachtwoord',
        ),
        validator: (value) {
          if (value != "Maarten heeft een kleine piemel") {
            return 'Voeg het juiste wachtwoord in';
          }
          return null;
        },
        onSaved: (String value) {
          setState(() {
            _transactionLedger.removeTransaction(_transactionToDelete);
          });
        });
  }

  Row priceRow(double buyingPrice, double sellingPrice) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            '€ ${buyingPrice.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
        Text(
          '€ ${sellingPrice.toStringAsFixed(2)}',
          style: TextStyle(color: Colors.green),
        ),
      ],
    );
  }

  final _tabs = <Tab>[
    Tab(icon: Icon(Icons.inbox), text: 'Stock'),
    Tab(icon: Icon(Icons.show_chart), text: 'Analyse'),
    Tab(icon: Icon(Icons.assignment), text: 'Transacties'),
  ];

  Widget _app(context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: Text(widget.title),
          bottom: !somethingNeedsToChange() ? TabBar(tabs: _tabs) : null,
        ),
        body: !somethingNeedsToChange()
            ? TabBarView(
                children: [_inventoryView(), _analyticsView(context), _transactionLogView(context)])
            : _inventoryView(),
        floatingActionButton: _speedDial(context),
        // FloatingActionButton(
        //   onPressed: _scanToRemove,
        //   child: Padding(
        //     padding: const EdgeInsets.only(top:10),
        //     child: SvgPicture.asset('assets/barcodeScanner.svg'),
        //   ),
        // ),
      ),
    );
  }

  SpeedDial _speedDial(context) {
    return SpeedDial(
      // both default to 16
      marginRight: 18,
      marginBottom: 20,
      animatedIcon: AnimatedIcons.menu_close,
      animatedIconTheme: IconThemeData(size: 22.0),
      // this is ignored if animatedIcon is non null
      // child: Icon(Icons.add),
      visible: true,
      // If true user is forced to close dial manually
      // by tapping main button and overlay is not rendered.
      closeManually: false,
      curve: Curves.bounceIn,
      overlayColor: Colors.black,
      overlayOpacity: 0.5,
      onOpen: () => print('OPENING DIAL'),
      onClose: () => print('DIAL CLOSED'),
      tooltip: 'Speed Dial',
      heroTag: 'speed-dial-hero-tag',
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 8.0,
      shape: CircleBorder(),
      children: [
        SpeedDialChild(
            child: Icon(Icons.remove_circle),
            backgroundColor: Colors.red,
            label: 'Scan om te verwijderen',
            labelStyle: TextStyle(fontSize: 18.0),
            onTap: _scanToRemove),
        SpeedDialChild(
          child: Icon(Icons.add_circle),
          backgroundColor: Colors.green,
          label: 'Scan om toe te voegen',
          labelStyle: TextStyle(fontSize: 18.0),
          onTap: _scanToAdd,
        ),
        SpeedDialChild(
          child: Icon(Icons.file_upload),
          backgroundColor: Colors.grey,
          label: 'Exporteren',
          labelStyle: TextStyle(fontSize: 18.0),
          onTap: () => _onShare(context),
        ),
        SpeedDialChild(
          child: Icon(Icons.file_download),
          backgroundColor: Colors.grey,
          label: 'Importeren',
          labelStyle: TextStyle(fontSize: 18.0),
          onTap: importStockAndTransactions,
        ),
      ],
    );
  }

  priceRowTransaction(double buyingPrice, double sellingPrice) {
    var profit = sellingPrice - buyingPrice;
    var color = profit > 0 ? Colors.green : Colors.redAccent;
    return Container(
      width: 100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(buyingPrice.toStringAsFixed(2)),
          Text(
            profit.toStringAsFixed(2),
            style: TextStyle(color: color),
          )
        ],
      ),
    );
  }

  Future<bool> initPath() async {
    _path = (await getApplicationDocumentsDirectory()).path;
    return true;
  }
}

class ItemDataRecord {
  String name;
  double profit;
  int total;

  ItemDataRecord(this.name, this.total, this.profit);
}

class TransactionAnalyser {
  List<ItemDataRecord> itemData = [];
  DateTime _dateStart;
  DateTime _dateEnd;

  TransactionAnalyser.fromLedger(TransactionLedger ledger, this._dateStart, this._dateEnd) {
    setItemData(ledger);
  }

  void setItemData(TransactionLedger ledger) {
    var map = Map();
    var transactions = ledger.transactionRecords.where((transaction) =>
        transaction.time.isBefore(_dateEnd) && transaction.time.isAfter(_dateStart));
    transactions.forEach((transaction) {
      var barCode = transaction.barCode;
      if (!map.containsKey(barCode)) {
        map[barCode] = [1, transaction.sellingPrice - transaction.buyingPrice];
      } else {
        map[barCode][0] += 1;
        map[barCode][1] += transaction.sellingPrice - transaction.buyingPrice;
      }
    });

    map.forEach((barCode, value) {
      var itemName = transactions.lastWhere((transaction) => transaction.barCode == barCode).name;
      itemData.add(ItemDataRecord(itemName, value[0], value[1]));
    });
  }

  double get totalProfit {
    return itemData.length == 0 ? 0.0 : itemData.map((e) => e.profit).reduce((value, element) => value+element);
  }

  getItemProfitSeries() {
    itemData.sort((a, b) => b.profit.compareTo(a.profit));
    List<ItemDataRecord> profitData = List.from(itemData);
    return [
      charts.Series<ItemDataRecord, String>(
        id: 'Profits',
        colorFn: (ItemDataRecord record, __) => record.profit >= 0
            ? charts.MaterialPalette.green.shadeDefault
            : charts.MaterialPalette.red.shadeDefault,
        domainFn: (ItemDataRecord record, _) => record.name,
        measureFn: (ItemDataRecord record, _) => record.profit.abs(),
        data: profitData,
        labelAccessorFn: (ItemDataRecord record, _) => '€${record.profit.toStringAsFixed(2)}',
      )
    ];
  }

  getItemCountSeries() {
    itemData.sort((a, b) => b.total.compareTo(a.total));
    List<ItemDataRecord> countData = List.from(itemData);
    return [
      charts.Series<ItemDataRecord, String>(
        id: 'ItemCounts',
        colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
        domainFn: (ItemDataRecord record, _) => record.name,
        measureFn: (ItemDataRecord record, _) => record.total,
        data: countData,
        labelAccessorFn: (ItemDataRecord record, _) => '${record.total}',
      )
    ];
  }
}
