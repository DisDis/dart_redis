import "../lib/dart_redis.dart" as redis;
import 'dart:io';
import 'dart:convert';
import "../lib/js_convert.dart" as js;
import "metrics/metrics.dart" as metrics;

//var    metrics = require("metrics");
int num_clients;
int num_requests = 20000;
List<Test> tests = [];
var versions_logged = false;
redis.RedisClientOptions client_options = new redis.RedisClientOptions(return_buffers: false);
String small_str, large_str;
List<int> small_buf;
List<int> large_buf;

List<int> stringToBuffer(String text) => redis.stringToBuffer(text);

next() {
  Test test;
  if (tests.length == 0) {
    js.console.log("End of tests.");
    exit(0);
  }
  test = tests.removeAt(0)/*shift()*/;
  test.run(() {
    next();
  });
}

class TestParams {
  final String descr;
  final String command;
  final List args;
  final int pipeline;
  final redis.RedisClientOptions client_opts;
  TestParams({String this.descr, String this.command, List this.args, int this.pipeline, redis.RedisClientOptions this.client_opts});
}

void main(List<String> args) {
  redis.debug_mode = false;
  // Set this to truthy to see the wire protocol and other debugging info
  if (args.length > 0) {
    num_clients = int.parse(args[0], radix: 10);
  } else {
    num_clients = 5;
  }

  small_str = "1234";
  small_buf = stringToBuffer(small_str);//new Buffer(small_str);
  large_str = (new List.generate(4097,(_)=>"-").join(""));
  large_buf = stringToBuffer(large_str);//new Buffer(large_str);

  print("small_buf size:${small_buf.length}, small_str size: ${small_str.length}");
  print("large_buf size:${large_buf.length}, large_str size: ${large_str.length}");
  
  tests.add(new Test(new TestParams(descr: "PING", command: "ping", args: [], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "PING", command: "ping", args: [], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "PING", command: "ping", args: [], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "PING", command: "ping", args: [], pipeline: 20000)));
  tests.add(new Test(new TestParams(descr: "SET small str", command: "set", args: ["foo_rand000000000000", small_str], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "SET small str", command: "set", args: ["foo_rand000000000000", small_str], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "SET small str", command: "set", args: ["foo_rand000000000000", small_str], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "SET small str", command: "set", args: ["foo_rand000000000000", small_str], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "SET small buf", command: "set", args: ["foo_rand000000000000", small_buf], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "SET small buf", command: "set", args: ["foo_rand000000000000", small_buf], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "SET small buf", command: "set", args: ["foo_rand000000000000", small_buf], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "SET small buf", command: "set", args: ["foo_rand000000000000", small_buf], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "GET small str", command: "get", args: ["foo_rand000000000000"], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "GET small str", command: "get", args: ["foo_rand000000000000"], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "GET small str", command: "get", args: ["foo_rand000000000000"], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "GET small str", command: "get", args: ["foo_rand000000000000"], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "GET small buf", command: "get", args: ["foo_rand000000000000"], pipeline: 1, client_opts: new redis.RedisClientOptions(return_buffers: true))));
  tests.add(new Test(new TestParams(descr: "GET small buf", command: "get", args: ["foo_rand000000000000"], pipeline: 50, client_opts: new redis.RedisClientOptions(return_buffers: true))));
  tests.add(new Test(new TestParams(descr: "GET small buf", command: "get", args: ["foo_rand000000000000"], pipeline: 200, client_opts: new redis.RedisClientOptions(return_buffers: true))));
  tests.add(new Test(new TestParams(descr: "GET small buf", command: "get", args: ["foo_rand000000000000"], pipeline: 20000, client_opts: new redis.RedisClientOptions(return_buffers: true))));

  tests.add(new Test(new TestParams(descr: "SET large str", command: "set", args: ["foo_rand000000000001", large_str], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "SET large str", command: "set", args: ["foo_rand000000000001", large_str], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "SET large str", command: "set", args: ["foo_rand000000000001", large_str], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "SET large str", command: "set", args: ["foo_rand000000000001", large_str], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "SET large buf", command: "set", args: ["foo_rand000000000001", large_buf], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "SET large buf", command: "set", args: ["foo_rand000000000001", large_buf], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "SET large buf", command: "set", args: ["foo_rand000000000001", large_buf], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "SET large buf", command: "set", args: ["foo_rand000000000001", large_buf], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "GET large str", command: "get", args: ["foo_rand000000000001"], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "GET large str", command: "get", args: ["foo_rand000000000001"], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "GET large str", command: "get", args: ["foo_rand000000000001"], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "GET large str", command: "get", args: ["foo_rand000000000001"], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "GET large buf", command: "get", args: ["foo_rand000000000001"], pipeline: 1, client_opts: new redis.RedisClientOptions(return_buffers: true))));
  tests.add(new Test(new TestParams(descr: "GET large buf", command: "get", args: ["foo_rand000000000001"], pipeline: 50, client_opts: new redis.RedisClientOptions(return_buffers: true))));
  tests.add(new Test(new TestParams(descr: "GET large buf", command: "get", args: ["foo_rand000000000001"], pipeline: 200, client_opts: new redis.RedisClientOptions(return_buffers: true))));
  tests.add(new Test(new TestParams(descr: "GET large buf", command: "get", args: ["foo_rand000000000001"], pipeline: 20000, client_opts: new redis.RedisClientOptions(return_buffers: true))));

  tests.add(new Test(new TestParams(descr: "INCR", command: "incr", args: ["counter_rand000000000000"], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "INCR", command: "incr", args: ["counter_rand000000000000"], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "INCR", command: "incr", args: ["counter_rand000000000000"], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "INCR", command: "incr", args: ["counter_rand000000000000"], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "LPUSH", command: "lpush", args: ["mylist", small_str], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "LPUSH", command: "lpush", args: ["mylist", small_str], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "LPUSH", command: "lpush", args: ["mylist", small_str], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "LPUSH", command: "lpush", args: ["mylist", small_str], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "LRANGE 10", command: "lrange", args: ["mylist", "0", "9"], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "LRANGE 10", command: "lrange", args: ["mylist", "0", "9"], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "LRANGE 10", command: "lrange", args: ["mylist", "0", "9"], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "LRANGE 10", command: "lrange", args: ["mylist", "0", "9"], pipeline: 20000)));

  tests.add(new Test(new TestParams(descr: "LRANGE 100", command: "lrange", args: ["mylist", "0", "99"], pipeline: 1)));
  tests.add(new Test(new TestParams(descr: "LRANGE 100", command: "lrange", args: ["mylist", "0", "99"], pipeline: 50)));
  tests.add(new Test(new TestParams(descr: "LRANGE 100", command: "lrange", args: ["mylist", "0", "99"], pipeline: 200)));
  tests.add(new Test(new TestParams(descr: "LRANGE 100", command: "lrange", args: ["mylist", "0", "99"], pipeline: 20000)));
  
  // TODO: Profiling tests
  /*tests.add(new Test(new TestParams(descr: "SET large str", command: "set", args: ["foo_rand000000000001", large_str], pipeline: 20000)));
  tests.add(new Test(new TestParams(descr: "SET large buf", command: "set", args: ["foo_rand000000000001", large_buf], pipeline: 20000)));
  tests.add(new Test(new TestParams(descr: "GET large str", command: "get", args: ["foo_rand000000000001"], pipeline: 20000)));
  tests.add(new Test(new TestParams(descr: "GET large buf", command: "get", args: ["foo_rand000000000001"], pipeline: 20000, client_opts: new redis.RedisClientOptions(return_buffers: true))));*/
  

  next();
}

String lpad(input, int len, [chr = " "]) {
  String str = input.toString();
  if (chr == null) {
    chr = " ";
  }


  while (str.length < len) {
    str = chr + str;
  }
  return str;
}

class Histogram extends metrics.Histogram {
  Histogram([sample]) : super(sample);
  String print_line() {
    var obj = this.printObj();
    return lpad(obj.min, 4) + "/" + lpad(obj.max, 4) + "/" + lpad(obj.mean.toStringAsFixed(2), 7) + "/" + lpad(obj.p95.toStringAsFixed(2), 7);
  }
}



class Test {
  List<redis.RedisClient> clients;
  int commands_sent;
  int commands_completed;
  int clients_ready;
  int max_pipeline;
  int test_start;
  redis.RedisClientOptions client_options;
  var callback;
  TestParams args;
  Histogram connect_latency;
  Histogram ready_latency;
  Histogram command_latency;

  Test(TestParams this.args) {
    this.callback = null;
    this.clients = new List(num_clients);
    this.clients_ready = 0;
    this.commands_sent = 0;
    this.commands_completed = 0;
    this.max_pipeline = args.pipeline != null ? args.pipeline : num_requests;
    //TODO: Original test client_options=args.client_options || client_options;
    this.client_options = args.client_opts != null ? args.client_opts : client_options;

    this.connect_latency = new Histogram();
    this.ready_latency = new Histogram();
    this.command_latency = new Histogram();
  }

  run(callback) {
    this.callback = callback;

    for (var i = 0; i < num_clients; i++) {
      this.new_client(i);
    }
  }

  new_client(id) {

    var new_client = redis.createClient(6379, "127.0.0.1", this.client_options);
    var create_time = new DateTime.now().millisecondsSinceEpoch;

    new_client.onConnect.listen((_) {
      connect_latency.update(new DateTime.now().millisecondsSinceEpoch - create_time);
    });

    new_client.onReady.listen((_) {
      if (!versions_logged) {
        js.console.log("Client count: $num_clients , dart version: ${Platform.version}, server version: ${new_client.server_info["redis_version"]}, parser: ${new_client.reply_parser.name}");
        versions_logged = true;
      }
      ready_latency.update(new DateTime.now().millisecondsSinceEpoch - create_time);
      clients_ready++;
      if (clients_ready == clients.length) {
        on_clients_ready();
      }
    });

    clients[id] = new_client;
  }

  on_clients_ready() {
    var str = "${lpad(args.descr, 13)}, ${lpad(args.pipeline, 5)}/$clients_ready ";
    stdout.write(str);
    this.test_start = new DateTime.now().millisecondsSinceEpoch;

    this.fill_pipeline();
  }

  fill_pipeline() {
    int pipeline = commands_sent - commands_completed;

    while (this.commands_sent < num_requests && pipeline < this.max_pipeline) {
      this.commands_sent++;
      pipeline++;
      send_next();
    }

    if (this.commands_completed == num_requests) {
      this.print_stats();
      this.stop_clients();
    }
  }

  stop_clients() {
    for (var pos = 0; pos < clients.length; pos++) {
      var client = clients[pos];
      if (pos == clients.length - 1) {
        client.quit(null, (err, [res]) {
          callback();
        });
      } else {
        client.quit(null);
      }
    }
  }

  send_next() {
    var cur_client = this.commands_sent % this.clients.length;
    var start = new DateTime.now().millisecondsSinceEpoch;

    this.clients[cur_client].send_command(this.args.command, this.args.args, (err, [res]) {
      if (err != null) {
        throw err;
      }
      commands_completed++;
      command_latency.update(new DateTime.now().millisecondsSinceEpoch - start);
      fill_pipeline();
    });
  }

  print_stats() {
    var duration = new DateTime.now().millisecondsSinceEpoch - this.test_start;
    js.console.log("min/max/avg/p95: " + command_latency.print_line() + " " + lpad(duration, 6) + "ms total, " + lpad((num_requests / (duration / 1000)).toStringAsFixed(2), 10) + " ops/sec");
  }
}
