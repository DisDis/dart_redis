part of dart_redis;


class ParserSettings{
  bool return_buffers;
  bool debug_mode;
  ParserSettings({bool this.return_buffers:false, bool this.debug_mode:false}){
  }
}


class RedisReply{
  final bool isError;
  final data;
  RedisReply(bool this.isError, this.data);
}

abstract class BaseParser{
  String name;
  bool debug_mode;
  BaseParser createInstance(ParserSettings settings);
  execute(Uint8List data);
  Stream get onError;
  Stream<RedisReply> get onReply;
}
