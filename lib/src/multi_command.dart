part of dart_redis;

class MultiCommand {
  final String command;
  final List args;
  final RedisCallback callback;
  MultiCommand(this.command, [this.args, this.callback]);

  toString() => "$command $args";
}
