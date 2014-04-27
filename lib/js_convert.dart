library js.convert;

bool isValueTrueObj(Object value){
  return value!=null;
}
bool isValueTrueBool(bool value){
  return value!=null && value==true;
}
bool isValueTrueStr(String value){
  return (value!=null && value!="");
}
bool isValueTrueNum(int value){
  return (value!=null && value!=0);
}

bool isNaN(dynamic value){
  return !(value is num);
}

bool isBool(dynamic value){
  return value is bool;
}
bool isFunction(dynamic value){
  return value is Function;
}
bool isString(dynamic value){
  return value is String;
}
bool isNumber(dynamic value){
  return value is num;
}
bool isObject(dynamic value){
  return value is Object;
}

bool isMap(dynamic value){
  return value is Map;
}

class Error implements Exception{
  /**
   * A message describing
   */
  final String message;

  /**
   * Creates a new FormatException with an optional error [message].
   */
  const Error([this.message = ""]);

  String toString() => "Error: $message";
}

class console{
  static void log(a1,[a2="",a3="",a4="",a5="",a6=""]){
    print("$a1 $a2 $a3 $a4 $a5 $a6");
  }
  static void warn(a1,[a2="",a3="",a4="",a5="",a6=""]){
    print("warn:$a1 $a2 $a3 $a4 $a5 $a6");
  }
  static void error(a1,[a2="",a3="",a4="",a5="",a6=""]){
      print("error:$a1 $a2 $a3 $a4 $a5 $a6");
  }
}

class Array{
  static bool isArray(obj){
    return obj is List;
  }
}

// typeof command_obj.callback === "function" => isFunction(command_obj.callback)
// +options.connect_timeout; => int.parse(options.connect_timeout);
// value === undefined => value == null
// typeof this.options.enable_offline_queue === "boolean" => this.options.enable_offline_queue is bool
// typeof command => command.runtimeType