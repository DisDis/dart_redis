import "../lib/dart_redis.dart" as redis;
import "dart:io";
import 'dart:collection';
import "dart:async";
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import "DUnit.dart" as dunit;
import "../lib/js_convert.dart" as js;

/*global require console setTimeout process Buffer */
var PORT = 6379;
var HOST = '127.0.0.1';
Queue<dunit.TestTuple> all_tests;
DateTime cur_start;
DateTime all_start;
int test_count;
redis.RedisClient client;
redis.RedisClient client2;
redis.RedisClient client3;
redis.RedisClient bclient;

List<int> stringToBuffer(String text) => redis.stringToBuffer(text);
String bufferToString(List<int> data) => redis.bufferToString(data);

String bufferToInspectStr(List<int> reply) {
  //<Buffer 73 74 72 69 6e 67 20 76 61 6c 75 65>
  StringBuffer sb = new StringBuffer("<Buffer");
  reply.forEach((item) {
    sb.write(" ");
    sb.write(item.toRadixString(16));
  });
  sb.write(">");
  return sb.toString();
}

run_next_test() {
  if (all_tests.isEmpty) {
    js.console.log('\n  completed \x1b[32m${test_count}\x1b[0m tests in \x1b[33m${new DateTime.now().difference(all_start)}\x1b[0m ms\n');
    client.quit(null);
    client2.quit(null);
    bclient.quit(null);
    return;
  }
  var test = all_tests.removeFirst();
  var test_name = test.testName;
  print('- \x1b[1m${test_name.toLowerCase()}\x1b[0m:');
  cur_start = new DateTime.now();
  test_count += 1;
  test.func();
}

next(name) {
  js.console.log(" \x1b[33m${new DateTime.now().difference(cur_start)}\x1b[0m ms");
  run_next_test();
}

void main(List<String> args) {
  // Set this to truthy to see the wire protocol and other debugging info
  if (args.length > 2) {
    redis.debug_mode = true;//args[2];
  }
  //ProcessSignal.
  client = redis.createClient(PORT, HOST);
  client2 = redis.createClient(PORT, HOST);
  client3 = redis.createClient(PORT, HOST);
  bclient = redis.createClient(PORT, HOST, new redis.RedisClientOptions(return_buffers: true));
  dunit.module("dart_redis");
  var test_db_num = 15, // this DB will be flushed and used for testing
      tests = {},
      connected = false,
      ended = false;


  server_version_at_least(redis.RedisClient connection, desired_version) {
    // Return true if the server version >= desired_version
    var version = connection.server_info["versions"];
    for (var i = 0; i < 3; i++) {
      if (version[i] > desired_version[i]) return true;
      if (version[i] < desired_version[i]) return false;
    }
    return true;
  }

  buffers_to_strings(arr) {
    return new List.from(arr.map((val) {
      return val.toString();
    }));
  }

  /* */redis.RedisCallback require_number(expected, String label) {
    return /* */(err, [results]) {
      dunit.strictEqual(null, err, "$label expected $expected, got error: $err");
      dunit.strictEqual(expected, results, "$label $expected !== $results");
      num numTest = 0;
      dunit.strictEqual(results.runtimeType, numTest.runtimeType/*"number"*/, label);
      return true;
    };
  }

  /* */redis.RedisCallback require_number_any(String label) {
    return /* */(err, [results]) {
      dunit.strictEqual(null, err, "$label expected any number, got error: $err");
      num numTest = 0;
      dunit.strictEqual(results.runtimeType, numTest.runtimeType/*"number"*/, "$label $results is not a number");
      return true;
    };
  }

  /* */redis.RedisCallback require_number_pos(String label) {
    return /* */(err, [results]) {
      dunit.strictEqual(null, err, "$label expected positive number, got error: $err");
      dunit.strictEqual(true, (results > 0), "$label $results is not a positive number");
      return true;
    };
  }

  /* */redis.RedisCallback require_string(str, String label) {
    return /* */(err, [results]) {
      dunit.strictEqual(null, err, "$label expected string '$str', got error: $err");
      dunit.equal(str, results, "$label $str does not match $results");
      return true;
    };
  }

  /* */redis.RedisCallback require_null(String label) {
    return /* */(err, [results]) {
      dunit.strictEqual(null, err, "$label expected null, got error: $err");
      dunit.strictEqual(null, results, "$label : $results is not null");
      return true;
    };
  }

  /* */redis.RedisCallback require_error(String label) {
    return /* */(err, [results]) {
      dunit.notEqual(err, null, "$label err is null, but an error is expected here.");
      return true;
    };
  }

  /* */is_empty_array(obj) {
    return js.Array.isArray(obj) && obj.length == /* === */0;
  }

  /* */redis.RedisCallback last(name, fn) {
    return /* */(err, [results]) {
      fn(err, results);
      next(name);
    };
  }

  // Wraps the given callback in a timeout. If the returned function
  // is not called within the timeout period, we fail the named test.
  /* */redis.RedisCallback with_timeout(name, redis.RedisCallback cb, millis) {

    Timer timeoutId = new Timer(new Duration(milliseconds: millis), () {
      dunit.fail("Callback timed out!", name);
    });
    return (err, [results]) {
      timeoutId.cancel();
      //clearTimeout(timeoutId);
      cb(err, results);
    };
  }


  // Tests are run in the order they are defined, so FLUSHDB should always be first.

  dunit.test("FLUSHDB", () {
    var name = "FLUSHDB";
    client.select(test_db_num, require_string("OK", name));
    client2.select(test_db_num, require_string("OK", name));
    client3.select(test_db_num, require_string("OK", name));
    client.mset(["flush keys 1", "flush val 1", "flush keys 2", "flush val 2"], require_string("OK", name));
    client.FLUSHDB(null, require_string("OK", name));
    client.dbsize(null, last(name, require_number(0, name)));
  });

  dunit.test("INCR", () {
    var name = "INCR";

    if (bclient.reply_parser.name == "hiredis") {
      js.console.log("Skipping INCR buffer test with hiredis");
      return next(name);
    }

    // Test incr with the maximum JavaScript number value. Since we are
    // returning buffers we should get back one more as a Buffer.
    bclient.set(["seq", "9007199254740992"], /* */(err, [result]) {
      dunit.strictEqual(bufferToString(result), "OK");
      bclient.incr(["seq"], /* */(err, [result]) {
        dunit.strictEqual("9007199254740993", bufferToString(result));
        next(name);
      });
    });
  });

  dunit.test("MULTI_1", () {
    var name = "MULTI_1";

    // Provoke an error at queue time
    redis.Multi multi1 = client.multi();
    multi1.mset(["multifoo", "10", "multibar", "20"], require_string("OK", name));
    multi1.set(["foo2"], require_error(name));
    multi1.incr(["multifoo"], require_number(11, name));
    multi1.incr(["multibar"], require_number(21, name));
    multi1.exec(/* */(_, [__]) {
      require_error(name);

      // Redis 2.6.5+ will abort transactions with errors
      // see: http://redis.io/topics/transactions
      var multibar_expected = 22;
      var multifoo_expected = 12;
      if (server_version_at_least(client, [2, 6, 5])) {
        multibar_expected = 1;
        multifoo_expected = 1;
      }

      // Confirm that the previous command, while containing an error, still worked.
      redis.Multi multi2 = client.multi();
      multi2.incr(["multibar"], require_number(multibar_expected, name));
      multi2.incr(["multifoo"], require_number(multifoo_expected, name));
      multi2.exec(/* */(err, [replies]) {
        dunit.strictEqual(multibar_expected, replies[0]);
        dunit.strictEqual(multifoo_expected, replies[1]);
        next(name);
      });
    });
  });

  dunit.test("MULTI_2", () {
    var name = "MULTI_2";
    // test nested multi-bulk replies
    client.multi([new redis.MultiCommand("mget", ["multifoo", "multibar"], /* */ /**/
      (err, [res]) {
        dunit.strictEqual(2, res.length, name);
        dunit.strictEqual("12", res[0].toString(), name);
        dunit.strictEqual("22", res[1].toString(), name);
      }), new redis.MultiCommand("set", ["foo2"], require_error(name)), new redis.MultiCommand("incr", ["multifoo"], require_number(13, name)), new redis.MultiCommand("incr", ["multibar"], require_number(23, name))]).exec(/* */(err, [replies]) {
      if (server_version_at_least(client, [2, 6, 5])) {
        dunit.notEqual(err, null, name);
        //FIXME: replace undefined
        dunit.equal(replies, null/*undefined*/, name);
      } else {
        dunit.strictEqual(2, replies[0].length, name);
        dunit.strictEqual("12", replies[0][0].toString(), name);
        dunit.strictEqual("22", replies[0][1].toString(), name);

        dunit.strictEqual("13", replies[1].toString());
        dunit.strictEqual("23", replies[2].toString());
      }
      next(name);
    });
  });

  dunit.test("MULTI_3", () {
    var name = "MULTI_3";
    client.sadd(["some set", "mem 1"]);
    client.sadd(["some set", "mem 2"]);
    client.sadd(["some set", "mem 3"]);
    client.sadd(["some set", "mem 4"]);

    // make sure empty mb reply works
    client.del(["some missing set"]);
    client.smembers(["some missing set"], /* */(err, [reply]) {
      // make sure empty mb reply works
      dunit.strictEqual(true, is_empty_array(reply), name);
    });

    // test nested multi-bulk replies with empty mb elements.
    client.multi([new redis.MultiCommand("smembers", ["some set"]), new redis.MultiCommand("del", ["some set"]), new redis.MultiCommand("smembers", ["some set"])]).scard(["some set"]).exec(/* */(err, [replies]) {
      dunit.strictEqual(true, is_empty_array(replies[2]), name);
      next(name);
    });
  });

  dunit.test("MULTI_4", () {
    var name = "MULTI_4";

    client.multi().mset(['some', '10', 'keys', '20']).incr(['some']).incr(['keys']).mget(['some', 'keys']).exec((err, [replies]) {
      dunit.strictEqual(null, err);
      dunit.equal('OK', replies[0]);
      dunit.equal(11, replies[1]);
      dunit.equal(21, replies[2]);
      dunit.equal("11", replies[3][0]);
      dunit.equal("21", replies[3][1]);
      next(name);
    });
  });

  dunit.test("MULTI_5", () {
    var name = "MULTI_5";

    // test nested multi-bulk replies with nulls.
    client.multi([new redis.MultiCommand("mget", ["multifoo", "some", "random value", "keys"]), new redis.MultiCommand("incr", ["multifoo"])]).exec((err, [replies]) {
      dunit.strictEqual(replies.length, 2, name);
      dunit.strictEqual(replies[0].length, 4, name);
      next(name);
    });
  });

  dunit.test("MULTI_6", () {
    var name = "MULTI_6";

    client.multi().hmset(["multihash", "a", "foo", "b", 1]).hmset(["multihash", {
        "extra": "fancy",
        "things": "here"
      }]).hgetall(["multihash"]).exec((err, [replies]) {
      dunit.strictEqual(null, err);
      dunit.equal("OK", replies[0]);
      dunit.strictEqual(replies[2].runtimeType, new Map().runtimeType);
      dunit.equal(replies[2].keys.length, 4);
      dunit.equal("foo", replies[2]["a"]);
      dunit.equal("1", replies[2]["b"]);
      dunit.equal("fancy", replies[2]["extra"]);
      dunit.equal("here", replies[2]["things"]);
      next(name);
    });
  });

  dunit.test("MULTI_7", () {
    var name = "MULTI_7";

    if (bclient.reply_parser.name != "dart") {
      js.console.log("Skipping wire-protocol test for 3rd-party parser");
      return next(name);
    }

    var parser = new redis.ReplyParser(new redis.ParserSettings());
    var reply_count = 0;
    check_reply(redis.RedisReply replyMsg) {
      var reply = replyMsg.data;
      dunit.deepEqual(reply, [['a']], "Expecting multi-bulk reply of [['a']]");
      reply_count++;
      dunit.notEqual(reply_count, 4, "Should only parse 3 replies");
    }
    parser.onReply.listen(check_reply);
    parser.execute(stringToBuffer('*1\r\n*1\r\n\$1\r\na\r\n'));

    parser.execute(stringToBuffer('*1\r\n*1\r'));
    parser.execute(stringToBuffer('\n\$1\r\na\r\n'));

    parser.execute(stringToBuffer('*1\r\n*1\r\n'));
    parser.execute(stringToBuffer('\$1\r\na\r\n'));

    next(name);
  });


  dunit.test("MULTI_EXCEPTION_1", () {
    var name = "MULTI_EXCEPTION_1";

    if (!server_version_at_least(client, [2, 6, 5])) {
      js.console.log("Skipping " + name + " for old Redis server version < 2.6.5");
      return next(name);
    }

    client.multi().set(["foo"]).exec((err, [reply]) {
      dunit.assert1(err is List, "err should be an array");//assert(Array.isArray(err),
      dunit.equal(2, err.length, "err should have 2 items");
      dunit.assert1(err[0].message.indexOf("ERR") != -1, "First error message should contain ERR");//.match(/ERR/)
      dunit.assert1(err[1].message.indexOf("EXECABORT") != -1, "First error message should contain EXECABORT");//.match(/EXECABORT/)
      next(name);
    });
  });

  dunit.test("MULTI_8", () {
    var name = "MULTI_8";

    // Provoke an error at queue time
    redis.Multi multi1 = client.multi();
    multi1.mset(["multifoo_8", "10", "multibar_8", "20"], require_string("OK", name));
    multi1.set(["foo2"], require_error(name));
    multi1.set(["foo3"], require_error(name));
    multi1.incr(["multifoo_8"], require_number(11, name));
    multi1.incr(["multibar_8"], require_number(21, name));
    multi1.exec((err, [res]) {
      require_error(name);

      // Redis 2.6.5+ will abort transactions with errors
      // see: http://redis.io/topics/transactions
      var multibar_expected = 22;
      var multifoo_expected = 12;
      if (server_version_at_least(client, [2, 6, 5])) {
        multibar_expected = 1;
        multifoo_expected = 1;
      }

      // Confirm that the previous command, while containing an error, still worked.
      redis.Multi multi2 = client.multi();
      multi2.incr(["multibar_8"], require_number(multibar_expected, name));
      multi2.incr(["multifoo_8"], require_number(multifoo_expected, name));
      multi2.exec((err, [replies]) {
        dunit.strictEqual(multibar_expected, replies[0]);
        dunit.strictEqual(multifoo_expected, replies[1]);
        next(name);
      });
    });
  });

  //TODO: Implement
   /*dunit.test("FWD_ERRORS_1",() {
            var name = "FWD_ERRORS_1";

            var toThrow = new js.Error("Forced exception");
            var recordedError = null;

            //DISABLED!
            //var originalHandlers = client3.listeners("error");
            //DISABLED!
            //client3.removeAllListeners("error");
            client3.onError.first.then((err) {
                recordedError = err;
            });

            client3.onMessage.listen((redis.MessageMsg msg){
                js.console.log("incoming");
                var channel = msg.channel;
                var data = msg.message;
                if (channel == name) {
                    dunit.equal(data, "Some message");
                    throw toThrow;
                }
            });
            client3.subscribe([name]);

            client.publish([name, "Some message"]);
            new Timer(new Duration(milliseconds: 150), () {
                //DISABLED!
                //client3.listeners("error").push(originalHandlers);
                dunit.equal(recordedError, toThrow, "Should have caught our forced exception");
                next(name);
            });
        });

       dunit.test("FWD_ERRORS_2",() {
            var name = "FWD_ERRORS_2";

            var toThrow = new js.Error("Forced exception");
            var recordedError = null;

            var originalHandler = client.listeners("error").pop();
            client.removeAllListeners("error");
            client.once("error",  (err) {
                recordedError = err;
            });

            client.get(["no_such_key"],  (err, [reply]) {
                throw toThrow;
            });

            new Timer(new Duration(milliseconds: 150),() {
                client.listeners("error").push(originalHandler);
                dunit.equal(recordedError, toThrow, "Should have caught our forced exception");
                next(name);
            });
        });

        dunit.test("FWD_ERRORS_3",() {
            var name = "FWD_ERRORS_3";

            var recordedError = null;

            var originalHandler = client.listeners("error").pop();
            client.removeAllListeners("error");
            client.once("error",  (err) {
                recordedError = err;
            });

            client.send_command("no_such_command", []);

            new Timer(new Duration(milliseconds: 150),() {
                client.listeners("error").push(originalHandler);
                dunit.ok(recordedError is js.Error,true);
                next(name);
            });
        });

        dunit.test("FWD_ERRORS_4",() {
            var name = "FWD_ERRORS_4";

            var toThrow = new js.Error("Forced exception");
            var recordedError = null;

            var originalHandler = client.listeners("error").pop();
            client.removeAllListeners("error");
            client.once("error",  (err) {
                recordedError = err;
            });

            client.send_command("no_such_command", [],  (err,[res]) {
                throw toThrow;
            });
            
            new Timer(new Duration(milliseconds: 150),  () {
                client.listeners("error").push(originalHandler);
                dunit.equal(recordedError, toThrow, "Should have caught our forced exception");
                next(name);
            });
        });*/
  dunit.test("EVAL_1", () {
    var name = "EVAL_1";

    if (!server_version_at_least(client, [2, 5, 0])) {
      js.console.log("Skipping " + name + " for old Redis server version < 2.5.x");
      return next(name);
    }
    // test {EVAL - Lua integer -> Redis protocol type conversion}
    client.eval(["return 100.5", 0], require_number(100, name));
    // test {EVAL - Lua string -> Redis protocol type conversion}
    client.eval(["return 'hello world'", 0], require_string("hello world", name));
    // test {EVAL - Lua true boolean -> Redis protocol type conversion}
    client.eval(["return true", 0], require_number(1, name));
    // test {EVAL - Lua false boolean -> Redis protocol type conversion}
    client.eval(["return false", 0], require_null(name));
    // test {EVAL - Lua status code reply -> Redis protocol type conversion}
    client.eval(["return {ok='fine'}", 0], require_string("fine", name));
    // test {EVAL - Lua error reply -> Redis protocol type conversion}
    client.eval(["return {err='this is an error'}", 0], require_error(name));
    // test {EVAL - Lua table -> Redis protocol type conversion}
    client.eval(["return {1,2,3,'ciao',{1,2}}", 0], (err, [res]) {
      dunit.strictEqual(5, res.length, name);
      dunit.strictEqual(1, res[0], name);
      dunit.strictEqual(2, res[1], name);
      dunit.strictEqual(3, res[2], name);
      dunit.strictEqual("ciao", res[3], name);
      dunit.strictEqual(2, res[4].length, name);
      dunit.strictEqual(1, res[4][0], name);
      dunit.strictEqual(2, res[4][1], name);
    });
    // test {EVAL - Are the KEYS and ARGS arrays populated correctly?}
    client.eval(["return {KEYS[1],KEYS[2],ARGV[1],ARGV[2]}", 2, "a", "b", "c", "d"], (err, [res]) {
      dunit.strictEqual(4, res.length, name);
      dunit.strictEqual("a", res[0], name);
      dunit.strictEqual("b", res[1], name);
      dunit.strictEqual("c", res[2], name);
      dunit.strictEqual("d", res[3], name);
    });

    // test {EVAL - parameters in array format gives same result}
    client.eval(["return {KEYS[1],KEYS[2],ARGV[1],ARGV[2]}", 2, "a", "b", "c", "d"], (err, [res]) {
      dunit.strictEqual(4, res.length, name);
      dunit.strictEqual("a", res[0], name);
      dunit.strictEqual("b", res[1], name);
      dunit.strictEqual("c", res[2], name);
      dunit.strictEqual("d", res[3], name);
    });

    // prepare sha sum for evalsha cache test
    var source = "return redis.call('get', 'sha test')";

    //var sha = crypto.createHash('sha1').update(source).digest('hex');
    var shaC = new crypto.SHA1();
    shaC.add(source.codeUnits);
    String sha = crypto.CryptoUtils.bytesToHex(shaC.close());

    client.set(["sha test", "eval get sha test"], (err, [res]) {
      if (err != null) throw err;
      // test {EVAL - is Lua able to call Redis API?}
      client.eval([source, 0], (err, [res]) {
        require_string("eval get sha test", name)(err, res);
        // test {EVALSHA - Can we call a SHA1 if already defined?}
        client.evalsha([sha, 0], require_string("eval get sha test", name));
        // test {EVALSHA - Do we get an error on non defined SHA1?}
        client.evalsha(["ffffffffffffffffffffffffffffffffffffffff", 0], require_error(name));
      });
    });

    // test {EVAL - Redis integer -> Lua type conversion}
    client.set(["incr key", 0], (err, [reply]) {
      if (err != null) throw err;
      client.eval(["local foo = redis.call('incr','incr key')\n" + "return {type(foo),foo}", 0], (err, [res]) {
        if (err != null) throw err;
        dunit.strictEqual(2, res.length, name);
        dunit.strictEqual("number", res[0], name);
        dunit.strictEqual(1, res[1], name);
      });
    });

    client.set(["bulk reply key", "bulk reply value"], (err, [res]) {
      // test {EVAL - Redis bulk -> Lua type conversion}
      client.eval(["local foo = redis.call('get','bulk reply key'); return {type(foo),foo}", 0], (err, [res]) {
        if (err != null) throw err;
        dunit.strictEqual(2, res.length, name);
        dunit.strictEqual("string", res[0], name);
        dunit.strictEqual("bulk reply value", res[1], name);
      });
    });

    // test {EVAL - Redis multi bulk -> Lua type conversion}
    client.multi().del(["mylist"]).rpush(["mylist", "a"]).rpush(["mylist", "b"]).rpush(["mylist", "c"]).exec((err, [replies]) {
      if (err != null) throw err;
      client.eval(["local foo = redis.call('lrange','mylist',0,-1); return {type(foo),foo[1],foo[2],foo[3],# foo}", 0], (err, [res]) {
        dunit.strictEqual(5, res.length, name);
        dunit.strictEqual("table", res[0], name);
        dunit.strictEqual("a", res[1], name);
        dunit.strictEqual("b", res[2], name);
        dunit.strictEqual("c", res[3], name);
        dunit.strictEqual(3, res[4], name);
      });
    });
    // test {EVAL - Redis status reply -> Lua type conversion}
    client.eval(["local foo = redis.call('set','mykey','myval'); return {type(foo),foo['ok']}", 0], (err, [res]) {
      if (err != null) throw err;
      dunit.strictEqual(2, res.length, name);
      dunit.strictEqual("table", res[0], name);
      dunit.strictEqual("OK", res[1], name);
    });
    // test {EVAL - Redis error reply -> Lua type conversion}
    client.set(["error reply key", "error reply value"], (err, [res]) {
      if (err != null) throw err;
      client.eval(["local foo = redis.pcall('incr','error reply key'); return {type(foo),foo['err']}", 0], (err, [res]) {
        if (err != null) throw err;
        dunit.strictEqual(2, res.length, name);
        dunit.strictEqual("table", res[0], name);
        dunit.strictEqual("ERR value is not an integer or out of range", res[1], name);
      });
    });
    // test {EVAL - Redis nil bulk reply -> Lua type conversion}
    client.del(["nil reply key"], (err, [res]) {
      if (err != null) throw err;
      client.eval(["local foo = redis.call('get','nil reply key'); return {type(foo),foo == false}", 0], (err, [res]) {
        if (err != null) throw err;
        dunit.strictEqual(2, res.length, name);
        dunit.strictEqual("boolean", res[0], name);
        dunit.strictEqual(1, res[1], name);
        next(name);
      });
    });
  });

  dunit.test("SCRIPT_LOAD", () {
    var name = "SCRIPT_LOAD";
    var command = "return 1";

    var shaC = new crypto.SHA1();
    shaC.add(command.codeUnits);
    String commandSha = crypto.CryptoUtils.bytesToHex(shaC.close());

    //commandSha = crypto.createHash('sha1').update(command).digest('hex');

    if (!server_version_at_least(client, [2, 6, 0])) {
      js.console.log("Skipping " + name + " for old Redis server version < 2.6.x");
      return next(name);
    }

    bclient.script(["load", command], (err, [result]) {
      dunit.strictEqual(bufferToString(result), commandSha);
      client.multi().script(["load", command]).exec((err, [result]) {
        dunit.strictEqual(result[0].toString(), commandSha);
        client.multi([new redis.MultiCommand('script', ['load', command])]).exec((err, [result]) {
          dunit.strictEqual(result[0].toString(), commandSha);
          next(name);
        });
      });
    });
  });

  dunit.test("CLIENT_LIST", () {
    var name = "CLIENT_LIST";

    if (!server_version_at_least(client, [2, 4, 0])) {
      js.console.log("Skipping $name for old Redis server version < 2.4.x");
      return next(name);
    }

    checkResult(String linesStr) {
      List<String> lines = linesStr.split('\n');
      lines.removeLast();
      dunit.strictEqual(lines.length, 4);
      dunit.assert1(lines.every((line) {
        return line.indexOf("addr=") == 0;//line.match(/^addr=/);
      }));
    }

    bclient.client(["list"], (err, [result]) {
      js.console.log(bufferToString(result));
      checkResult(bufferToString(result));
      client.multi().client(["list"]).exec((err, [result]) {
        js.console.log(result.toString());
        checkResult(result.join(','));
        client.multi([new redis.MultiCommand('client', ['list'])]).exec((err, [result]) {
          js.console.log(result.toString());
          checkResult(result.join(','));
          next(name);
        });
      });
    });
  });

  dunit.test("WATCH_MULTI", () {
    var name = 'WATCH_MULTI',
        multi;
    if (!server_version_at_least(client, [2, 2, 0])) {
      js.console.log("Skipping " + name + " for old Redis server version < 2.2.x");
      return next(name);
    }

    client.watch([name]);
    client.incr([name]);
    multi = client.multi();
    multi.incr([name]);
    multi.exec(last(name, require_null(name)));
  });

  dunit.test("WATCH_TRANSACTION", () {
    var name = "WATCH_TRANSACTION";

    if (!server_version_at_least(client, [2, 1, 0])) {
      js.console.log("Skipping " + name + " because server version isn't new enough.");
      return next(name);
    }

    // Test WATCH command aborting transactions, look for parser offset errors.

    client.set(["unwatched", 200]);

    client.set([name, 0]);
    client.watch([name]);
    client.incr([name]);
    var multi = client.multi().incr([name]).exec((err, [replies]) {
      // Failure expected because of pre-multi incr
      dunit.strictEqual(replies, null, "Aborted transaction multi-bulk reply should be null.");

      client.get(["unwatched"], (err, [reply]) {
        dunit.equal(err, null, name);
        //ORIGINAL: changed to 200 -> "200"
        dunit.equal(reply, "200", "Expected 200, got $reply");
        next(name);
      });
    });

    client.set(["unrelated", 100], (err, [reply]) {
      dunit.equal(err, null, name);
      dunit.equal(reply, "OK", "Expected 'OK', got $reply");
    });
  });

  dunit.test("detect_buffers", () {
    var name = "detect_buffers";
    redis.RedisClient detect_client = redis.createClient(null, null, new redis.RedisClientOptions(detect_buffers: true));

    detect_client.on("ready", (_) {
      // single Buffer or String
      detect_client.set(["string key 1", "string value"]);
      detect_client.get(["string key 1"], require_string("string value", name));
      detect_client.get([stringToBuffer("string key 1")], (err, [reply]) {
        dunit.strictEqual(null, err, name);
        dunit.strictEqual(true, redis.RedisClient.isBuffer(reply), name);

        dunit.strictEqual("<Buffer 73 74 72 69 6e 67 20 76 61 6c 75 65>", bufferToInspectStr(reply)/*reply.inspect()*/, name);
      });
      detect_client.hmset(["hash key 2", "key 1", "val 1", "key 2", "val 2"]);
      // array of Buffers or Strings
      detect_client.hmget(["hash key 2", "key 1", "key 2"], (err, [reply]) {
        dunit.strictEqual(null, err, name);
        dunit.strictEqual(true, js.Array.isArray(reply), name);
        dunit.strictEqual(2, reply.length, name);
        dunit.strictEqual("val 1", reply[0], name);
        dunit.strictEqual("val 2", reply[1], name);
      });
      detect_client.hmget([stringToBuffer("hash key 2"), "key 1", "key 2"], (err, [reply]) {
        dunit.strictEqual(null, err, name);
        dunit.strictEqual(true, js.Array.isArray(reply));
        dunit.strictEqual(2, reply.length, name);
        dunit.strictEqual(true, redis.RedisClient.isBuffer(reply[0]));
        dunit.strictEqual(true, redis.RedisClient.isBuffer(reply[1]));
        dunit.strictEqual("<Buffer 76 61 6c 20 31>", bufferToInspectStr(reply[0]), name);
        dunit.strictEqual("<Buffer 76 61 6c 20 32>", bufferToInspectStr(reply[1]), name);
      });

      // array of strings with undefined values (repro #344)
      detect_client.hmget(["hash key 2", "key 3", "key 4"], (err, [reply]) {
        dunit.strictEqual(null, err, name);
        dunit.strictEqual(true, js.Array.isArray(reply), name);
        dunit.strictEqual(2, reply.length, name);
        dunit.equal(null, reply[0], name);
        dunit.equal(null, reply[1], name);
      });

      // Object of Buffers or Strings
      detect_client.hgetall(["hash key 2"], (err, [reply]) {
        dunit.strictEqual(null, err, name);
        dunit.strictEqual(new Map().runtimeType, reply.runtimeType, name);
        dunit.strictEqual(2, reply.keys.length, name);
        dunit.strictEqual("val 1", reply["key 1"], name);
        dunit.strictEqual("val 2", reply["key 2"], name);
      });
      detect_client.hgetall([stringToBuffer("hash key 2")], (err, [reply]) {
        dunit.strictEqual(null, err, name);
        dunit.strictEqual(new Map().runtimeType, reply.runtimeType, name);
        dunit.strictEqual(2, reply.keys.length, name);
        dunit.strictEqual(true, redis.RedisClient.isBuffer(reply["key 1"]));
        dunit.strictEqual(true, redis.RedisClient.isBuffer(reply["key 2"]));
        dunit.strictEqual("<Buffer 76 61 6c 20 31>", bufferToInspectStr(reply["key 1"]), name);
        dunit.strictEqual("<Buffer 76 61 6c 20 32>", bufferToInspectStr(reply["key 2"]), name);
      });

      detect_client.quit(null, (err, [res]) {
        next(name);
      });
    });
  });

  dunit.test("socket_nodelay", () {
    var name = "socket_nodelay",
        ready_count = 0,
        quit_count = 0;

    redis.RedisClient c1 = redis.createClient(null, null, new redis.RedisClientOptions(socket_nodelay: true));
    redis.RedisClient c2 = redis.createClient(null, null, new redis.RedisClientOptions(socket_nodelay: false));
    redis.RedisClient c3 = redis.createClient(null, null);

    quit_check(_, [__]) {
      quit_count++;

      if (quit_count == /* === */3) {
        next(name);
      }
    }

    run() {
      dunit.strictEqual(true, c1.options.socket_nodelay, name);
      dunit.strictEqual(false, c2.options.socket_nodelay, name);
      dunit.strictEqual(true, c3.options.socket_nodelay, name);

      c1.set(["set key 1", "set val"], require_string("OK", name));
      c1.set(["set key 2", "set val"], require_string("OK", name));
      c1.get(["set key 1"], require_string("set val", name));
      c1.get(["set key 2"], require_string("set val", name));

      c2.set(["set key 3", "set val"], require_string("OK", name));
      c2.set(["set key 4", "set val"], require_string("OK", name));
      c2.get(["set key 3"], require_string("set val", name));
      c2.get(["set key 4"], require_string("set val", name));

      c3.set(["set key 5", "set val"], require_string("OK", name));
      c3.set(["set key 6", "set val"], require_string("OK", name));
      c3.get(["set key 5"], require_string("set val", name));
      c3.get(["set key 6"], require_string("set val", name));

      c1.quit(null, quit_check);
      c2.quit(null, quit_check);
      c3.quit(null, quit_check);
    }

    ready_check(_, [__]) {
      ready_count++;
      if (ready_count == /* === */3) {
        run();
      }
    }

    c1.on("ready", ready_check);
    c2.on("ready", ready_check);
    c3.on("ready", ready_check);
  });

  dunit.test("reconnect", () {
    var name = "reconnect";

    client.set(["recon 1", "one"]);
    client.set(["recon 2", "two"], (err, [res]) {
      // Do not do this in normal programs. This is to simulate the server closing on us.
      // For orderly shutdown in normal programs, do client.quit()
      client.stream.shutdown(SocketDirection.BOTH);// .destroy();
    });
    StreamSubscription sson_recon;
    on_recon(redis.ReconnectingParams params) {
      StreamSubscription sson_connect;
      on_connect(_) {
        client.select(test_db_num, require_string("OK", name));
        client.get(["recon 1"], require_string("one", name));
        client.get(["recon 1"], require_string("one", name));
        client.get(["recon 2"], require_string("two", name));
        client.get(["recon 2"], require_string("two", name));
        sson_connect.cancel();//client.removeListener("connect", on_connect);
        sson_recon.cancel();//client.removeListener("reconnecting", on_recon);
        next(name);
      }
      sson_connect = client.on("connect", on_connect);
    }
    sson_recon = client.on("reconnecting", on_recon);
  });

  dunit.test("reconnect_select_db_after_pubsub", () {
    var name = "reconnect_select_db_after_pubsub";

    client.select(test_db_num);
    client.set([name, "one"]);
    client.subscribe(['ChannelV'], (err, [res]) {
      client.stream.close();//destroy();
    });
    StreamSubscription sson_recon;
    on_recon(params) {
      StreamSubscription sson_connect;
      on_connect(_) {
        client.unsubscribe(['ChannelV'], (err, [res]) {
          client.get([name], require_string("one", name));
          sson_connect.cancel();//client.removeListener("connect", on_connect);
          sson_recon.cancel();//client.removeListener("reconnecting", on_recon);
          next(name);
        });
      }
      sson_connect = client.on("ready", on_connect);
    }
    sson_recon = client.on("reconnecting", on_recon);
  });

  dunit.test("idle", () {
    var name = "idle";
    StreamSubscription ssidle;
    on_idle(_) {
      ssidle.cancel();//client.removeListener("idle", on_idle);
      next(name);
    }
    ssidle = client.on("idle", on_idle);

    client.set(["idle", "test"]);
  });


  dunit.test("HSET", () {
    var key = "test hash",
        field1 = stringToBuffer("0123456789"),
        value1 = stringToBuffer("abcdefghij"),
        field2 = stringToBuffer(""),//stringToBuffer(0),
        value2 = stringToBuffer(""),//stringToBuffer(0),
        name = "HSET";

    client.HSET([key, field1, value1], require_number(1, name));
    client.HGET([key, field1], require_string(bufferToString(value1), name));

    // Empty value
    client.HSET([key, field1, value2], require_number(0, name));
    client.HGET([key, field1], require_string("", name));

    // Empty key, empty value
    client.HSET([key, field2, value1], require_number(1, name));
    client.HSET([key, field2, value2], last(name, require_number(0, name)));
  });

  dunit.test("HLEN", () {
    var key = "test hash",
        field1 = stringToBuffer("0123456789"),
        value1 = stringToBuffer("abcdefghij"),
        field2 = stringToBuffer(""),//stringToBuffer(0),
        value2 = stringToBuffer(""),//stringToBuffer(0),
        name = "HSET",
        timeout = 1000;

    client.HSET([key, field1, value1], (err, [results]) {
      client.HLEN([key], (err, [len]) {
        if (len is num) {
          dunit.ok(2 == /* === */len);
        } else {
          dunit.ok(2 == /* === */int.parse(len));
        }
        next(name);
      });
    });
  });

  dunit.test("HMSET_BUFFER_AND_ARRAY", () {
    // Saving a buffer and an array to the same key should not error
    var key = "test hash",
        field1 = "buffer",
        value1 = stringToBuffer("abcdefghij"),
        field2 = "array",
        value2 = ["array contents"],
        name = "HSET";

    client.HMSET([key, field1, value1, field2, value2], last(name, require_string("OK", name)));
  });

  // TODO - add test for HMSET with optional callbacks
  dunit.test("HMGET", () {
    var key1 = "test hash 1",
        key2 = "test hash 2",
        key3 = 123456789,
        name = "HMGET";

    // redis-like hmset syntax
    client.HMSET([key1, "0123456789", "abcdefghij", "some manner of key", "a type of value"], require_string("OK", name));

    // fancy hmset syntax
    client.HMSET([key2, {
        "0123456789": "abcdefghij",
        "some manner of key": "a type of value"
      }], require_string("OK", name));

    // test for numeric key
    client.HMSET([key3, {
        "0123456789": "abcdefghij",
        "some manner of key": "a type of value"
      }], require_string("OK", name));

    client.HMGET([key1, "0123456789", "some manner of key"], (err, [reply]) {
      dunit.strictEqual("abcdefghij", reply[0].toString(), name);
      dunit.strictEqual("a type of value", reply[1].toString(), name);
    });

    client.HMGET([key2, "0123456789", "some manner of key"], (err, [reply]) {
      dunit.strictEqual("abcdefghij", reply[0].toString(), name);
      dunit.strictEqual("a type of value", reply[1].toString(), name);
    });

    client.HMGET([key3, "0123456789", "some manner of key"], (err, [reply]) {
      dunit.strictEqual("abcdefghij", reply[0].toString(), name);
      dunit.strictEqual("a type of value", reply[1].toString(), name);
    });

    client.HMGET([key1, ["0123456789"]], (err, [reply]) {
      dunit.strictEqual("abcdefghij", reply[0], name);
    });

    client.HMGET([key1, ["0123456789", "some manner of key"]], (err, [reply]) {
      dunit.strictEqual("abcdefghij", reply[0], name);
      dunit.strictEqual("a type of value", reply[1], name);
    });

    client.HMGET([key1, "missing thing", "another missing thing"], (err, [reply]) {
      dunit.strictEqual(null, reply[0], name);
      dunit.strictEqual(null, reply[1], name);
      next(name);
    });
  });

  dunit.test("HINCRBY", () {
    var name = "HINCRBY";
    client.hset(["hash incr", "value", 10], require_number(1, name));
    client.HINCRBY(["hash incr", "value", 1], require_number(11, name));
    client.HINCRBY(["hash incr", "value 2", 1], last(name, require_number(1, name)));
  });

  dunit.test("SUBSCRIBE", () {
    var client1 = client;
    int msg_count = 0;
    var name = "SUBSCRIBE";

    client1.onSubscribe.listen((msg) {
      var channel = msg.channel;
      var count = msg.count;
      if (channel == /* === */"chan1") {
        client2.publish(["chan1", "message 1"], require_number(1, name));
        client2.publish(["chan2", "message 2"], require_number(1, name));
        client2.publish(["chan1", "message 3"], require_number(1, name));
      }
    });

    client1.onUnsubscribe.listen((msg) {
      var channel = msg.channel;
      var count = msg.count;
      if (count == /* === */0) {
        // make sure this connection can go into and out of pub/sub mode
        client1.incr(["did a thing"], last(name, require_number(2, name)));
      }
    });

    client1.onMessage.listen((msg) {
      var channel = msg.channel;
      var message = msg.message;
      msg_count += 1;
      dunit.strictEqual("message $msg_count", message.toString());
      if (msg_count == /* === */3) {
        client1.unsubscribe(["chan1", "chan2"]);
      }
    });

    client1.set(["did a thing", 1], require_string("OK", name));
    client1.subscribe(["chan1", "chan2"], (err, [results]) {
      dunit.strictEqual(null, err, "result sent back unexpected error: $err");
      dunit.strictEqual("chan1", results.toString(), name);
    });
  });

  dunit.test("UNSUB_EMPTY", () {
    // test situation where unsubscribe reply[1] is null
    var name = "UNSUB_EMPTY";
    client3.unsubscribe([]); // unsubscribe from all so can test null
    client3.unsubscribe([]); // reply[1] will be null
    next(name);
  });

  dunit.test("PUNSUB_EMPTY", () {
    // test situation where punsubscribe reply[1] is null
    var name = "PUNSUB_EMPTY";
    client3.punsubscribe([]); // punsubscribe from all so can test null
    client3.punsubscribe([]); // reply[1] will be null
    next(name);
  });

  dunit.test("UNSUB_EMPTY_CB", () {
    var name = "UNSUB_EMPTY_CB";
    // test hangs on older versions of redis, so skip
    if (!server_version_at_least(client, [2, 6, 11])) return next(name);

    // test situation where unsubscribe reply[1] is null
    client3.unsubscribe([]); // unsubscribe from all so can test null
    client3.unsubscribe([], (err, [results]) {
      // reply[1] will be null
      dunit.strictEqual(null, err, "unexpected error: $err");
      next(name);
    });
  });

  dunit.test("PUNSUB_EMPTY_CB", () {
    var name = "PUNSUB_EMPTY_CB";
    // test hangs on older versions of redis, so skip
    if (!server_version_at_least(client, [2, 6, 11])) return next(name);

    // test situation where punsubscribe reply[1] is null
    client3.punsubscribe([]); // punsubscribe from all so can test null
    client3.punsubscribe([], (err, [results]) {
      // reply[1] will be null
      dunit.strictEqual(null, err, "unexpected error: $err");
      next(name);
    });
  });

  dunit.test("SUB_UNSUB_SUB", () {
    var name = "SUB_UNSUB_SUB";
    // test hangs on older versions of redis, so skip
    if (!server_version_at_least(client, [2, 6, 11])) return next(name);

    client3.subscribe(['chan3']);
    client3.unsubscribe(['chan3']);
    client3.subscribe(['chan3'], (err, [results]) {
      dunit.strictEqual(null, err, "unexpected error: $err");
      client2.publish(['chan3', 'foo']);
    });
    StreamSubscription ss;
    StreamController sc = new StreamController();
    ss = client3.onMessage.listen((redis.MessageMsg msg) {
      var channel = msg.channel;
      var message = msg.message;
      dunit.strictEqual(channel, 'chan3');
      dunit.strictEqual(message, 'foo');
      //client3.removeAllListeners();
      //next(name);
      ss.cancel();
      sc.add(true);
    });
    sc.stream.listen((_) {
      next(name);
    });
  });

  dunit.test("SUB_UNSUB_MSG_SUB", () {
    var name = "SUB_UNSUB_MSG_SUB";
    // test hangs on older versions of redis, so skip
    if (!server_version_at_least(client, [2, 6, 11])) return next(name);

    client3.subscribe(['chan8']);
    client3.subscribe(['chan9']);
    client3.unsubscribe(['chan9']);
    client2.publish(['chan8', 'something']);
    client3.subscribe(['chan9'], with_timeout(name, (err, [results]) {
      next(name);
    }, 2000));
  });

  dunit.test("PSUB_UNSUB_PMSG_SUB", () {
    var name = "PSUB_UNSUB_PMSG_SUB";
    // test hangs on older versions of redis, so skip
    if (!server_version_at_least(client, [2, 6, 11])) return next(name);

    client3.psubscribe(['abc*']);
    client3.subscribe(['xyz']);
    client3.unsubscribe(['xyz']);
    client2.publish(['abcd', 'something']);
    client3.subscribe(['xyz'], with_timeout(name, (err, [results]) {
      next(name);
    }, 2000));
  });

        dunit.test("SUBSCRIBE_QUIT",() {
          var name = "SUBSCRIBE_QUIT";
            client3.onEnd.listen((_) {
                next(name);
            });
            client3.onSubscribe.listen((redis.PubSubMsg msg) {
                client3.quit(null);
            });
            client3.subscribe(["chan3"]);
        });

  dunit.test("SUBSCRIBE_CLOSE_RESUBSCRIBE",() {
            var name = "SUBSCRIBE_CLOSE_RESUBSCRIBE";
            redis.RedisClient c1 = redis.createClient();
            redis.RedisClient c2 = redis.createClient();
            var count = 0;

            /* Create two clients. c1 subscribes to two channels, c2 will publish to them.
               c2 publishes the first message.
               c1 gets the message and drops its connection. It must resubscribe itself.
               When it resubscribes, c2 publishes the second message, on the same channel
               c1 gets the message and drops its connection. It must resubscribe itself, again.
               When it resubscribes, c2 publishes the third message, on the second channel
               c1 gets the message and drops its connection. When it reconnects, the test ends.
            */

            c1.onMessage.listen((redis.MessageMsg msg) {
              var channel = msg.channel;
              var message = msg.message;
                if (channel == /* === */"chan1") {
                    dunit.strictEqual(message, "hi on channel 1");
                    c1.stream.close();//end();

                } else if (channel == /* === */"chan2") {
                    dunit.strictEqual(message, "hi on channel 2");
                    c1.stream.close();//.end();

                } else {
                    c1.quit(null);
                    c2.quit(null);
                    dunit.fail("test failed");
                }
            });

            c1.subscribe(["chan1", "chan2"]);

            c2.once("ready", (_) {
                js.console.log("c2 is ready");
                c1.onReady.listen((err/*,  results*/) {
                    js.console.log("c1 is ready", count);

                    count++;
                    if (count == 1) {
                        c2.publish(["chan1", "hi on channel 1"]);
                        return;

                    } else if (count == 2) {
                        c2.publish(["chan2", "hi on channel 2"]);

                    } else {
                        c1.quit([],(_,[__]) {
                            c2.quit([],(_,[__]) {
                                next(name);
                            });
                        });
                    }
                });

                c2.publish(["chan1", "hi on channel 1"]);

            });
        });

  dunit.test("EXISTS", () {
    var name = "EXISTS";
    client.del(["foo", "foo2"], require_number_any(name));
    client.set(["foo", "bar"], require_string("OK", name));
    client.EXISTS(["foo"], require_number(1, name));
    client.EXISTS(["foo2"], last(name, require_number(0, name)));
  });

  dunit.test("DEL", () {
    var name = "DEL";
    client.DEL(["delkey"], require_number_any(name));
    client.set(["delkey", "delvalue"], require_string("OK", name));
    client.DEL(["delkey"], require_number(1, name));
    client.exists(["delkey"], require_number(0, name));
    client.DEL(["delkey"], require_number(0, name));
    client.mset(["delkey", "delvalue", "delkey2", "delvalue2"], require_string("OK", name));
    client.DEL(["delkey", "delkey2"], last(name, require_number(2, name)));
  });

  dunit.test("TYPE", () {
    var name = "TYPE";
    client.set(["string key", "should be a string"], require_string("OK", name));
    client.rpush(["list key", "should be a list"], require_number_pos(name));
    client.sadd(["set key", "should be a set"], require_number_any(name));
    client.zadd(["zset key", "10.0", "should be a zset"], require_number_any(name));
    client.hset(["hash key", "hashtest", "should be a hash"], require_number_any(name));

    client.TYPE(["string key"], require_string("string", name));
    client.TYPE(["list key"], require_string("list", name));
    client.TYPE(["set key"], require_string("set", name));
    client.TYPE(["zset key"], require_string("zset", name));
    client.TYPE(["not here yet"], require_string("none", name));
    client.TYPE(["hash key"], last(name, require_string("hash", name)));
  });

  dunit.test("KEYS", () {
    var name = "KEYS";
    client.mset(["test keys 1", "test val 1", "test keys 2", "test val 2"], require_string("OK", name));
    client.KEYS(["test keys*"], (err, [results]) {
      dunit.strictEqual(null, err, "result sent back unexpected error: $err");
      dunit.strictEqual(2, results.length, name);
      dunit.ok(results.indexOf("test keys 1") != -1);
      dunit.ok(results.indexOf("test keys 2") != -1);
      next(name);
    });
  });

  dunit.test("MULTIBULK", () {
    var name = "MULTIBULK";
    var keys_values = [];
    var rnd = new Random();
    for (var i = 0; i < 200; i++) {
      List<int> rndA = [];

      for (var ii = 0; ii < 256; ii++) {
        rndA.add(rnd.nextInt(255));
      }
      var key_value = ["multibulk:" + crypto.CryptoUtils.bytesToHex(rndA)/*crypto.randomBytes(256).toString("hex")*/, // use long strings as keys to ensure generation of large packet
        "test val $i"];
      keys_values.add(key_value);
    }

    client.mset(keys_values.reduce((a, b) {
      List tmp = new List.from(a);
      tmp.addAll(b);
      return tmp;
    }), require_string("OK", name));

    client.KEYS(["multibulk:*"], (err, [results]) {
      dunit.strictEqual(null, err, "result sent back unexpected error: $err");
      var tmp = new List.from(keys_values.map((val) {
        return val[0];
      }));
      tmp.sort();
      results.sort();
      dunit.deepEqual(tmp, results, name);
    });

    next(name);
  });

  dunit.test("MULTIBULK_ZERO_LENGTH", () {
    var name = "MULTIBULK_ZERO_LENGTH";
    client.KEYS(['users:*'], (err, [results]) {
      dunit.strictEqual(null, err, 'error on empty multibulk reply');
      dunit.strictEqual(true, is_empty_array(results), "not an empty array");
      next(name);
    });
  });

  dunit.test("RANDOMKEY", () {
    var name = "RANDOMKEY";
    client.mset(["test keys 1", "test val 1", "test keys 2", "test val 2"], require_string("OK", name));
    client.RANDOMKEY([], (err, [results]) {
      dunit.strictEqual(null, err, "$name result sent back unexpected error: $err");
      dunit.strictEqual(true, new RegExp("\\w+").hasMatch(results), name);
      next(name);
    });
  });

  dunit.test("RENAME", () {
    var name = "RENAME";
    client.set(['foo', 'bar'], require_string("OK", name));
    client.RENAME(["foo", "new foo"], require_string("OK", name));
    client.exists(["foo"], require_number(0, name));
    client.exists(["new foo"], last(name, require_number(1, name)));
  });

  dunit.test("RENAMENX", () {
    var name = "RENAMENX";
    client.set(['foo', 'bar'], require_string("OK", name));
    client.set(['foo2', 'bar2'], require_string("OK", name));
    client.RENAMENX(["foo", "foo2"], require_number(0, name));
    client.exists(["foo"], require_number(1, name));
    client.exists(["foo2"], require_number(1, name));
    client.del(["foo2"], require_number(1, name));
    client.RENAMENX(["foo", "foo2"], require_number(1, name));
    client.exists(["foo"], require_number(0, name));
    client.exists(["foo2"], last(name, require_number(1, name)));
  });

  dunit.test("DBSIZE", () {
    var name = "DBSIZE";
    client.set(['foo', 'bar'], require_string("OK", name));
    client.DBSIZE([], last(name, require_number_pos("DBSIZE")));
  });

  dunit.test("GET_1", () {
    var name = "GET_1";
    client.set(["get key", "get val"], require_string("OK", name));
    client.GET(["get key"], last(name, require_string("get val", name)));
  });

  dunit.test("GET_2", () {
    var name = "GET_2";

    // tests handling of non-existent keys
    client.GET(['this_key_shouldnt_exist'], last(name, require_null(name)));
  });

  dunit.test("SET", () {
    var name = "SET";
    client.SET(["set key", "set val"], require_string("OK", name));
    client.get(["set key"], last(name, require_string("set val", name)));
    client.SET(["set key", null], require_error(name));
  });

  dunit.test("GETSET", () {
    var name = "GETSET";
    client.set(["getset key", "getset val"], require_string("OK", name));
    client.GETSET(["getset key", "new getset val"], require_string("getset val", name));
    client.get(["getset key"], last(name, require_string("new getset val", name)));
  });

  dunit.test("MGET", () {
    var name = "MGET";
    client.mset(["mget keys 1", "mget val 1", "mget keys 2", "mget val 2", "mget keys 3", "mget val 3"], require_string("OK", name));
    client.MGET(["mget keys 1", "mget keys 2", "mget keys 3"], (err, [results]) {
      dunit.strictEqual(null, err, "result sent back unexpected error: $err");
      dunit.strictEqual(3, results.length, name);
      dunit.strictEqual("mget val 1", results[0].toString(), name);
      dunit.strictEqual("mget val 2", results[1].toString(), name);
      dunit.strictEqual("mget val 3", results[2].toString(), name);
    });
    client.MGET(["mget keys 1", "mget keys 2", "mget keys 3"], (err, [results]) {
      dunit.strictEqual(null, err, "result sent back unexpected error: $err");
      dunit.strictEqual(3, results.length, name);
      dunit.strictEqual("mget val 1", results[0].toString(), name);
      dunit.strictEqual("mget val 2", results[1].toString(), name);
      dunit.strictEqual("mget val 3", results[2].toString(), name);
    });
    client.MGET(["mget keys 1", "some random shit", "mget keys 2", "mget keys 3"], (err, [results]) {
      dunit.strictEqual(null, err, "result sent back unexpected error: $err");
      dunit.strictEqual(4, results.length, name);
      dunit.strictEqual("mget val 1", results[0].toString(), name);
      dunit.strictEqual(null, results[1], name);
      dunit.strictEqual("mget val 2", results[2].toString(), name);
      dunit.strictEqual("mget val 3", results[3].toString(), name);
      next(name);
    });
  });

  dunit.test("SETNX", () {
    var name = "SETNX";
    client.set(["setnx key", "setnx value"], require_string("OK", name));
    client.SETNX(["setnx key", "new setnx value"], require_number(0, name));
    client.del(["setnx key"], require_number(1, name));
    client.exists(["setnx key"], require_number(0, name));
    client.SETNX(["setnx key", "new setnx value"], require_number(1, name));
    client.exists(["setnx key"], last(name, require_number(1, name)));
  });

  dunit.test("SETEX", () {
    var name = "SETEX";
    client.SETEX(["setex key", "100", "setex val"], require_string("OK", name));
    client.exists(["setex key"], require_number(1, name));
    client.ttl(["setex key"], last(name, require_number_pos(name)));
    client.SETEX(["setex key", "100", null], require_error(name));
  });

  dunit.test("MSETNX", () {
    var name = "MSETNX";
    client.mset(["mset1", "val1", "mset2", "val2", "mset3", "val3"], require_string("OK", name));
    client.MSETNX(["mset3", "val3", "mset4", "val4"], require_number(0, name));
    client.del(["mset3"], require_number(1, name));
    client.MSETNX(["mset3", "val3", "mset4", "val4"], require_number(1, name));
    client.exists(["mset3"], require_number(1, name));
    client.exists(["mset4"], last(name, require_number(1, name)));
  });

  dunit.test("HGETALL", () {
    var name = "HGETALL";
    client.hmset(["hosts", "mjr", "1", "another", "23", "home", "1234"], require_string("OK", name));
    client.HGETALL(["hosts"], (err, [obj]) {
      dunit.strictEqual(null, err, name + " result sent back unexpected error: $err");
      dunit.strictEqual(3, obj.keys.length, name);
      dunit.strictEqual("1", obj["mjr"].toString(), name);
      dunit.strictEqual("23", obj["another"].toString(), name);
      dunit.strictEqual("1234", obj["home"].toString(), name);
      next(name);
    });
  });

  dunit.test("HGETALL_MESSAGE", () {
    var name = "HGETALL_MESSAGE";
    client.hmset(["msg_test", {
        "message": "hello"
      }], require_string("OK", name));
    client.hgetall(["msg_test"], (err, [obj]) {
      dunit.strictEqual(null, err, "$name result sent back unexpected error: $err");
      dunit.strictEqual(1, obj.keys.length, name);
      dunit.strictEqual(obj["message"], "hello");
      next(name);
    });
  });

  dunit.test("HGETALL_NULL", () {
    var name = "HGETALL_NULL";

    client.hgetall(["missing"], (err, [obj]) {
      dunit.strictEqual(null, err);
      dunit.strictEqual(null, obj);
      next(name);
    });
  });
    dunit.test("UTF8",() {
        var name = "UTF8",
            utf8_sample = "ಠ_ಠ";

        client.set(["utf8test", utf8_sample], require_string("OK", name));
        client.get(["utf8test"],  (err, [obj]) {
            dunit.strictEqual(null, err);
            dunit.strictEqual(utf8_sample, obj);
            next(name);
        });
    });

  // Set tests were adapted from Brian Hammond's redis-node-client.js, which has a comprehensive test suite

  dunit.test("SADD", () {
    var name = "SADD";

    client.del(['set0']);
    client.SADD(['set0', 'member0'], require_number(1, name));
    client.sadd(['set0', 'member0'], last(name, require_number(0, name)));
  });

  dunit.test("SADD2", () {
    var name = "SADD2";

    client.del(["set0"]);
    client.sadd(["set0", ["member0", "member1", "member2"]], require_number(3, name));
    client.smembers(["set0"], (err, [res]) {
      dunit.strictEqual(res.length, 3);
      dunit.ok(res.indexOf("member0") != -1);
      dunit.ok(res.indexOf("member1") != -1);
      dunit.ok(res.indexOf("member2") != -1);
    });
    client.SADD(["set1", ["member0", "member1", "member2"]], require_number(3, name));
    client.smembers(["set1"], (err, [res]) {
      dunit.strictEqual(res.length, 3);
      dunit.ok(res.indexOf("member0") != -1);
      dunit.ok(res.indexOf("member1") != -1);
      dunit.ok(res.indexOf("member2") != -1);
      next(name);
    });
  });

  dunit.test("SISMEMBER", () {
    var name = "SISMEMBER";

    client.del(['set0']);
    client.sadd(['set0', 'member0'], require_number(1, name));
    client.sismember(['set0', 'member0'], require_number(1, name));
    client.sismember(['set0', 'member1'], last(name, require_number(0, name)));
  });

  dunit.test("SCARD", () {
    var name = "SCARD";

    client.del(['set0']);
    client.sadd(['set0', 'member0'], require_number(1, name));
    client.scard(['set0'], require_number(1, name));
    client.sadd(['set0', 'member1'], require_number(1, name));
    client.scard(['set0'], last(name, require_number(2, name)));
  });

  dunit.test("SREM", () {
    var name = "SREM";

    client.del(['set0']);
    client.sadd(['set0', 'member0'], require_number(1, name));
    client.srem(['set0', 'foobar'], require_number(0, name));
    client.srem(['set0', 'member0'], require_number(1, name));
    client.scard(['set0'], last(name, require_number(0, name)));
  });


  dunit.test("SREM2", () {
    var name = "SREM2";
    client.del(["set0"]);
    client.sadd(["set0", ["member0", "member1", "member2"]], require_number(3, name));
    client.SREM(["set0", ["member1", "member2"]], require_number(2, name));
    client.smembers(["set0"], (err, [res]) {
      dunit.strictEqual(res.length, 1);
      dunit.ok(res.indexOf("member0") != -1);
    });
    client.sadd(["set0", ["member3", "member4", "member5"]], require_number(3, name));
    client.srem(["set0", ["member0", "member6"]], require_number(1, name));
    client.smembers(["set0"], (err, [res]) {
      dunit.strictEqual(res.length, 3);
      dunit.ok(res.indexOf("member3") != -1);
      dunit.ok(res.indexOf("member4") != -1);
      dunit.ok(res.indexOf("member5") != -1);
      next(name);
    });
  });

  dunit.test("SPOP", () {
    var name = "SPOP";

    client.del(['zzz']);
    client.sadd(['zzz', 'member0'], require_number(1, name));
    client.scard(['zzz'], require_number(1, name));

    client.spop(['zzz'], (err, [value]) {
      if (err != null) {
        dunit.fail(err);
      }
      dunit.equal(value, 'member0', name);
    });

    client.scard(['zzz'], last(name, require_number(0, name)));
  });

  dunit.test("SDIFF", () {
    var name = "SDIFF";

    client.del(['foo']);
    client.sadd(['foo', 'x'], require_number(1, name));
    client.sadd(['foo', 'a'], require_number(1, name));
    client.sadd(['foo', 'b'], require_number(1, name));
    client.sadd(['foo', 'c'], require_number(1, name));

    client.sadd(['bar', 'c'], require_number(1, name));

    client.sadd(['baz', 'a'], require_number(1, name));
    client.sadd(['baz', 'd'], require_number(1, name));

    client.sdiff(['foo', 'bar', 'baz'], (err, [values]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      values.sort();
      dunit.equal(values.length, 2, name);
      dunit.equal(values[0], 'b', name);
      dunit.equal(values[1], 'x', name);
      next(name);
    });
  });

  dunit.test("SDIFFSTORE", () {
    var name = "SDIFFSTORE";

    client.del(['foo']);
    client.del(['bar']);
    client.del(['baz']);
    client.del(['quux']);

    client.sadd(['foo', 'x'], require_number(1, name));
    client.sadd(['foo', 'a'], require_number(1, name));
    client.sadd(['foo', 'b'], require_number(1, name));
    client.sadd(['foo', 'c'], require_number(1, name));

    client.sadd(['bar', 'c'], require_number(1, name));

    client.sadd(['baz', 'a'], require_number(1, name));
    client.sadd(['baz', 'd'], require_number(1, name));

    // NB: SDIFFSTORE returns the number of elements in the dstkey

    client.sdiffstore(['quux', 'foo', 'bar', 'baz'], require_number(2, name));

    client.smembers(['quux'], (err, [values]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      var members = buffers_to_strings(values);
      members.sort();

      dunit.deepEqual(members, ['b', 'x'], name);
      next(name);
    });
  });

  dunit.test("SMEMBERS", () {
    var name = "SMEMBERS";

    client.del(['foo']);
    client.sadd(['foo', 'x'], require_number(1, name));

    client.smembers(['foo'], (err, [members]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.deepEqual(buffers_to_strings(members), ['x'], name);
    });

    client.sadd(['foo', 'y'], require_number(1, name));

    client.smembers(['foo'], (err, [values]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.equal(values.length, 2, name);
      var members = buffers_to_strings(values);
      members.sort();

      dunit.deepEqual(members, ['x', 'y'], name);
      next(name);
    });
  });

  dunit.test("SMOVE", () {
    var name = "SMOVE";

    client.del(['foo']);
    client.del(['bar']);

    client.sadd(['foo', 'x'], require_number(1, name));
    client.smove(['foo', 'bar', 'x'], require_number(1, name));
    client.sismember(['foo', 'x'], require_number(0, name));
    client.sismember(['bar', 'x'], require_number(1, name));
    client.smove(['foo', 'bar', 'x'], last(name, require_number(0, name)));
  });

  dunit.test("SINTER", () {
    var name = "SINTER";

    client.del(['sa']);
    client.del(['sb']);
    client.del(['sc']);

    client.sadd(['sa', 'a'], require_number(1, name));
    client.sadd(['sa', 'b'], require_number(1, name));
    client.sadd(['sa', 'c'], require_number(1, name));

    client.sadd(['sb', 'b'], require_number(1, name));
    client.sadd(['sb', 'c'], require_number(1, name));
    client.sadd(['sb', 'd'], require_number(1, name));

    client.sadd(['sc', 'c'], require_number(1, name));
    client.sadd(['sc', 'd'], require_number(1, name));
    client.sadd(['sc', 'e'], require_number(1, name));

    client.sinter(['sa', 'sb'], (err, [intersection]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.equal(intersection.length, 2, name);
      var tmp = buffers_to_strings(intersection);
      tmp.sort();
      dunit.deepEqual(tmp, ['b', 'c'], name);
    });

    client.sinter(['sb', 'sc'], (err, [intersection]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.equal(intersection.length, 2, name);
      var tmp = buffers_to_strings(intersection);
      tmp.sort();
      dunit.deepEqual(tmp, ['c', 'd'], name);
    });

    client.sinter(['sa', 'sc'], (err, [intersection]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.equal(intersection.length, 1, name);
      dunit.equal(intersection[0], 'c', name);
    });

    // 3-way

    client.sinter(['sa', 'sb', 'sc'], (err, [intersection]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.equal(intersection.length, 1, name);
      dunit.equal(intersection[0], 'c', name);
      next(name);
    });
  });

  dunit.test("SINTERSTORE", () {
    var name = "SINTERSTORE";

    client.del(['sa']);
    client.del(['sb']);
    client.del(['sc']);
    client.del(['foo']);

    client.sadd(['sa', 'a'], require_number(1, name));
    client.sadd(['sa', 'b'], require_number(1, name));
    client.sadd(['sa', 'c'], require_number(1, name));

    client.sadd(['sb', 'b'], require_number(1, name));
    client.sadd(['sb', 'c'], require_number(1, name));
    client.sadd(['sb', 'd'], require_number(1, name));

    client.sadd(['sc', 'c'], require_number(1, name));
    client.sadd(['sc', 'd'], require_number(1, name));
    client.sadd(['sc', 'e'], require_number(1, name));

    client.sinterstore(['foo', 'sa', 'sb', 'sc'], require_number(1, name));

    client.smembers(['foo'], (err, [members]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.deepEqual(buffers_to_strings(members), ['c'], name);
      next(name);
    });
  });

  dunit.test("SUNION", () {
    var name = "SUNION";

    client.del(['sa']);
    client.del(['sb']);
    client.del(['sc']);

    client.sadd(['sa', 'a'], require_number(1, name));
    client.sadd(['sa', 'b'], require_number(1, name));
    client.sadd(['sa', 'c'], require_number(1, name));

    client.sadd(['sb', 'b'], require_number(1, name));
    client.sadd(['sb', 'c'], require_number(1, name));
    client.sadd(['sb', 'd'], require_number(1, name));

    client.sadd(['sc', 'c'], require_number(1, name));
    client.sadd(['sc', 'd'], require_number(1, name));
    client.sadd(['sc', 'e'], require_number(1, name));

    client.sunion(['sa', 'sb', 'sc'], (err, [union]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      var tmp = buffers_to_strings(union);
      tmp.sort();
      dunit.deepEqual(tmp, ['a', 'b', 'c', 'd', 'e'], name);
      next(name);
    });
  });

  dunit.test("SUNIONSTORE", () {
    var name = "SUNIONSTORE";

    client.del(['sa']);
    client.del(['sb']);
    client.del(['sc']);
    client.del(['foo']);

    client.sadd(['sa', 'a'], require_number(1, name));
    client.sadd(['sa', 'b'], require_number(1, name));
    client.sadd(['sa', 'c'], require_number(1, name));

    client.sadd(['sb', 'b'], require_number(1, name));
    client.sadd(['sb', 'c'], require_number(1, name));
    client.sadd(['sb', 'd'], require_number(1, name));

    client.sadd(['sc', 'c'], require_number(1, name));
    client.sadd(['sc', 'd'], require_number(1, name));
    client.sadd(['sc', 'e'], require_number(1, name));

    client.sunionstore(['foo', 'sa', 'sb', 'sc'], (err, [cardinality]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.equal(cardinality, 5, name);
    });

    client.smembers(['foo'], (err, [members]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.equal(members.length, 5, name);
      var tmp = buffers_to_strings(members);
      tmp.sort();
      dunit.deepEqual(tmp, ['a', 'b', 'c', 'd', 'e'], name);
      next(name);
    });
  });

  // SORT test adapted from Brian Hammond's redis-node-client.js, which has a comprehensive test suite

  dunit.test("SORT", () {
    var name = "SORT";

    client.del(['y']);
    client.del(['x']);

    client.rpush(['y', 'd'], require_number(1, name));
    client.rpush(['y', 'b'], require_number(2, name));
    client.rpush(['y', 'a'], require_number(3, name));
    client.rpush(['y', 'c'], require_number(4, name));

    client.rpush(['x', '3'], require_number(1, name));
    client.rpush(['x', '9'], require_number(2, name));
    client.rpush(['x', '2'], require_number(3, name));
    client.rpush(['x', '4'], require_number(4, name));

    client.set(['w3', '4'], require_string("OK", name));
    client.set(['w9', '5'], require_string("OK", name));
    client.set(['w2', '12'], require_string("OK", name));
    client.set(['w4', '6'], require_string("OK", name));

    client.set(['o2', 'buz'], require_string("OK", name));
    client.set(['o3', 'foo'], require_string("OK", name));
    client.set(['o4', 'baz'], require_string("OK", name));
    client.set(['o9', 'bar'], require_string("OK", name));

    client.set(['p2', 'qux'], require_string("OK", name));
    client.set(['p3', 'bux'], require_string("OK", name));
    client.set(['p4', 'lux'], require_string("OK", name));
    client.set(['p9', 'tux'], require_string("OK", name));

    // Now the data has been setup, we can test.

    // But first, test basic sorting.

    // y = [ d b a c ]
    // sort y ascending = [ a b c d ]
    // sort y descending = [ d c b a ]

    client.sort(['y', 'asc', 'alpha'], (err, [sorted]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.deepEqual(buffers_to_strings(sorted), ['a', 'b', 'c', 'd'], name);
    });

    client.sort(['y', 'desc', 'alpha'], (err, [sorted]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.deepEqual(buffers_to_strings(sorted), ['d', 'c', 'b', 'a'], name);
    });

    // Now try sorting numbers in a list.
    // x = [ 3, 9, 2, 4 ]

    client.sort(['x', 'asc'], (err, [sorted]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      //ORIGINAL: Values convert to string [2, 3, 4, 9]
      dunit.deepEqual(buffers_to_strings(sorted), ["2", "3", "4", "9"], name);
    });

    client.sort(['x', 'desc'], (err, [sorted]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      //ORIGINAL: Values convert to string [9, 4, 3, 2]
      dunit.deepEqual(buffers_to_strings(sorted), ["9", "4", "3", "2"], name);
    });

    // Try sorting with a 'by' pattern.

    client.sort(['x', 'by', 'w*', 'asc'], (err, [sorted]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      //ORIGINAL: Values convert to string [3, 9, 4, 2]
      dunit.deepEqual(buffers_to_strings(sorted), ["3", "9", "4", "2"], name);
    });

    // Try sorting with a 'by' pattern and 1 'get' pattern.

    client.sort(['x', 'by', 'w*', 'asc', 'get', 'o*'], (err, [sorted]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.deepEqual(buffers_to_strings(sorted), ['foo', 'bar', 'baz', 'buz'], name);
    });

    // Try sorting with a 'by' pattern and 2 'get' patterns.

    client.sort(['x', 'by', 'w*', 'asc', 'get', 'o*', 'get', 'p*'], (err, [sorted]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.deepEqual(buffers_to_strings(sorted), ['foo', 'bux', 'bar', 'tux', 'baz', 'lux', 'buz', 'qux'], name);
    });

    // Try sorting with a 'by' pattern and 2 'get' patterns.
    // Instead of getting back the sorted set/list, store the values to a list.
    // Then check that the values are there in the expected order.

    client.sort(['x', 'by', 'w*', 'asc', 'get', 'o*', 'get', 'p*', 'store', 'bacon'], (err, [_]) {
      if (err != null) {
        dunit.fail(err, name);
      }
    });

    client.lrange(['bacon', 0, -1], (err, [values]) {
      if (err != null) {
        dunit.fail(err, name);
      }
      dunit.deepEqual(buffers_to_strings(values), ['foo', 'bux', 'bar', 'tux', 'baz', 'lux', 'buz', 'qux'], name);
      next(name);
    });

    // TODO - sort by hash value
  });

  dunit.test("MONITOR", () {
    var name = "MONITOR";
    List responses = [];

    if (!server_version_at_least(client, [2, 6, 0])) {
      js.console.log("Skipping " + name + " for old Redis server version < 2.6.x");
      return next(name);
    }

    redis.RedisClient monitor_client = redis.createClient();
    monitor_client.monitor(null, (err, [res]) {
      client.mget(["some", "keys", "foo", "bar"]);
      client.set(["json", JSON.encode({
          "foo": "123",
          "bar": "sdflkdfsjk",
          "another": false
        })]);
    });
    monitor_client.on("monitor", (redis.MonitorMsg msg) {
      var time = msg.time;
      var args = msg.args.toList();
      // skip monitor command for Redis <= 2.4.16
      if (args[0] == /* === */"monitor") return;

      responses.add(args);
      if (responses.length == /* === */2) {
        dunit.strictEqual(5, responses[0].length);
        dunit.strictEqual("mget", responses[0][0]);
        dunit.strictEqual("some", responses[0][1]);
        dunit.strictEqual("keys", responses[0][2]);
        dunit.strictEqual("foo", responses[0][3]);
        dunit.strictEqual("bar", responses[0][4]);
        dunit.strictEqual(3, responses[1].length);
        dunit.strictEqual("set", responses[1][0]);
        dunit.strictEqual("json", responses[1][1]);
        dunit.strictEqual('{"foo":"123","bar":"sdflkdfsjk","another":false}', responses[1][2]);
        monitor_client.quit(null, (err, [res]) {
          next(name);
        });
      }
    });
  });

  dunit.test("BLPOP", () {
    var name = "BLPOP";

    client.rpush(["blocking list", "initial value"], (err, [res]) {
      client2.BLPOP(["blocking list", 0], (err, [res]) {
        dunit.strictEqual("blocking list", res[0].toString());
        dunit.strictEqual("initial value", res[1].toString());

        client.rpush(["blocking list", "wait for this value"]);
      });
      client2.BLPOP(["blocking list", 0], (err, [res]) {
        dunit.strictEqual("blocking list", res[0].toString());
        dunit.strictEqual("wait for this value", res[1].toString());
        next(name);
      });
    });
  });

  dunit.test("BLPOP_TIMEOUT", () {
    var name = "BLPOP_TIMEOUT";

    // try to BLPOP the list again, which should be empty.  This should timeout and return null.
    client2.BLPOP(["blocking list", 1], (err, [res]) {
      if (err != null) {
        throw err;
      }

      dunit.strictEqual(res, null);
      next(name);
    });
  });

  dunit.test("EXPIRE", () {
    var name = "EXPIRE";
    client.set(['expiry key', 'bar'], require_string("OK", name));
    client.EXPIRE(["expiry key", "1"], require_number_pos(name));
    new Timer(new Duration(milliseconds: 2000), () {
      client.exists(["expiry key"], last(name, require_number(0, name)));
    });
  });

  dunit.test("TTL", () {
    var name = "TTL";
    client.set(["ttl key", "ttl val"], require_string("OK", name));
    client.expire(["ttl key", "100"], require_number_pos(name));
    new Timer(new Duration(milliseconds: 500), () {
      client.TTL(["ttl key"], last(name, require_number_pos(/*0,*/ name)));
    });
  });

  dunit.test("OPTIONAL_CALLBACK", () {
    var name = "OPTIONAL_CALLBACK";
    client.del(["op_cb1"]);
    client.set(["op_cb1", "x"]);
    client.get(["op_cb1"], last(name, require_string("x", name)));
  });

  dunit.test("OPTIONAL_CALLBACK_UNDEFINED", () {
    var name = "OPTIONAL_CALLBACK_UNDEFINED";
    client.del(["op_cb2"]);
    client.set(["op_cb2", "y"], null/*undefined*/);
    client.get(["op_cb2"], last(name, require_string("y", name)));
    client.set(["op_cb_undefined", null/*undefined*/, null/*undefined*/]);
  });

  dunit.test("ENABLE_OFFLINE_QUEUE_TRUE", () {
    var name = "ENABLE_OFFLINE_QUEUE_TRUE";
    var cli = redis.createClient(9999, null, new redis.RedisClientOptions(max_attempts: 1// default :)
    // enable_offline_queue: true
    ));
    cli.on('error', (e) {
      // ignore, b/c expecting a "can't connect" error
    });
    return new Timer(new Duration(milliseconds: 50), () {
      cli.set([name, name], (err, [result]) {
        dunit.ifError(err);
      });

      return new Timer(new Duration(milliseconds: 25), () {
        dunit.strictEqual(cli.offline_queue.length, 1);
        return next(name);
      });
    });
  });

  /*TODO: skip ENABLE_OFFLINE_QUEUE_FALSE
        dunit.test("ENABLE_OFFLINE_QUEUE_FALSE",() {
            var name = "ENABLE_OFFLINE_QUEUE_FALSE";
            var cli = redis.createClient(9999, null, new redis.RedisClientOptions(
                max_attempts: 1,
                enable_offline_queue: false
            ));
            cli.on('error', (_) {
                // ignore, see above
            });
            dunit.throws( (_) {
                cli.set([name, name]);
            });
            dunit.doesNotThrow( () {
                cli.set([name, name],  (err,[__]) {
                    // should callback with an error
                    dunit.ok(err);
                    new Timer(new Duration(milliseconds: 50),  () {
                        next(name);
                    });
                });
            });
        });*/

  dunit.test("SLOWLOG", () {
    var name = "SLOWLOG";
    client.config(["set", "slowlog-log-slower-than", 0], require_string("OK", name));
    client.slowlog(["reset"], require_string("OK", name));
    client.set(["foo", "bar"], require_string("OK", name));
    client.get(["foo"], require_string("bar", name));
    client.slowlog(["get"], (err, [res]) {
      dunit.equal(res.length, 3, name);
      dunit.equal(res[0][3].length, 2, name);
      dunit.deepEqual(res[1][3], ["set", "foo", "bar"], name);
      dunit.deepEqual(res[2][3], ["slowlog", "reset"], name);
      client.config(["set", "slowlog-log-slower-than", 10000], require_string("OK", name));
      next(name);
    });
  });

  /*TODO: skip DOMAIN
        dunit.test("DOMAIN",() {
            var name = "DOMAIN";

            var domain;
            try {
                domain = require('domain').create();
            } catch (err) {
                js.console.log("Skipping " + name + " because this version of node doesn't have domains.");
                next(name);
            }

            if (domain) {
                domain.run( () {
                    client.set(['domain', 'value'],  (err, [res]) {
                        dunit.ok(process.domain);
                        var notFound = res.not.existing.thing; // ohhh nooooo
                    });
                });

                // this is the expected and desired behavior
                domain.on('error',  (err) { next(name); });
            }
        });*/

  // TODO - need a better way to test auth, maybe auto-config a local Redis server or something.
  // Yes, this is the real password.  Please be nice, thanks.
  dunit.test("auth", () {
    var name = "AUTH";
    var ready_count = 0;

    redis.RedisClient client4 = redis.createClient(9006, "filefish.redistogo.com");
    client4.auth("664b1b6aaf134e1ec281945a8de702a9", (err, [res]) {
      dunit.strictEqual(null, err, name);
      dunit.strictEqual("OK", res.toString(), name);
    });

    // test auth, then kill the connection so it'll auto-reconnect and auto-re-auth
    client4.onReady.listen((_) {
      ready_count++;
      if (ready_count == /* === */1) {
        client4.stream.close();//.destroy();
      } else {
        client4.quit(null, (err, [res]) {
          next(name);
        });
      }
    });
  });

  dunit.test("auth2", () {
    var name = "AUTH2",
        client4,
        ready_count = 0;

    client4 = redis.createClient(9006, "filefish.redistogo.com", new redis.RedisClientOptions(auth_pass: "664b1b6aaf134e1ec281945a8de702a9"));

    // test auth, then kill the connection so it'll auto-reconnect and auto-re-auth
    client4.on("ready", (_) {
      ready_count++;
      if (ready_count == /* === */1) {
        client4.stream.close();
      } else {
        client4.quit(null, (err, [res]) {
          next(name);
        });
      }
    });
  });

  dunit.test("reconnectRetryMaxDelay", () {
    var time = new DateTime.now();
    var name = 'reconnectRetryMaxDelay',
        reconnecting = false;
    var client = redis.createClient(PORT, HOST, new redis.RedisClientOptions(retry_max_delay: 1));
    client.on('ready', (_) {
      if (!reconnecting) {
        reconnecting = true;
        client.retry_delay = 1000;
        client.retry_backoff = 1.0;
        client.stream.close();//end();
      } else {
        client.end();
        var lasted = new DateTime.now().millisecondsSinceEpoch - time.millisecondsSinceEpoch;
        dunit.ok(lasted < 1000);
        next(name);
      }
    });
  });

  //TODO:Uncomment
  /*dunit.test("unref",() {
            var name = "unref";
            var external = fork("./test-unref.js");
            var done = false;
            external.on("close",  (code) {
                assert(code == 0, "test-unref.js failed");
                done = true;
            });
            new Timer(new Duration(milliseconds: 500),  () {
                if (!done) {
                    external.kill();
                }
                assert(done, "test-unref.js didn't finish in time.");
                next(name);
            });
        });*/

  all_tests = new Queue.from(dunit.getTests());
  all_start = new DateTime.now();
  test_count = 0;

  client.once("ready", (_) {
    js.console.log("Connected to ${client.host}:${client.port}, Redis server version ${client.server_info["redis_version"]}\n");
    js.console.log("Using reply parser ${client.reply_parser.name}");

    run_next_test();

    connected = true;
  });

  client.on('end', (_) {
    ended = true;
  });

  // Exit immediately on connection failure, which triggers "exit", below, which fails the test
  client.on("error", (err) {
    js.console.error("client: ${err.stackTrace}");
    exit(1);
    //process.exit();
  });
  client2.on("error", (err) {
    js.console.error("client2: ${err.stackTrace}");
    exit(1);
    //process.exit();
  });
  client3.on("error", (err) {
    js.console.error("client3: ${err.stackTrace}");
    exit(1);
    //process.exit();
  });
  bclient.on("error", (err) {
    js.console.error("bclient: ${err.stackTrace}");
    exit(1);
    //process.exit();
  });

  client.on("reconnecting", (redis.ReconnectingParams params) {
    js.console.log("reconnecting: $params");
  });

  /*process.on('uncaughtException',  (err) {
            js.console.error("Uncaught exception: " + err.stack);
            process.exit(1);
        });*/
  /*
        process.on('exit',  (code) {
            dunit.equal(true, connected);
            dunit.equal(true, ended);
        });*/
}
