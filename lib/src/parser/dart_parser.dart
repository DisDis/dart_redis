part of dart_redis;

//var events = require("events"),
//    util   = require("../util");

class IncompleteReadBuffer implements js.Error {
  /**
   * A message describing
   */
  final String message;
  
  /**
   * Creates a new FormatException with an optional error [message].
   */
  const IncompleteReadBuffer([this.message = ""]);

  String toString() => "Error: $message";
}
//util.inherits(IncompleteReadBuffer, Error);

class Packet {
  final int type;
  final int size;
  Packet(int this.type, int this.size);
}

class EmptyObject {
  toString() => "!EMPTY_OBJECT!";
}

class ReplyParser extends BaseParser {
  final EmptyObject _emptyObject = new EmptyObject();
  final String name = "dart";
  String _encoding;
  int _offset;
  bool _debug_mode;
  Uint8List _buffer;
  ParserSettings options;

  Stream get onError => _error.stream;
  Stream<RedisReply> get onReply => _reply.stream;
  StreamController _error = new StreamController.broadcast();
  StreamController<RedisReply> _reply = new StreamController.broadcast();

  ReplyParser(ParserSettings options) {
    this.options = options;

    this._buffer = null;
    this._offset = 0;
    this._encoding = "utf-8";
    this._debug_mode = options.debug_mode;
    //this._reply_type = null;
  }

  BaseParser createInstance(ParserSettings settings) {
    return new ReplyParser(settings);
  }

  //util.inherits(ReplyParser, events.EventEmitter);
  //exports.Parser = ReplyParser;



  _parseResult(int type) {
    switch (type) {
      case 43:
        return _parse43and45();
      case 45: // + or -
        return _parse43and45();
      case 58: // :
        return _parse58();
      case 36: // $
        return _parse36(type);
      case 42: // *
        return _parse42(type);
    }
  }

  _parse42(int type) {
    int offset = _offset;
    Packet packetHeader = new Packet(type, parseHeader());

    if (packetHeader.size < 0) {
      return null;
    }

    if (packetHeader.size > _bytesRemaining()) {
      _offset = offset - 1;
      throw new IncompleteReadBuffer("Wait for more data.");
    }

    var reply = [];
    offset = this._offset - 1;

    for (var i = 0; i < packetHeader.size; i++) {
      int ntype = this._buffer[this._offset++];

      if (this._offset > this._buffer.length) {
        throw new IncompleteReadBuffer("Wait for more data.");
      }
      var res = this._parseResult(ntype);
      if (identical(res, _emptyObject)/* res == undefined*/) {
        res = null;
      }
      reply.add/*.push*/(res);
    }

    return reply;
  }

  _parse36(int type) {
    // set a rewind point, as the packet could be larger than the
    // buffer in memory
    int offset = _offset - 1;

    Packet packetHeader = new Packet(type, parseHeader());

    // packets with a size of -1 are considered null
    if (packetHeader.size /* === */ == -1) {
      return _emptyObject;
      /*undefined;*/
    }

    int end = _offset + packetHeader.size;
    int start = _offset;

    // set the offset to after the delimiter
    _offset = end + 2;

    if (end > this._buffer.length) {
      this._offset = offset;
      throw new IncompleteReadBuffer("Wait for more data.");
    }

    var _outBuffer = new Uint8List.view(_buffer.buffer, start, end - start);
    if (options.return_buffers) {
      return _outBuffer;//this._buffer.slice(start, end);
    } else {
      return bufferToString(_outBuffer);
      //return this._buffer.toString(this._encoding, start, end);
    }
  }

  _parse58() {
    // up to the delimiter
    int end = _packetEndOffset() - 1;
    int start = _offset;

    // include the delimiter
    this._offset = end + 2;

    if (end > this._buffer.length) {
      this._offset = start;
      throw new IncompleteReadBuffer("Wait for more data.");
    }

    var _outBuffer = new Uint8List.view(_buffer.buffer, start, end - start);
    if (options.return_buffers) {
      return _outBuffer;//this._buffer.slice(start, end);
    }
    // return the coerced numeric value
    return int.parse(bufferToString(_outBuffer));
  }

  _parse43and45() {

    // up to the delimiter
    int end = _packetEndOffset() - 1;
    int start = _offset;

    // include the delimiter
    _offset = end + 2;

    if (end > _buffer.length) {
      _offset = start;
      throw new IncompleteReadBuffer("Wait for more data.");
    }

    var _outBuffer = new Uint8List.view(_buffer.buffer, start, end - start);
    if (options.return_buffers) {
      return _outBuffer;//this._buffer.slice(start, end);
    } else {
      return bufferToString(_outBuffer);
    }
  }

  execute(Uint8List buffer) {
    _append(buffer);

    while (true) {
      int offset = _offset;
      try {
        // at least 4 bytes: :1\r\n
        if (_bytesRemaining() < 4) {
          break;
        }

        int type = _buffer[_offset++];

        switch (type) {

          case 43: // +
            var ret = _parseResult(type);

            if (ret == null) {
              return;
            }
            send_reply(ret);
            break;
          case 45: // -
            var ret = _parseResult(type);

            if (ret == null) {
              return;
            }

            send_error(ret);
            break;
          case 58: // :
            var ret = _parseResult(type);

            if (ret == null) {
              return;
            }

            send_reply(ret);
            break;
          case 36:// $
            var ret = _parseResult(type);

            if (ret /* === */ == null) {
              return;
            }

            // check the state for what is the result of
            // a -1, set it back up for a null reply

            if (identical(_emptyObject, ret) /*ret == undefined*/ ) {
              ret = null;
            }

            send_reply(ret);
            break;
          case 42: // *
            // set a rewind point. if a failure occurs,
            // wait for the next execute()/append() and try again
            offset = _offset - 1;

            var ret = _parseResult(type);

            send_reply(ret);
            break;
        }
      } on IncompleteReadBuffer catch (e) {
        _offset = offset;
        break;
      } catch (err) {
        // catch the error (not enough data), rewind, and wait
        // for the next packet to appear
        throw err;
      }
    }
  }

  _append(Uint8List newBuffer) {
    if (newBuffer == null) {
      return;
    }

    // first run
    if (_buffer /* === */ == null) {
      _buffer = newBuffer;
      return;
    }

    // out of data
    if (_offset >= _buffer.length) {
      _buffer = newBuffer;
      _offset = 0;

      return;
    }

    // very large packet
    // check for concat, if we have it, use it
    if (_buffer.length - 1 < _offset) {
      _buffer = newBuffer;
    } else {
      var oldLen = _buffer.length - _offset;
      var _tmp = new Uint8List(oldLen + newBuffer.length);
      _tmp.setRange(0, oldLen, _buffer.skip(_offset));
      _tmp.setRange(oldLen, _tmp.length, newBuffer);
      _buffer = _tmp;
    }

    _offset = 0;
  }

  int parseHeader() {
    var end = this._packetEndOffset();
    var valueBuff = new Uint8List.view(_buffer.buffer, _offset, end - 1 - _offset);
    var value =  new String.fromCharCodes(valueBuff); //bufferToString(valueBuff);
    this._offset = end + 1;
    return int.parse(value);
  }

  _packetEndOffset() {
    var offset = this._offset;

    while (this._buffer[offset] != 0x0d && this._buffer[offset + 1] != 0x0a) {
      offset++;
      if (offset >= this._buffer.length) {
        throw new IncompleteReadBuffer("didn't see LF after NL reading multi bulk count ($offset => ${_buffer.length}, $_offset)");
      }
    }

    offset++;
    return offset;
  }

  _bytesRemaining() {
    return (_buffer.length - _offset) < 0 ? 0 : (_buffer.length - _offset);
  }

  parser_error(message) {
    //this.emit("error", message);
    _error.add(message);
  }

  send_error(reply) {
    //this.emit("reply error", reply);
    _reply.add(new RedisReply(true, reply));
  }

  send_reply(reply) {
    //this.emit("reply", reply);
    _reply.add(new RedisReply(false, reply));
  }
}
