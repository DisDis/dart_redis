part of dart_redis;

class RedisClientOptions {
  bool socket_nodelay;
  int command_queue_high_water;
  int command_queue_low_water;
  int max_attempts;
  int connect_timeout;
  bool enable_offline_queue;
  int retry_max_delay;
  String auth_pass;
  bool no_ready_check;
  bool detect_buffers;
  bool return_buffers;
  BaseParser parser;
  RedisClientOptions({bool this.socket_nodelay:true, int this.command_queue_high_water:1000, int this.command_queue_low_water:0,
    int this.max_attempts:0, int this.connect_timeout:0, bool this.enable_offline_queue:true,
    int this.retry_max_delay:0, var this.auth_pass,
    bool this.no_ready_check:false, bool this.detect_buffers:false, bool this.return_buffers:false, BaseParser this.parser}) {
    if (parser == null) {
      parser = new ReplyParser(new ParserSettings(return_buffers: return_buffers,debug_mode: debug_mode));
      if (debug_mode) {
        console.log("Using default parser module: ${parser.name}");
      }
    }
  }
}
