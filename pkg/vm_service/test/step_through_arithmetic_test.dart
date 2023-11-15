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
const LINE_A = 19;
// AUTOGENERATED END

const file = 'step_through_arithmetic_test.dart';

void code() /* LINE_A */ {
  print(1 + 2);
  print((1 + 2) / 2);
  print(1 + 2 * 3);
  print((1 + 2) * 3);
}

final stops = <String>[];
const expected = <String>[
  '$file:${LINE_A + 0}:10', // after 'code'

  '$file:${LINE_A + 1}:11', // on '+'
  '$file:${LINE_A + 1}:3', // on 'print'

  '$file:${LINE_A + 2}:12', // on '+'
  '$file:${LINE_A + 2}:17', // on '/'
  '$file:${LINE_A + 2}:3', // on 'print'

  '$file:${LINE_A + 3}:15', // on '*'
  '$file:${LINE_A + 3}:11', // on '+'
  '$file:${LINE_A + 3}:3', // on 'print'

  '$file:${LINE_A + 4}:12', // on '+'
  '$file:${LINE_A + 4}:17', // on '*'
  '$file:${LINE_A + 4}:3', // on 'print'

  '$file:${LINE_A + 5}:1', // on ending '}'
];

final tests = <IsolateTest>[
  hasPausedAtStart,
  setBreakpointAtLine(LINE_A),
  runStepIntoThroughProgramRecordingStops(stops),
  checkRecordedStops(
    stops,
    expected,
    debugPrint: true,
    debugPrintFile: file,
    debugPrintLine: LINE_A,
  ),
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'step_through_arithmetic_test.dart',
      testeeConcurrent: code,
      pauseOnStart: true,
      pauseOnExit: true,
    );
