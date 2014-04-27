part of dart_redis;

class RedisState{
  bool monitoring;
  bool pub_sub_mode;
  int selected_db;
  RedisState({this.monitoring,this.pub_sub_mode, this.selected_db});
}
