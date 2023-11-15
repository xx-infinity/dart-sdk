// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart <test.dart>
//
const LINE_A = 29;
// AUTOGENERATED END

const file = 'next_through_operator_bracket_test.dart';

class Class2 {
  int operator [](int index) => index;

  int code() {
    this[42];
    return this[42];
  }
}

void code() {
  final c = Class2(); // LINE_A
  c[42];
  c.code();
}

final stops = <String>[];
const expected = <String>[
  '$file:${LINE_A + 0}:13', // on 'Class2()'
  '$file:${LINE_A + 1}:4', // on '['
  '$file:${LINE_A + 2}:5', // on 'code'
  '$file:${LINE_A + 3}:1', // on ending '}'
];

final tests = <IsolateTest>[
  hasPausedAtStart,
  setBreakpointAtLine(LINE_A),
  runStepThroughProgramRecordingStops(stops),
  checkRecordedStops(stops, expected),
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'next_through_operator_bracket_test.dart',
      testeeConcurrent: code,
      pauseOnStart: true,
      pauseOnExit: true,
    );
