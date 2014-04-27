part of dart_redis;

class Command {
  String command;
  List args;
  bool sub_command;
  bool buffer_args;
  RedisCallback callback;
  // This Command constructor is ever so slightly faster than using an object literal, but more importantly, using
  // a named constructor helps it show up meaningfully in the V8 CPU profiler and in heap snapshots.
  Command(command, args, sub_command, buffer_args, callback) {
    this.command = command;
    this.args = args;
    this.sub_command = sub_command;
    this.buffer_args = buffer_args;
    this.callback = callback;
  }

  toString() => "$command $args";
}
