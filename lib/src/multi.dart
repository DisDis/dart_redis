part of dart_redis;

class Multi extends _Multi {
  final RedisClient _client;
  Multi(RedisClient this._client, [List<MultiCommand> args]) {
    _queue.add(new MultiCommand("MULTI")/*[["MULTI"]]*/);
    //if (Array.isArray(args)) {
    //    this.queue = this.queue.concat(args);
    //}
    if (args != null) {
      _queue.addAll(args);
    }
  }

  Multi hmset([List args]) {
    if (args == null) {
      args = [];
    }
    var len = args.length;
    if (len >= 2 && /*typeof args[0] === "string" && typeof args[1] === "object"*/ js.isString(args[0]) && js.isMap(args[1])) {
      List tmp_args = [args[0]];
      args[1].forEach((k, v) {
        tmp_args.add(k);
        tmp_args.add(v);
      });
      /*Object.keys().map((key) {
              tmp_args/*.push*/.add(key);
              tmp_args/*.push*/.add(args[1][key]);
          });*/
      if (len > 2 && js.isValueTrueObj(args[2])) {
        tmp_args/*.push*/.add(args[2]);
      }
      args = tmp_args;
    }

    this._queue.add(new MultiCommand("hmset", args));//push(args);
    return this;
  }
  // HMSET = hmset;

  exec(RedisCallback callback) {
    var errors = [];
    // drain queue, callback will catch "QUEUED" or error
    // TODO - get rid of all of these anonymous functions which are elegant but slow
    _queue.forEach((MultiCommand currentItem/*, index */) {
      var args = currentItem.args;
      String command = currentItem.command;

      if (command.toLowerCase() /* === */ == 'hmset' && /*typeof args[1] === 'object'*/ js.isMap(args[1])) {
        Map obj = args.removeLast();//.pop();
        obj.forEach((k, v) {
          args.add(k);
          args.add(v);
        });
      }
      _client.send_command(command, args, (err, [reply]) {
        if (err != null) {
          if (currentItem.callback != null) {
            currentItem.callback(err);
          } else {
            errors/*.push*/.add(err);
          }
        }
      });
    });

    // TODO - make this callback part of Multi.prototype instead of creating it each time
    return _client.send_command("EXEC", [], (err, [replies]) {
      if (err != null) {
        if (!(err is js.Error)) {
          err = new js.Error(err);
        }
        if (callback != null) {
          errors/*.push*/.add(err);
          callback(errors);
          return;
        } else {
          throw err;
        }
      }


      if (replies != null && (((replies is num) && js.isValueTrueNum(replies)) || replies is List)) {
        //var il, reply, args;
        //              for (int i = 1, il = queue.length; i < il; i += 1) {
        int i = -1;
        _queue.forEach((item) {
          if (i == -1) {
            i++;
            return;
          }
          var reply = replies[i];
          // TODO - confusing and error-prone that hgetall is special cased in two places
          if (reply != null && item.command.toLowerCase() /* === */ == "hgetall" && reply is List) {
            replies[i] = reply = reply_to_object(reply);
          }
          if (item.callback != null) {
            item.callback(null, reply);
          }
          i++;
        });

      }

      if (callback != null) {
        callback(null, replies);
      }
    });
  }

  EXEC(RedisCallback callback) => exec(callback);
}
