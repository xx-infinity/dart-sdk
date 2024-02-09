// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

interface class Model {}

class MyModelExpectingABoolean implements Model {
  MyModelExpectingABoolean(bool value);
}

class MyModelExpectingAString implements Model {
  MyModelExpectingAString(String value);
}

void test1() {
  // The expectation is that 'someKey' will only ever be a bool or a String.
  final model = switch (json['someKey']) {
    final bool value => MyModelExpectingABoolean(value),
    final value as String => MyModelExpectingAString(value),
  };
}

void test2() {
  // The expectation is that 'someKey' will only ever be a bool or a String.
  final model = switch (json['someKey']) {
    final bool value => MyModelExpectingABoolean(value),
    _ as String => MyModelExpectingAString(''),
  };
}

final Map<String, dynamic> json = {
  'someKey': 'In some cases, this field could also be a boolean',
};
