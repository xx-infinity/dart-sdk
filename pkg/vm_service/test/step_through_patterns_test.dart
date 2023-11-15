// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=3.0

import 'dart:math' show pi;
import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart <test.dart>
//
const LINE_A = 33;
// AUTOGENERATED END
const String FILE = 'step_through_patterns_test.dart';

abstract class Shape {}

class Square implements Shape {
  final double length;
  Square(this.length);
}

class Circle implements Shape {
  final double radius;
  Circle(this.radius);
}

double calculateArea(Shape shape) => switch (shape) /* LINE_A */ {
      Square(length: final l) when l >= 0 => l * l,
      Circle(radius: final r) when r >= 0 => pi * r * r,
      Square(length: final l) when l < 0 => -1,
      Circle(radius: final r) when r < 0 => -1,
      Shape() => 0
    };

void testMain() {
  calculateArea(Circle(-123));
}

final stops = <String>[];

const expected = <String>[
  '$FILE:${LINE_A + 0}:28', // on 'shape' before 'switch'
  '$FILE:${LINE_A + 1}:7', // on 'Square'
  '$FILE:${LINE_A + 2}:7', // on 'Circle'
  '$FILE:${LINE_A + 2}:28', // on 'r' right after 'var'
  '$FILE:${LINE_A + 2}:38', // on '>='
  '$FILE:${LINE_A + 3}:7', // on 'Square'
  '$FILE:${LINE_A + 4}:7', // on 'Circle'
  '$FILE:${LINE_A + 4}:28', // on 'r' right after 'var'
  '$FILE:${LINE_A + 4}:38', // on '<'
  '$FILE:${LINE_A + 4}:42', // on '=>'
  '$FILE:${LINE_A + 0}:38', // on 'switch'
  '$FILE:43:1', // on closing '}' of [testMain]
];

final tests = <IsolateTest>[
  hasPausedAtStart,
  setBreakpointAtLine(LINE_A),
  runStepThroughProgramRecordingStops(stops),
  checkRecordedStops(stops, expected),
];

void main(args) => runIsolateTestsSynchronous(
      args,
      tests,
      FILE,
      testeeConcurrent: testMain,
      extraArgs: extraDebuggingArgs,
      pauseOnStart: true,
      pauseOnExit: true,
    );
