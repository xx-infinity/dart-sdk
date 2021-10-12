// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// part of "core_patch.dart";

// NOTE: When making changes to this class, please also update
// `VmTarget.instantiateInvocation` and `VmTarget._invocationType` in
// `pkg/kernel/lib/target/vm.dart`.
class _InvocationMirror implements Invocation {
  // Constants describing the invocation kind.
  // _FIELD cannot be generated by regular invocation mirrors.
  static const int _UNINITIALIZED = -1;
  static const int _METHOD = 0;
  static const int _GETTER = 1;
  static const int _SETTER = 2;
  static const int _FIELD = 3;
  static const int _LOCAL_VAR = 4;
  static const int _KIND_SHIFT = 0;
  static const int _KIND_BITS = 3;
  static const int _KIND_MASK = (1 << _KIND_BITS) - 1;

  // These values, except _DYNAMIC and _SUPER, are only used when throwing
  // NoSuchMethodError for compile-time resolution failures.
  static const int _DYNAMIC = 0;
  static const int _SUPER = 1;
  static const int _STATIC = 2;
  static const int _CONSTRUCTOR = 3;
  static const int _TOP_LEVEL = 4;
  static const int _LEVEL_SHIFT = _KIND_BITS;
  static const int _LEVEL_BITS = 3;
  static const int _LEVEL_MASK = (1 << _LEVEL_BITS) - 1;

  // ArgumentsDescriptor layout. Keep in sync with enum in dart_entry.h.
  static const int _TYPE_ARGS_LEN = 0;
  static const int _COUNT = 1;
  static const int _SIZE = 2;
  static const int _POSITIONAL_COUNT = 3;
  static const int _FIRST_NAMED_ENTRY = 4;

  // Internal representation of the invocation mirror.
  String? _functionName;
  List? _argumentsDescriptor;
  List? _arguments;
  bool _isSuperInvocation = false;
  int _delayedTypeArgumentsLen = 0;

  // External representation of the invocation mirror; populated on demand.
  Symbol? _memberName;
  int _type = _UNINITIALIZED;
  List<Type>? _typeArguments;
  List? _positionalArguments;
  Map<Symbol, dynamic>? _namedArguments;

  _InvocationMirror._withType(this._memberName, int? type, this._typeArguments,
      this._positionalArguments, this._namedArguments)
      : _type = type ?? _UNINITIALIZED {
    _typeArguments ??= const <Type>[];
    _positionalArguments ??= const [];
    _namedArguments ??= const {};
  }

  void _setMemberNameAndType() {
    final funcName = _functionName!;
    if (_type == _UNINITIALIZED) {
      _type = 0;
    }
    if (funcName.startsWith("get:")) {
      _type |= _GETTER;
      _memberName = new internal.Symbol.unvalidated(funcName.substring(4));
    } else if (funcName.startsWith("set:")) {
      _type |= _SETTER;
      _memberName =
          new internal.Symbol.unvalidated(funcName.substring(4) + "=");
    } else {
      _type |=
          _isSuperInvocation ? (_SUPER << _LEVEL_SHIFT) | _METHOD : _METHOD;
      _memberName = new internal.Symbol.unvalidated(funcName);
    }
  }

  Symbol get memberName {
    if (_memberName == null) {
      _setMemberNameAndType();
    }
    return _memberName!;
  }

  int get _typeArgsLen {
    int typeArgsLen = _argumentsDescriptor![_TYPE_ARGS_LEN];
    return typeArgsLen == 0 ? _delayedTypeArgumentsLen : typeArgsLen;
  }

  List<Type> get typeArguments {
    if (_typeArguments == null) {
      if (_typeArgsLen == 0) {
        return _typeArguments = const <Type>[];
      }
      // A TypeArguments object does not have a corresponding Dart class and
      // cannot be accessed as an array in Dart. Therefore, we need a native
      // call to unpack the individual types into a list.
      _typeArguments = _unpackTypeArguments(_arguments![0], _typeArgsLen);
    }
    return _typeArguments!;
  }

  // Unpack the given TypeArguments object into a new list of individual types.
  @pragma("vm:external-name", "InvocationMirror_unpackTypeArguments")
  external static List<Type> _unpackTypeArguments(
      typeArguments, int numTypeArguments);

  List get positionalArguments {
    if (_positionalArguments == null) {
      // The argument descriptor counts the receiver, but not the type arguments
      // as positional arguments.
      int numPositionalArguments = _argumentsDescriptor![_POSITIONAL_COUNT] - 1;
      if (numPositionalArguments == 0) {
        return _positionalArguments = const [];
      }
      // Exclude receiver and type args in the returned list.
      int receiverIndex = _typeArgsLen > 0 ? 1 : 0;
      var args = _arguments!;
      _positionalArguments = new _ImmutableList._from(
          args, receiverIndex + 1, numPositionalArguments);
    }
    return _positionalArguments!;
  }

  Map<Symbol, dynamic> get namedArguments {
    if (_namedArguments == null) {
      final argsDescriptor = _argumentsDescriptor!;
      int numArguments = argsDescriptor[_COUNT] - 1; // Exclude receiver.
      int numPositionalArguments = argsDescriptor[_POSITIONAL_COUNT] - 1;
      int numNamedArguments = numArguments - numPositionalArguments;
      if (numNamedArguments == 0) {
        return _namedArguments = const {};
      }
      int receiverIndex = _typeArgsLen > 0 ? 1 : 0;
      final namedArguments = new Map<Symbol, dynamic>();
      for (int i = 0; i < numNamedArguments; i++) {
        int namedEntryIndex = _FIRST_NAMED_ENTRY + 2 * i;
        int pos = argsDescriptor[namedEntryIndex + 1];
        String arg_name = argsDescriptor[namedEntryIndex];
        var arg_value = _arguments![receiverIndex + pos];
        namedArguments[new internal.Symbol.unvalidated(arg_name)] = arg_value;
      }
      _namedArguments = new Map.unmodifiable(namedArguments);
    }
    return _namedArguments!;
  }

  bool get isMethod {
    if (_type == _UNINITIALIZED) {
      _setMemberNameAndType();
    }
    return (_type & _KIND_MASK) == _METHOD;
  }

  bool get isAccessor {
    if (_type == _UNINITIALIZED) {
      _setMemberNameAndType();
    }
    return (_type & _KIND_MASK) != _METHOD;
  }

  bool get isGetter {
    if (_type == _UNINITIALIZED) {
      _setMemberNameAndType();
    }
    return (_type & _KIND_MASK) == _GETTER;
  }

  bool get isSetter {
    if (_type == _UNINITIALIZED) {
      _setMemberNameAndType();
    }
    return (_type & _KIND_MASK) == _SETTER;
  }

  _InvocationMirror(this._functionName, this._argumentsDescriptor,
      this._arguments, this._isSuperInvocation, this._type,
      [this._delayedTypeArgumentsLen = 0]);

  _InvocationMirror._withoutType(this._functionName, this._typeArguments,
      this._positionalArguments, this._namedArguments, this._isSuperInvocation,
      [this._delayedTypeArgumentsLen = 0]);

  @pragma("vm:entry-point", "call")
  static _allocateInvocationMirror(String functionName,
      List argumentsDescriptor, List arguments, bool isSuperInvocation,
      [int type = _UNINITIALIZED]) {
    return new _InvocationMirror(
        functionName, argumentsDescriptor, arguments, isSuperInvocation, type);
  }

  // This factory is used when creating an `Invocation` for a closure call which
  // may have delayed type arguments. In that case, the arguments descriptor will
  // indicate 0 type arguments, but the actual number of type arguments are
  // passed in `delayedTypeArgumentsLen`. If any type arguments are available,
  // the type arguments vector will be the first entry in `arguments`.
  @pragma("vm:entry-point", "call")
  static _allocateInvocationMirrorForClosure(
      String functionName,
      List argumentsDescriptor,
      List arguments,
      int? type,
      int delayedTypeArgumentsLen) {
    return new _InvocationMirror(functionName, argumentsDescriptor, arguments,
        false, type ?? _UNINITIALIZED, delayedTypeArgumentsLen);
  }
}
