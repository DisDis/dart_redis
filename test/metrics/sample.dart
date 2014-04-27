part of metrics;
class Sample {
  BinaryHeap values;
  int count;
  Sample() {
    this.values = null;
    this.count = 0;
  }

  init() {
    this.clear();
  }
  update(val) {
    this.values.push(val);
  }
  clear() {
    //this.values = [];
    this.count = 0;
  }
  size() {
    return this.values.size();
  }
  printConsole() {
    print("$values");
  }
  getValues() {
    return this.values;
  }
}
