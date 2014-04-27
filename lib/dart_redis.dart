library dart_redis;
import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import "js_convert.dart" as js;
import "js_convert.dart" show console, Array;
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

part "src/gen/RedisClient.dart";
part "src/gen/Multi.dart";
part "src/parser/dart_parser.dart";
part 'src/redis_state.dart';
part 'src/message_msg.dart';
part 'src/p_message_msg.dart';
part 'src/base_parser.dart';
part 'src/multi.dart';
part 'src/command.dart';
part 'src/multi_command.dart';
part 'src/redis_client_options.dart';

const int default_port = 6379;
const String default_host = "127.0.0.1";
RegExp _regExpNOSCRIPT = new RegExp("NOSCRIPT");


Uint8List stringToBuffer(String text) => //new Uint8List.fromList(text.codeUnits);
   new Uint8List.fromList(UTF8.encode(text));
  
String bufferToString(List<int> data) => //new String.fromCharCodes(data);
  UTF8.decode(data);

// can set this to true to enable for all connections
bool debug_mode = false;

//var arraySlice = Array.prototype.slice
trace([a1, a2, a3, a4, a5, a6, a7, a8]) {
  if (!debug_mode) return;
  console.log(a1, a2, a3, a4, a5, a6);
}

class PubSubMsg {
  final String channel;
  final int count;
  PubSubMsg(String this.channel, int this.count);
}

class ReconnectingParams {
  final int delay;
  final int attempt;
  ReconnectingParams({int this.delay, int this.attempt});
  toString()=>"{ delay:$delay, attempt:$attempt }";
}

class MonitorMsg {
  final time;
  final Iterable args;
  MonitorMsg(this.time, Iterable this.args);
}

class RedisClient extends _RedisClient {
  static int _connection_id = 0;
  static final Logger _log = new Logger("RedisClient");
  int connection_id;
  bool emitted_end;
  bool connected;
  bool ready;
  int connections;
  bool enable_offline_queue;
  int retry_max_delay;
  int commands_sent;
  int connect_timeout;
  int max_attempts;
  bool pub_sub_mode;
  final Queue<Command> command_queue = new Queue(); // holds sent commands to de-pipeline them
  final Queue<Command> offline_queue = new Queue(); // holds commands issued but not able to be sent
  int attempts;
  Timer retry_timer;
  int retry_totaltime;
  int retry_delay;
  double retry_backoff;
  bool should_buffer;
  int command_queue_high_water;
  int command_queue_low_water;
  Set subscription_set = new Set();
  bool monitoring;
  bool closing;
  Map server_info;
  var auth_pass;
  bool send_anyway;
  String host;
  int port;
  int selected_db;
  RawSocket stream;
  RedisClientOptions options;
  RedisCallback auth_callback;
  BaseParser reply_parser;

  StreamController _connect = new StreamController.broadcast();
  Stream get onConnect => _connect.stream;
  StreamController<js.Error> _error = new StreamController.broadcast();
  Stream<js.Error> get onError => _error.stream;
  StreamController _end = new StreamController.broadcast();
  Stream get onEnd => _end.stream;
  StreamController _drain = new StreamController.broadcast();
  Stream get onDrain => _drain.stream;
  StreamController _ready = new StreamController.broadcast();
  Stream get onReady => _ready.stream;
  StreamController<ReconnectingParams> _reconnecting = new StreamController.broadcast();
  Stream<ReconnectingParams> get onReconnecting => _reconnecting.stream;
  StreamController _idle = new StreamController.broadcast();
  Stream get onIdle => _idle.stream;
  StreamController<MonitorMsg> _monitor = new StreamController.broadcast();
  Stream<MonitorMsg> get onMonitor => _monitor.stream;

  StreamController<PubSubMsg> _psubscribe = new StreamController.broadcast();
  Stream<PubSubMsg> get onPsubscribe => _psubscribe.stream;
  StreamController _punsubscribe = new StreamController.broadcast();
  Stream<PubSubMsg> get onPunsubscribe => _punsubscribe.stream;

  StreamController<PubSubMsg> _subscribe = new StreamController.broadcast();
  Stream<PubSubMsg> get onSubscribe => _subscribe.stream;
  StreamController<PubSubMsg> _unsubscribe = new StreamController.broadcast();
  Stream<PubSubMsg> get onUnsubscribe => _unsubscribe.stream;

  StreamController<MessageMsg> _message = new StreamController<MessageMsg>.broadcast();
  Stream<MessageMsg> get onMessage => _message.stream;
  StreamController<PMessageMsg> _pmessage = new StreamController<PMessageMsg>.broadcast();
  Stream<PMessageMsg> get onPMessage => _pmessage.stream;

  RedisState old_state;
  BaseParser parser_module;

  static bool isBuffer(value) {
    return (value is Uint8List)/* || (value is List<int>)*/;
  }

  StreamController _getStreamController(String streamName) {
    switch (streamName) {
      case "psubscribe":
        return _psubscribe;
      case "punsubscribe":
        return _punsubscribe;
      case "subscribe":
        return _subscribe;
      case "unsubscribe":
        return _unsubscribe;
      case "message":
        return _message;
      case "pmessage":
        return _pmessage;
      case "error":
        return _error;
      case "ready":
        return _ready;
      case "end":
        return _end;
      case "reconnecting":
        return _reconnecting;
      case "connect":
        return _connect;
      case "monitor":
        return _monitor;
      case "idle":
        return _idle;
    }
    throw new Exception("not found '$streamName' stream");
  }

  StreamSubscription on(String streamName, void onData(event)) {
    return _getStreamController(streamName).stream.listen(onData);
  }

  Future once(String streamName, dynamic onData(event)) {
    return _getStreamController(streamName).stream.first.then(onData);
  }

  RedisClient(Future<RawSocket> stream, RedisClientOptions options) {
    if (options == null) {
      options = new RedisClientOptions();
    }
    emitted_end = false;
    send_anyway = false;
    this.options = options;
    this.connection_id = ++_connection_id;
    this.connected = false;
    this.ready = false;
    this.connections = 0;
    this.should_buffer = false;
    this.command_queue_high_water = options.command_queue_high_water;
    this.command_queue_low_water = options.command_queue_low_water;
    this.max_attempts = options.max_attempts;
    this.commands_sent = 0;
    this.connect_timeout = options.connect_timeout;
    this.enable_offline_queue = this.options.enable_offline_queue;
    this.retry_max_delay = options.retry_max_delay;

    this.initialize_retry_vars();
    this.pub_sub_mode = false;
    //     this.subscription_set = {};
    this.monitoring = false;
    this.closing = false;
    this.server_info = {};
    this.auth_pass = options.auth_pass;
    this.parser_module = null;
    this.selected_db = null; // save the selected db here, used when reconnecting

    this.old_state = null;


    /*this.stream.on("connect", () {
         self._on_connect();
     });*/

    /*this.stream.on("data", (buffer_from_socket) {
         self._on_data(buffer_from_socket);
     });*/

    //TODO: Implement
    /*this.stream.on("error", (msg) {
         _on_error(msg.message);
     });*/

    /*this.stream.on("close", () {
         self._connection_gone("close");
     });*/

    /*this.stream.on("end", () {
         self._connection_gone("end");
     });*/

    /*this.stream.on("drain", () {
         self.should_buffer = false;
         self.emit("drain");
     });*/
    onDrain.listen((_) {
      should_buffer = false;
      //_drain.add(null);
    });

    stream.then(_initSocket).catchError((error) => _on_error(error.toString()));

    //events.EventEmitter.call(this);
  }

  _initSocket(RawSocket socketStream) {
    this.stream = socketStream;
    _on_connect(null);
    socketStream.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.READ) {
        _on_data(socketStream.read());
      }
      /* else if (event == RawSocketEvent.CLOSED) {
        if (debug_mode){
          print("close : RawSocketEvent.CLOSED");
        }
        _connection_gone("close");
      } else if (event == RawSocketEvent.READ_CLOSED) {
        if (debug_mode){
          print("End : RawSocketEvent.READ_CLOSED");
        }
        _connection_gone("close");
      }*/
    }, onError: (err) {
      _on_error(err.toString());
    }, onDone: () {
      _connection_gone("end");
    });
  }

  initialize_retry_vars() {
    retry_timer = null;
    retry_totaltime = 0;
    retry_delay = 150;
    retry_backoff = 1.7;
    attempts = 1;
  }

  unref() {
    trace("User requesting to unref the connection");
    if (this.connected) {
      trace("unref'ing the socket connection");
      //this.stream.unref();
      stream.shutdown(SocketDirection.BOTH);
      //this.stream.destroy();
    } else {
      trace("Not connected yet, will unref later");
      this.once("connect", (_) {
        this.unref();
      });
    }
  }

  // flush offline_queue and command_queue, erroring any items with a callback first
  flush_and_error(message) {
    var error = new js.Error(message);

    while (offline_queue.length > 0) {
      var command_obj = offline_queue.removeFirst();
      if (command_obj.callback!=null) {
        try {
          command_obj.callback(error);
        } catch (callback_err) {
          _error.add(callback_err);
        }
      }
    }
    offline_queue.clear();

    while (command_queue.length > 0) {
      var command_obj = this.command_queue.removeFirst();
      if (command_obj.callback!=null) {
        try {
          command_obj.callback(error);
        } catch (callback_err) {
          _error.add(callback_err);
        }
      }
    }
    this.command_queue.clear();
  }

  _on_error(msg) {
    var message = "Redis connection to $host:$port failed - $msg";

    if (this.closing) {
      return;
    }

    if (debug_mode) {
      console.warn(message);
    }

    this.flush_and_error(message);

    this.connected = false;
    this.ready = false;

    _error.add(new js.Error(message));
    // "error" events get turned into exceptions if they aren't listened for.  If the user handled this error
    // then we should try to reconnect.
    this._connection_gone("error");
  }

  do_auth() {
    if (debug_mode) {
      console.log("Sending auth to $host:$port id $connection_id");
    }
    send_anyway = true;
    send_command("auth", [this.auth_pass], (err, [res]) {
      if (err != null) {
        if (err.toString().match("LOADING")) {
          // if redis is still loading the db, it will not authenticate and everything else will fail
          console.log("Redis still loading, trying to authenticate later");
          // TODO - magic number alert*/
          new Timer(new Duration(milliseconds: 2000), do_auth);
          return;
        } else if (err.toString().match("no password is set")) {
          console.log("Warning: Redis server does not require a password, but a password was supplied.");
          err = null;
          res = "OK";
        } else {
          _error.add(new js.Error("Auth error: ${err.message}"));// self.emit("error", new js.Error("Auth error: ${err.message}"));
          return;
        }
      }
      if (res.toString() != "OK") {//if (res.toString() !== "OK") {
        _error.add(new js.Error("Auth failed: $res"));
        return;
      }
      if (debug_mode) {
        console.log("Auth succeeded $host:$port id $connection_id");
      }
      if (auth_callback != null) {
        auth_callback(err, res);
        auth_callback = null;
      }

      // now we are really connected
      //self.emit("connect");
      _connect.add(null);
      initialize_retry_vars();

      if (js.isValueTrueBool(options.no_ready_check)) {
        on_ready();
      } else {
        ready_check();
      }
    });
    send_anyway = false;
  }

  _on_connect(_) {
    if (debug_mode) {
      console.log("Stream connected $host:$port id $connection_id");
    }

    this.connected = true;
    this.ready = false;
    this.connections += 1;
    this.command_queue.clear();
    this.emitted_end = false;
    if (this.options.socket_nodelay) {
      if (this.stream.setOption(SocketOption.TCP_NODELAY, true) == false) {
        print("setNoDelay not set!");
      }
    }
    //TODO: release setTimeout
    //this.stream.setTimeout(0);
    if (debug_mode) {
      print("not implement this.stream.setTimeout(0)");
    }

    init_parser();

    if (this.auth_pass != null) {
      do_auth();
    } else {
      _connect.add(null);
      initialize_retry_vars();

      if (options.no_ready_check) {
        on_ready();
      } else {
        ready_check();
      }
    }
  }

  init_parser() {
    parser_module = options.parser;
    if (debug_mode) {
      console.log("Using parser module: ${parser_module.name}");
    }

    this.parser_module.debug_mode = debug_mode;
    // return_buffers sends back Buffers from parser to callback. detect_buffers sends back Buffers from parser, but
    // converts to Strings if the input arguments are not Buffers.
    var return_buffers = (options.return_buffers != null && options.return_buffers) || (options.detect_buffers != null && options.detect_buffers);
    this.reply_parser = //*new this.parser_module.Parser({
    parser_module.createInstance(new ParserSettings(return_buffers: return_buffers));

    // "reply error" is an error sent back by Redis
    this.reply_parser.onReply.listen(/*on("reply",*/ (RedisReply reply) {
      if (reply.isError) {
        if (/*reply instanceof Error*/ reply is js.Error) {
          return_error(reply.data);
        } else {
          return_error(new js.Error(reply.data));
        }
      } else {
        return_reply(reply.data);
      }
    });
    // "error" is bad.  Somehow the parser got confused.  It'll try to reset and continue.
    reply_parser.onError.listen(/*on("error", */(err) {
      _error.add(new js.Error("Redis reply parser error: ${err.stack}"));
    });
  }

  on_ready() {
    ready = true;

    if (old_state != null) {
      monitoring = old_state.monitoring;
      pub_sub_mode = old_state.pub_sub_mode;
      selected_db = old_state.selected_db;
      old_state = null;
    }

    // magically restore any modal commands from a previous connection
    if (this.selected_db /* !== null */ != null) {
      // this trick works if and only if the following send_command
      // never goes into the offline queue
      var pub_sub_mode = this.pub_sub_mode;
      this.pub_sub_mode = false;
      send_command('select', [selected_db]);
      this.pub_sub_mode = pub_sub_mode;
    }
    if (pub_sub_mode  == true) {
      // only emit "ready" when all subscriptions were made again
      var callback_count = 0;
      var callback = (err, [res]) {
        callback_count--;
        if (callback_count  == 0) {
          _ready.add(null);
        }
      };

      //Object.keys(this.subscription_set).forEach(
      subscription_set.forEach((key) {
        var parts = key.split(" ");
        if (debug_mode) {
          console.warn("sending pub/sub on_ready " + parts[0] + ", " + parts[1]);
        }
        callback_count++;
        send_command(parts[0] + "scribe", [parts[1]], callback);
      });
      return;
    } else if (monitoring) {
      this.send_command("monitor");
    } else {
      this.send_offline_queue();
    }
    _ready.add(null);
  }

  on_info_cmd(err, res) {
    var self = this;
    Map obj = {};
    List<String> lines;

    if (err != null) {
      _error.add(new js.Error("Ready check failed: ${err.message}"));
      return;
    }


    if (options.return_buffers != null && options.return_buffers) {
      lines = bufferToString(res).split("\r\n");
    } else {
      lines = res.toString().split("\r\n");
    }

    lines.forEach((line) {
      var parts = line.split(':');
      if (parts.length > 1 && js.isValueTrueStr(parts[1])) {
        obj[parts[0]] = parts[1];
      }
    });

    obj["versions"] = [];
    if (obj["redis_version"] != null) {
      obj["redis_version"].split('.').forEach((num) {
        obj["versions"].add/*.push*/(/*+num*/ int.parse(num));
      });
    }

    // expose info key/vals to users
    this.server_info = obj;

    if ((obj["loading"] != null && obj["loading"]  == "0")) {
      if (debug_mode) {
        console.log("Redis server ready.");
      }
      on_ready();
    } else {
      var retry_time = int.parse(obj["loading_eta_seconds"]) * 1000;
      if (retry_time > 1000) {
        retry_time = 1000;
      }
      if (debug_mode) {
        console.log("Redis server still loading, trying again in $retry_time");
      }
      new Timer(new Duration(milliseconds: retry_time), ready_check);
    }
  }

  ready_check() {
    if (debug_mode) {
      console.log("checking server ready state...");
    }

    this.send_anyway = true; // secret flag to send_command to send something even if not "ready"
    this.info(null, (err, [res]) {
      on_info_cmd(err, res);
    });
    this.send_anyway = false;
  }

  send_offline_queue() {
    int buffered_writes = 0;

    Command command_obj;
    while (this.offline_queue.length > 0) {
      command_obj = this.offline_queue.removeFirst();
      /*shift();*/
      if (debug_mode) {
        console.log("Sending offline command: ${command_obj.command}");
      }
      //TODO:uncomment
      //buffered_writes += !this.send_command(command_obj.command, command_obj.args, command_obj.callback);
      if (send_command(command_obj.command, command_obj.args, command_obj.callback) == 0) {
        buffered_writes++;
      }
    }
    this.offline_queue.clear();// = new Queue();
    // Even though items were shifted off, Queue backing store still uses memory until next add, so just get a new Queue

    if (!js.isValueTrueNum(buffered_writes)) {
      this.should_buffer = false;
      //this.emit("drain");
      _drain.add(null);
    }
  }

  _connection_gone(String why) {

    // If a retry is already in progress, just let that happen
    if (retry_timer != null) {
      return;
    }

    if (debug_mode) {
      console.warn("Redis connection is gone from $why event.");
    }
    connected = false;
    ready = false;

    if (this.old_state  == null) {
      var state = new RedisState(monitoring: this.monitoring, pub_sub_mode: this.pub_sub_mode, selected_db: this.selected_db);
      old_state = state;
      monitoring = false;
      pub_sub_mode = false;
      selected_db = null;
    }

    // since we are collapsing end and close, users don't expect to be called twice
    if (!emitted_end) {
      _end.add(null);
      emitted_end = true;
    }

    flush_and_error("Redis connection gone from $why event.");

    // If this is a requested shutdown, then don't retry
    if (closing) {
      retry_timer = null;
      if (debug_mode) {
        console.warn("connection ended from quit command, not retrying.");
      }
      return;
    }

    var nextDelay = (retry_delay * retry_backoff).floor();
    if (retry_max_delay >0 && nextDelay > retry_max_delay) {
      retry_delay = this.retry_max_delay;
    } else {
      retry_delay = nextDelay;
    }

    if (debug_mode) {
      console.log("Retry connection in $retry_delay ms");
    }

    if (max_attempts>0 && attempts >= max_attempts) {
      retry_timer = null;
      // TODO - some people need a "Redis is Broken mode" for future commands that errors immediately, and others
      // want the program to exit.  Right now, we just log, which doesn't really help in either case.
      console.error("dart_redis: Couldn't get Redis connection after $max_attempts  attempts.");
      return;
    }

    attempts += 1;
    _reconnecting.add(new ReconnectingParams(delay: retry_delay, attempt: attempts));
    retry_timer = new Timer(new Duration(milliseconds: retry_delay), () {
      if (debug_mode) {
        console.log("Retrying connection...");
      }

      retry_totaltime += retry_delay;

      if (connect_timeout > 0 && retry_totaltime >= connect_timeout) {
        retry_timer = null;
        // TODO - engage Redis is Broken mode for future commands, or whatever
        console.error("dart_redis: Couldn't get Redis connection after $retry_totaltime ms.");
        return;
      }

      //TODO: added events
      RawSocket.connect(host, port)//self.stream.connect(self.port, self.host);
      .then((socket) {
        _initSocket(socket);
        retry_timer = null;
      }).catchError((error) => _on_error(error.toString()));
    });
  }

  _on_data(Uint8List data) {
    if (debug_mode) {
      try {
        console.log("net read $host:$port id $connection_id : ${bufferToString(data)}");
      } catch (_) {
        console.log("net read $host:$port id $connection_id : ${data}");
      }
    }

    try {
      this.reply_parser.execute(data);
    } catch (err) {
      // This is an unexpected parser problem, an exception that came from the parser code itself.
      // Parser should emit "error" events if it notices things are out of whack.
      // Callbacks that throw exceptions will land in return_reply(), below.
      // TODO - it might be nice to have a different "error" event for different types of errors
      _error.add(err);
      //this.emit("error", err);
    }
  }

  return_error(err) {
    int queue_len = command_queue.length;
    Command command_obj;
    if (queue_len>0){
     command_obj = command_queue.removeFirst();
     queue_len--;
    }

    if (this.pub_sub_mode  == false && queue_len  == 0) {
      _idle.add(null);
    }
    if (this.should_buffer && queue_len <= command_queue_low_water) {
      _drain.add(null);
      this.should_buffer = false;
    }

    if (command_obj != null && command_obj.callback!=null) {
      try {
        command_obj.callback(err);
      } catch (callback_err) {
        _error.add(callback_err);
      }
    } else {
      console.log("dart_redis: no callback to send error: ${err.message}");
      _error.add(err);
    }
  }

  return_reply(reply) {
    String type;
    Command command_obj;
    // If the "reply" here is actually a message received asynchronously due to a
    // pubsub subscription, don't pop the command queue as we'll only be consuming
    // the head command prematurely.
    if (Array.isArray(reply) && reply.length > 0 && ((reply[0] is num && js.isValueTrueNum(reply[0])) || (reply[0] is String && js.isValueTrueStr(reply[0])))) {
      type = reply[0].toString();
    }

    if (this.pub_sub_mode && (type == 'message' || type == 'pmessage')) {
      trace("received pubsub message");
    } else {
      if (command_queue.length > 0) {
        command_obj = command_queue.removeFirst();
      }
    }

    int queue_len = command_queue.length;

    if (pub_sub_mode  == false && queue_len  == 0) {
      //this.command_queue = new Queue();  // explicitly reclaim storage from old Queue
      //this.emit("idle");
      _idle.add(null);
    }
    if (should_buffer && queue_len <= command_queue_low_water) {
      //this.emit("drain");
      _drain.add(null);
      should_buffer = false;
    }

    if (command_obj != null && !command_obj.sub_command) {
      if (command_obj.callback != null) {
        if (options.detect_buffers && command_obj.buffer_args  == false) {
          // If detect_buffers option was specified, then the reply from the parser will be Buffers.
          // If this command did not use Buffer arguments, then convert the reply to Strings here.
          reply = reply_to_strings(reply);
        }

        // TODO - confusing and error-prone that hgetall is special cased in two places
        if (js.isValueTrueObj(reply) && 'hgetall'  == command_obj.command.toLowerCase() && reply is List) {
          reply = reply_to_object(reply);
        }

        try_callback(command_obj.callback, reply);
      } else if (debug_mode) {
        console.log("no callback for reply: $reply");
      }
    } else if (this.pub_sub_mode || (js.isValueTrueObj(command_obj) && js.isValueTrueObj(command_obj.sub_command))) {
      if (Array.isArray(reply)) {
        type = reply[0].toString();
        if (type  == "message") {
          _message.add(new MessageMsg(reply[1].toString(), reply[2]));
        } else if (type  == "pmessage") {
          _pmessage.add(new PMessageMsg(reply[1].toString(), reply[2].toString(), reply[3]));
        } else if (type  == "subscribe" || type  == "unsubscribe" || type  == "psubscribe" || type  == "punsubscribe") {
          if (reply[2]  == 0) {
            pub_sub_mode = false;
            if (debug_mode) {
              console.log("All subscriptions removed, exiting pub/sub mode");
            }
          } else {
            pub_sub_mode = true;
          }
          // subscribe commands take an optional callback and also emit an event, but only the first response is included in the callback
          // TODO - document this or fix it so it works in a more obvious way
          // reply[1] can be null
          var reply1String = (reply[1]  == null) ? null : reply[1].toString();
          if (command_obj != null && command_obj.callback != null) {
            try_callback(command_obj.callback, reply1String);
          }
          _getStreamController(type).add(new PubSubMsg(reply1String, reply[2]));
        } else {
          throw new js.Error("subscriptions are active but got unknown reply type $type");
        }
      } else if (!this.closing) {
        throw new js.Error("subscriptions are active but got an invalid reply: $reply");
      }
    } else if (this.monitoring) {
      int len = reply.indexOf(" ");
      double timestamp = double.parse(reply.substring(0, len));
      int argindex = reply.indexOf('"');
      var args = reply.substring(argindex + 1, reply.length - 1).split('" "').map((String elem) {
        return elem.replaceAll('\\"', '"');
      });
      _monitor.add(new MonitorMsg(timestamp, args));
    } else {
      throw new js.Error("dart_redis command queue state error. If you can reproduce this, please report it.");
    }
  }

  send_command(String command, [List args, RedisCallback callback]) {
    var arg;
    int buffered_writes = 0;
    RawSocket stream = this.stream;

    if (args == null) {
      args = [];
    }
    //FIXME: replace domain
    //if (callback && process.domain) callback = process.domain.bind(callback);

    // if the last argument is an array and command is sadd or srem, expand it out:
    //     client.sadd(arg1, [arg2, arg3, arg4], cb);
    //  converts to:
    //     client.sadd(arg1, arg2, arg3, arg4, cb);
    var lcaseCommand = command.toLowerCase();
    if ((lcaseCommand  == 'sadd' || lcaseCommand  == 'srem') && args.length > 0 && Array.isArray(args[args.length - 1])) {
      args.addAll(args.removeLast());
    }

    // if the value is undefined or null and command is set or setx, need not to send message to redis
    if (command  == 'set' || command  == 'setex') {
      if (args[args.length - 1] == null) {
        var err = new js.Error('send_command: $command value must not be undefined or null');
        if (callback != null) {
          return callback(err);
        } else {
          return null;
        }
      }
    }

    bool buffer_args = false;
    for (int i = 0,
        il = args.length; i < il; i += 1) {
      //FIXME: Correct check buffer
      //if (Buffer.isBuffer(args[i])) {
      if (isBuffer(args[i])) {
        buffer_args = true;
        break;
      }
    }

    Command command_obj = new Command(command, args, false, buffer_args, callback);

    //TODO:stream.writable
    if ((!ready && !send_anyway) /*|| !stream.writeEventsEnabled*/ /*!stream.writable*/) {
      if (debug_mode) {
        //TODO:stream.writable
        /*if (!stream.writeEventsEnabled/*!stream.writable*/) {
                console.log("send command: stream is not writeable.");
            }*/
      }

      if (enable_offline_queue) {
        if (debug_mode) {
          console.log("Queueing " + command + " for next server connection.");
        }
        offline_queue.add(command_obj);// push(command_obj);
        should_buffer = true;
      } else {
        var not_writeable_error = new js.Error('send_command: stream not writeable. enable_offline_queue is false');
        if (command_obj.callback != null) {
          command_obj.callback(not_writeable_error);
        } else {
          throw not_writeable_error;
        }
      }

      return false;
    }

    if (command == "subscribe" || command == "psubscribe" || command == "unsubscribe" || command == "punsubscribe") {
      this.pub_sub_command(command_obj);
    } else if (command == "monitor") {
      this.monitoring = true;
    } else if (command == "quit") {
      this.closing = true;
    } else if (pub_sub_mode == true) {
      throw new js.Error("Connection in subscriber mode, only subscriber commands may be used");
    }
    command_queue.add(command_obj);//push(command_obj);
    commands_sent += 1;

    int elem_count = args.length + 1;

    // Always use "Multi bulk commands", but if passed any Buffer args, then do multiple writes, one for each arg.
    // This means that using Buffers in commands is going to be slower, so use Strings if you don't already have a Buffer.

    String command_str = "*$elem_count\r\n\$${command.length}\r\n$command\r\n";
    BytesBuilder bb = new BytesBuilder(copy: false);
    bb.add(command_str.codeUnits);
    //stream.write(command_str.codeUnits);

    if (debug_mode) {
       console.log("send $host:$port id $connection_id : $command_str");
    }

    args.forEach((item) {
      List<int> arg;
      if (item is Uint8List) {
        arg = item;
      } else {
        if (item is String){
          arg = stringToBuffer(item);
        } else{
          arg = stringToBuffer(item.toString());
        }
      }
      /*stream.write("\$${arg.length}\r\n".codeUnits);
      stream.write(arg);
      stream.write("\r\n".codeUnits);*/
      bb.add("\$${arg.length}\r\n".codeUnits);
      bb.add(arg);
      bb.add("\r\n".codeUnits);
      /*if (stream.write(bb.takeBytes()) == 0) {
         buffered_writes++;
      }*/
      if (debug_mode) {
        console.log("send_command: buffer send ${arg.length} bytes");
      }
    });
    //buffered_writes += !stream.write(command_str.toString());
    if (bb.isNotEmpty){
      if (stream.write(bb.takeBytes()) == 0) {
        buffered_writes++;
      }
    }
    

    if (debug_mode) {
      console.log("send_command buffered_writes: $buffered_writes should_buffer: $should_buffer");
    }
    if (js.isValueTrueNum(buffered_writes) || command_queue.length >= command_queue_high_water) {
      this.should_buffer = true;
    }
    return !this.should_buffer;
  }

  pub_sub_command(Command command_obj) {
    
    String key;

    if (pub_sub_mode  == false && debug_mode) {
      console.log("Entering pub/sub mode from ${command_obj.command}");
    }
    pub_sub_mode = true;
    command_obj.sub_command = true;

    String command = command_obj.command;
    List args = command_obj.args;
    if (command  == "subscribe" || command  == "psubscribe") {
      if (command  == "subscribe") {
        key = "sub";
      } else {
        key = "psub";
      }
      for (int i = 0; i < args.length; i++) {
        subscription_set.add(key + " " + args[i]);
      }
    } else {
      if (command  == "unsubscribe") {
        key = "sub";
      } else {
        key = "psub";
      }
      for (int i = 0; i < args.length; i++) {
        subscription_set.remove(key + " " + args[i]);
      }
    }
  }

  end() {
    //this.stream._events = {};
    connected = false;
    ready = false;
    closing = true;
    return stream.close();//this.stream.destroySoon();
  }

  // store db in this.select_db to restore it on reconnect
  select(int db, [RedisCallback callback]) {
    send_command('select', [db], (err, [res]) {
      if (err  == null) {
        selected_db = db;
      }
      if (callback != null) {
        callback(err, res);
      }
    });
  }
  // SELECT = select;

  // Stash auth for connect and reconnect.  Send immediately if already connected.
  auth(String pass, RedisCallback callback) {
    auth_pass = pass;
    auth_callback = callback;
    if (debug_mode) {
      console.log("Saving auth as $auth_pass");
    }

    if (connected) {
      send_command("auth", [pass], callback);
    }
  }
  // AUTH = auth;

  hmget(List args, [RedisCallback callback]) {
    if (args.length == 2 && Array.isArray(args[1])) {
      args.addAll(args.removeLast());
    }
    return send_command("hmget", args, callback);
  }
  // HMGET = hmget;

  hmset(List args, [RedisCallback callback]) {
    //  return this.send_command("hmset", args, callback);

    if (args.length  == 2 && (js.isString(args[0]) || js.isNumber(args[0]) /*typeof args[0] === "string" || typeof args[0] === "number"*/) && /*typeof args[1] === "object"*/ js.isMap(args[1])) {
      // User does: client.hmset(key, {key1: val1, key2: val2})
      // assuming key is a string, i.e. email address

      // if key is a number, i.e. timestamp, convert to string
      if (js.isNumber(args[0]) /*typeof args[0] === "number"*/) {
        args[0] = args[0].toString();
      }

      var tmp_args = [args[0]];

      args[1].forEach((k, v) {
        tmp_args.add(k);
        tmp_args.add(v);
      });

      /*tmp_keys = Object.keys(args[1]);
     for (int i = 0, il = tmp_keys.length; i < il ; i++) {
         key = tmp_keys[i];
         tmp_args/*.push*/.add(key);
         tmp_args/*.push*/.add(args[1][key]);
     }*/
      args = tmp_args;
    }

    return send_command("hmset", args, callback);
  }
  //HMSET = hmset;

  Multi multi([List<MultiCommand> args]) {
    return new Multi(this, args);
  }
  Multi MULTI([List<MultiCommand> args]) {
    return multi(args);
  }



  // hook eval with an attempt to evalsha for cached scripts
  //eval =EVAL;
  eval(List args, [RedisCallback callback]) {
    // replace script source with sha value
    var source = args[0];

    var shaC = new SHA1();
    shaC.add(source.codeUnits);
    String sha = CryptoUtils.bytesToHex(shaC.close());

    args[0] = CryptoUtils.bytesToHex(shaC.close());//crypto.createHash("sha1").update(source).digest("hex");

    evalsha(args, (err, [reply]) {
      if (err != null && _regExpNOSCRIPT.hasMatch(err.message)) {//if (err && /NOSCRIPT/.test(err.message)) {
        args[0] = source;
        eval_orig(args, callback);
      } else if (callback != null) {
        callback(err, reply);
      }
    });
  }

  eval_orig(List args, RedisCallback callback) => super.eval(args, callback);

  // if a callback throws an exception, re-throw it on a new stack so the parser can keep going.
  // if a domain is active, emit the error on the domain, which will serve the same function.
  // put this try/catch in its own because V8 doesn't optimize this well yet.
  try_callback(RedisCallback callback, reply) {
    try {
      callback(null, reply);
    } catch (err, stackTrace) {
      console.error(err, stackTrace);
      //FIXME: Uncomment
      /*if (process.domain) {
           process.domain.emit('error', err);
           process.domain.exit();
       } else {
           client.emit("error", err);
       }*/
      //TODO:Delete
      _error.add(err);
    }
  }
}



// hgetall converts its replies to an Object.  If the reply is empty, null is returned.
reply_to_object(List reply) {

  if (reply.length  == 0) {
    return null;
  }
  var obj = {};

  int jl = reply.length;
  for (int j = 0; j < jl; j += 2) {
    var keyO = reply[j];
    String key;
    if (RedisClient.isBuffer(keyO)) {
      key = bufferToString(keyO);
    } else {
      key = keyO.toString();
    }
    var val = reply[j + 1];
    obj[key] = val;
  }

  return obj;
}

reply_to_strings(reply) {
  if (RedisClient.isBuffer(reply)/* Buffer.isBuffer(reply)*/) {
    return bufferToString(reply);//reply.toString();
  }

  if (Array.isArray(reply)) {
    List<String> _temp = new List(reply.length);
    for (int i = 0; i < reply.length; i++) {
      var item = reply[i];
      if (/*reply[i] !== null  && */item /* !== undefined */ != null) {
        _temp[i] = bufferToString(item);
      }
    }
    return _temp;
  }

  return reply;
}

RedisClient createClient([int port = default_port, String host = default_host, RedisClientOptions options]) {
  if (port == null) {
    port = default_port;
  }
  if (host == null) {
    host = default_host;
  }

  var redis_client = new RedisClient(RawSocket.connect(host, port), options);
  redis_client.port = port;
  redis_client.host = host;
  return redis_client;
}
