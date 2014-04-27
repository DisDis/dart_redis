part of metrics;
/*var Sample = require('./sample')
  , BinaryHeap = require('../lib/binary_heap')
  , util = require('util')
  , utils = require('../lib/utils');*/



/* This acts as a ordered binary heap for any serializeable JS object or collection of such objects */
class BinaryHeap<T>{
  List<T> content;
  Function scoreFunction;
 BinaryHeap(scoreFunction(T obj)){
  this.content = [];
  this.scoreFunction = scoreFunction;
}


 BinaryHeap clone() {
    var heap = new BinaryHeap<EDSItem>(this.scoreFunction);
    // A little hacky, but effective.
    heap.content = new List.from(content);// JSON.parse(JSON.stringify(this.content));
    return heap;
  }

  push(element) {
    // Add the new element to the end of the array.
    this.content.add(element);
    // Allow it to bubble up.
    this.bubbleUp(this.content.length - 1);
  }

  T peek() {
    return this.content[0];
  }

  T pop() {
    if (this.content.length==0){
      return null;
    }
    // Store the first element so we can return it later.
    var result = this.content[0];
    // Get the element at the end of the array.
    var end = this.content.removeLast();//pop();
    // If there are any elements left, put the end element at the
    // start, and let it sink down.
    if (this.content.length > 0) {
      this.content[0] = end;
      this.sinkDown(0);
    }
    return result;
  }

  remove(node) {
    var len = this.content.length;
    // To remove a value, we must search through the array to find
    // it.
    for (var i = 0; i < len; i++) {
      if (this.content[i] == node) {
        // When it is found, the process seen in 'pop' is repeated
        // to fill up the hole.
        var end = this.content.removeLast();//.pop();
        if (i != len - 1) {
          this.content[i] = end;
          if (this.scoreFunction(end) < this.scoreFunction(node))
            this.bubbleUp(i);
          else
            this.sinkDown(i);
        }
        return true;
      }
    }
    throw new Exception("Node not found.");
  }
  
  size() {
    return this.content.length;
  }

  bubbleUp(n) {
    // Fetch the element that has to be moved.
    var element = this.content[n];
    // When at 0, an element can not go up any further.
    while (n > 0) {
      // Compute the parent element's index, and fetch it.
      var parentN = /*Math.floor*/((n + 1) / 2).floor() - 1,
          parent = this.content[parentN];
      // Swap the elements if the parent is greater.
      if (this.scoreFunction(element) < this.scoreFunction(parent)) {
        this.content[parentN] = element;
        this.content[n] = parent;
        // Update 'n' to continue at the new position.
        n = parentN;
      }
      // Found a parent that is less, no need to move it further.
      else {
        break;
      }
    }
  }

  sinkDown(n) {
    // Look up the target element and its score.
    var length = this.content.length;
    T  element = this.content[n];
    var elemScore = this.scoreFunction(element);

    var child1Score;
    while(true) {
      // Compute the indices of the child elements.
      var child2N = (n + 1) * 2, child1N = child2N - 1;
      // This is used to store the new position of the element,
      // if any.
      var swap = null;
      // If the first child exists (is inside the array)...
      if (child1N < length) {
        // Look it up and compute its score.
        var child1 = this.content[child1N];
        child1Score = this.scoreFunction(child1);
        // If the score is less than our element's, we need to swap.
        if (child1Score < elemScore)
          swap = child1N;
      }
      // Do the same checks for the other child.
      if (child2N < length) {
        var child2 = this.content[child2N],
            child2Score = this.scoreFunction(child2);
        if (child2Score < (swap == null ? elemScore : child1Score))
          swap = child2N;
      }

      // If the element needs to be moved, swap it, and continue.
      if (swap != null) {
        this.content[n] = this.content[swap];
        this.content[swap] = element;
        n = swap;
      }
      // Otherwise, we are done.
      else {
        break;
      }
    }
  }
}

/*
 *  Take an exponentially decaying sample of size size of all values
 */
var RESCALE_THRESHOLD = 60 * 60 * 1000; // 1 hour in milliseconds

class ExponentiallyDecayingSample extends Sample{
  int limit;
  double alpha;
  int startTime;
  int nextScaleTime;
  ExponentiallyDecayingSample(int size,double alpha):super() {
  this.limit = size;
  this.alpha = alpha;
  this.clear();
}

// This is a relatively expensive operation
List<EDSItem> getValues() {
  var values = [];
  var heap = this.values.clone();
  var elt;
  while((elt = heap.pop())!=null) {
    values.add(elt.val);
  }
  return values;
}

size() {
  return this.values.size();
}

newHeap() {
  return new BinaryHeap<EDSItem>((obj){
    return obj.priority;
    });
}

int now() {
  return /*(new Date()).getTime()*/ new DateTime.now().millisecondsSinceEpoch;
}

int tick() {
  return (this.now() ~/ 1000);
}

clear() {
  this.values = this.newHeap();
  this.count = 0;
  this.startTime = this.tick();
  this.nextScaleTime = this.now() + RESCALE_THRESHOLD;
}

Math.Random _rnd = new Math.Random();
/*
* timestamp in milliseconds
*/
update(val, [timestamp]) {
  // Convert timestamp to seconds
  if (timestamp == null) {
    timestamp = this.tick();
  } else {
    timestamp = timestamp / 1000;
  }
  
  var priority = this.weight(timestamp - this.startTime) / _rnd.nextDouble()/* Math.random()*/;
  var value = new EDSItem(val: val, priority: priority);
  if (this.count < this.limit) {
    this.count += 1;
    this.values.push(value);
  } else {
    var first = this.values.peek();
    if (first.priority < priority) {
      this.values.push(value);
      this.values.pop();
    }
  }

  if (this.now() > this.nextScaleTime) {
    this.rescale(this.now(), this.nextScaleTime);
  }
}

weight(time) {
  return Math.exp(this.alpha * time);
}

// now: parameter primarily used for testing rescales
rescale(now,[_]) {
  this.nextScaleTime = this.now() + RESCALE_THRESHOLD;
  var oldContent = this.values.content
    , newContent = []
    , elt
    , oldStartTime = this.startTime;
  var tmp = now && now / 1000;
  this.startTime = (now==null || now==0)?this.tick():now;
  // Downscale every priority by the same factor. Order is unaffected, which is why we're avoiding the cost of popping.
  for(var i = 0; i < oldContent.length; i++) {
    newContent.add(new EDSItem(val: oldContent[i].val, priority: oldContent[i].priority * Math.exp(-this.alpha * (this.startTime - oldStartTime))));
  }
  this.values.content = newContent;
}
}

class EDSItem{
  var val;
  double priority;
  EDSItem({this.val,this.priority});
}