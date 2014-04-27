part of dart_redis;

class PMessageMsg extends MessageMsg {
  final String pattern;
  PMessageMsg(String this.pattern, String channel,String message):super(channel, message);
}
