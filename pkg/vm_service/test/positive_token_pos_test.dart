// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// VMOptions=--verbose_debug

import 'dart:developer';

import 'package:vm_service/vm_service.dart';
import 'package:test/test.dart';

import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart <test.dart>
//
const LINE_C = 29;
const LINE_A = 33;
const LINE_B = 34;
// AUTOGENERATED END

const LINE_B_COL = 3;
const LINE_C_COL = 1;

Future<void> helper() async {
  // LINE_C
}

void testMain() {
  debugger(); // LINE_A
  helper(); // LINE_B
}

final tests = <IsolateTest>[
  hasStoppedAtBreakpoint,
  stoppedAtLine(LINE_A),
  stepOver,
  hasStoppedAtBreakpoint,
  stoppedAtLine(LINE_B),
  stepInto,
  (VmService service, IsolateRef isolateRef) async {
    final isolateId = isolateRef.id!;
    final stack = await service.getStack(isolateId);
    final frames = stack.frames!;
    expect(frames.length, greaterThan(2));

    // We used to return a negative token position for this frame.
    // See issue #27128.
    var frame = frames[0];
    expect(frame.function!.name, 'helper');
    expect(await frame.location!.line, LINE_C + 1);
    expect(await frame.location!.column, LINE_C_COL);

    frame = frames[1];
    expect(frame.function!.name, 'testMain');
    expect(await frame.location!.line, LINE_B);
    expect(await frame.location!.column, LINE_B_COL);
  }
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'positive_token_pos_test.dart',
      testeeConcurrent: testMain,
    );
