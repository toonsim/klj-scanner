class Item{
  final String barCode;
  String name;
  int count = 0;
  double buyingPrice = 0.0;
  double sellingPrice = 0.0;

  Item(this.barCode, this.name);



  
  void increment(){
    count += 1;
  }
  
  void decrement(){
    count -= 1;
  }

  int get hashCode => this.barCode.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is Item) return barCode == other.barCode;
    else return false;
  }

  void incrementBy(int number) {
    count += number;
  }

  Map<String, dynamic> toMap(){
    return {'barCode':barCode, 'name':name,'count':count,'buyingPrice':buyingPrice,'sellingPrice':sellingPrice};
  }
}