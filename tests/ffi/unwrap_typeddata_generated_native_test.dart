// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// This file has been automatically generated. Please do not edit it manually.
// Generated by tests/ffi/generator/unwrap_typeddata_test_generator.dart.
//
// SharedObjects=ffi_test_functions
// VMOptions=
// VMOptions=--deterministic --optimization-counter-threshold=90
// VMOptions=--use-slow-path
// VMOptions=--use-slow-path --stacktrace-every=100

import 'dart:ffi';
import 'dart:typed_data';

import 'package:expect/expect.dart';

import 'dylib_utils.dart';

final ffiTestFunctions = dlopenPlatformSpecific('ffi_test_functions');

void main() {
  // Force dlopen so @Native lookups in DynamicLibrary.process() succeed.
  dlopenGlobalPlatformSpecific('ffi_test_functions');

  for (int i = 0; i < 100; ++i) {
    testUnwrapInt8List();
    testUnwrapInt8ListView();
    testUnwrapInt8ListMany();
    testUnwrapInt16List();
    testUnwrapInt16ListView();
    testUnwrapInt16ListMany();
    testUnwrapInt32List();
    testUnwrapInt32ListView();
    testUnwrapInt32ListMany();
    testUnwrapInt64List();
    testUnwrapInt64ListView();
    testUnwrapInt64ListMany();
    testUnwrapUint8List();
    testUnwrapUint8ListView();
    testUnwrapUint8ListMany();
    testUnwrapUint16List();
    testUnwrapUint16ListView();
    testUnwrapUint16ListMany();
    testUnwrapUint32List();
    testUnwrapUint32ListView();
    testUnwrapUint32ListMany();
    testUnwrapUint64List();
    testUnwrapUint64ListView();
    testUnwrapUint64ListMany();
    testUnwrapFloat32List();
    testUnwrapFloat32ListView();
    testUnwrapFloat32ListMany();
    testUnwrapFloat64List();
    testUnwrapFloat64ListView();
    testUnwrapFloat64ListMany();
  }
}

@Native<Int8 Function(Pointer<Int8>, Size)>(
    symbol: 'UnwrapInt8List', isLeaf: true)
external int unwrapInt8List(Int8List typedData, int length);

@Native<
    Int8 Function(
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
      Pointer<Int8>,
    )>(symbol: 'UnwrapInt8ListMany', isLeaf: true)
external int unwrapInt8ListMany(
  Int8List typedData0,
  Int8List typedData1,
  Int8List typedData2,
  Int8List typedData3,
  Int8List typedData4,
  Int8List typedData5,
  Int8List typedData6,
  Int8List typedData7,
  Int8List typedData8,
  Int8List typedData9,
  Int8List typedData10,
  Int8List typedData11,
  Int8List typedData12,
  Int8List typedData13,
  Int8List typedData14,
  Int8List typedData15,
  Int8List typedData16,
  Int8List typedData17,
  Int8List typedData18,
  Int8List typedData19,
);

void testUnwrapInt8List() {
  const length = 10;
  final typedData = Int8List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt8List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt8ListView() {
  const sourceLength = 30;
  const elementSize = 1;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Int8List(sourceLength);
  final view = Int8List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapInt8List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt8ListMany() {
  const length = 20;
  const elementSize = 1;
  final source = Int8List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt8ListMany(
    Int8List.view(source.buffer, elementSize * 0, 1),
    Int8List.view(source.buffer, elementSize * 1, 1),
    Int8List.view(source.buffer, elementSize * 2, 1),
    Int8List.view(source.buffer, elementSize * 3, 1),
    Int8List.view(source.buffer, elementSize * 4, 1),
    Int8List.view(source.buffer, elementSize * 5, 1),
    Int8List.view(source.buffer, elementSize * 6, 1),
    Int8List.view(source.buffer, elementSize * 7, 1),
    Int8List.view(source.buffer, elementSize * 8, 1),
    Int8List.view(source.buffer, elementSize * 9, 1),
    Int8List.view(source.buffer, elementSize * 10, 1),
    Int8List.view(source.buffer, elementSize * 11, 1),
    Int8List.view(source.buffer, elementSize * 12, 1),
    Int8List.view(source.buffer, elementSize * 13, 1),
    Int8List.view(source.buffer, elementSize * 14, 1),
    Int8List.view(source.buffer, elementSize * 15, 1),
    Int8List.view(source.buffer, elementSize * 16, 1),
    Int8List.view(source.buffer, elementSize * 17, 1),
    Int8List.view(source.buffer, elementSize * 18, 1),
    Int8List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Int16 Function(Pointer<Int16>, Size)>(
    symbol: 'UnwrapInt16List', isLeaf: true)
external int unwrapInt16List(Int16List typedData, int length);

@Native<
    Int16 Function(
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
      Pointer<Int16>,
    )>(symbol: 'UnwrapInt16ListMany', isLeaf: true)
external int unwrapInt16ListMany(
  Int16List typedData0,
  Int16List typedData1,
  Int16List typedData2,
  Int16List typedData3,
  Int16List typedData4,
  Int16List typedData5,
  Int16List typedData6,
  Int16List typedData7,
  Int16List typedData8,
  Int16List typedData9,
  Int16List typedData10,
  Int16List typedData11,
  Int16List typedData12,
  Int16List typedData13,
  Int16List typedData14,
  Int16List typedData15,
  Int16List typedData16,
  Int16List typedData17,
  Int16List typedData18,
  Int16List typedData19,
);

void testUnwrapInt16List() {
  const length = 10;
  final typedData = Int16List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt16List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt16ListView() {
  const sourceLength = 30;
  const elementSize = 2;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Int16List(sourceLength);
  final view = Int16List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapInt16List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt16ListMany() {
  const length = 20;
  const elementSize = 2;
  final source = Int16List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt16ListMany(
    Int16List.view(source.buffer, elementSize * 0, 1),
    Int16List.view(source.buffer, elementSize * 1, 1),
    Int16List.view(source.buffer, elementSize * 2, 1),
    Int16List.view(source.buffer, elementSize * 3, 1),
    Int16List.view(source.buffer, elementSize * 4, 1),
    Int16List.view(source.buffer, elementSize * 5, 1),
    Int16List.view(source.buffer, elementSize * 6, 1),
    Int16List.view(source.buffer, elementSize * 7, 1),
    Int16List.view(source.buffer, elementSize * 8, 1),
    Int16List.view(source.buffer, elementSize * 9, 1),
    Int16List.view(source.buffer, elementSize * 10, 1),
    Int16List.view(source.buffer, elementSize * 11, 1),
    Int16List.view(source.buffer, elementSize * 12, 1),
    Int16List.view(source.buffer, elementSize * 13, 1),
    Int16List.view(source.buffer, elementSize * 14, 1),
    Int16List.view(source.buffer, elementSize * 15, 1),
    Int16List.view(source.buffer, elementSize * 16, 1),
    Int16List.view(source.buffer, elementSize * 17, 1),
    Int16List.view(source.buffer, elementSize * 18, 1),
    Int16List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Int32 Function(Pointer<Int32>, Size)>(
    symbol: 'UnwrapInt32List', isLeaf: true)
external int unwrapInt32List(Int32List typedData, int length);

@Native<
    Int32 Function(
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
      Pointer<Int32>,
    )>(symbol: 'UnwrapInt32ListMany', isLeaf: true)
external int unwrapInt32ListMany(
  Int32List typedData0,
  Int32List typedData1,
  Int32List typedData2,
  Int32List typedData3,
  Int32List typedData4,
  Int32List typedData5,
  Int32List typedData6,
  Int32List typedData7,
  Int32List typedData8,
  Int32List typedData9,
  Int32List typedData10,
  Int32List typedData11,
  Int32List typedData12,
  Int32List typedData13,
  Int32List typedData14,
  Int32List typedData15,
  Int32List typedData16,
  Int32List typedData17,
  Int32List typedData18,
  Int32List typedData19,
);

void testUnwrapInt32List() {
  const length = 10;
  final typedData = Int32List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt32List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt32ListView() {
  const sourceLength = 30;
  const elementSize = 4;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Int32List(sourceLength);
  final view = Int32List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapInt32List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt32ListMany() {
  const length = 20;
  const elementSize = 4;
  final source = Int32List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt32ListMany(
    Int32List.view(source.buffer, elementSize * 0, 1),
    Int32List.view(source.buffer, elementSize * 1, 1),
    Int32List.view(source.buffer, elementSize * 2, 1),
    Int32List.view(source.buffer, elementSize * 3, 1),
    Int32List.view(source.buffer, elementSize * 4, 1),
    Int32List.view(source.buffer, elementSize * 5, 1),
    Int32List.view(source.buffer, elementSize * 6, 1),
    Int32List.view(source.buffer, elementSize * 7, 1),
    Int32List.view(source.buffer, elementSize * 8, 1),
    Int32List.view(source.buffer, elementSize * 9, 1),
    Int32List.view(source.buffer, elementSize * 10, 1),
    Int32List.view(source.buffer, elementSize * 11, 1),
    Int32List.view(source.buffer, elementSize * 12, 1),
    Int32List.view(source.buffer, elementSize * 13, 1),
    Int32List.view(source.buffer, elementSize * 14, 1),
    Int32List.view(source.buffer, elementSize * 15, 1),
    Int32List.view(source.buffer, elementSize * 16, 1),
    Int32List.view(source.buffer, elementSize * 17, 1),
    Int32List.view(source.buffer, elementSize * 18, 1),
    Int32List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Int64 Function(Pointer<Int64>, Size)>(
    symbol: 'UnwrapInt64List', isLeaf: true)
external int unwrapInt64List(Int64List typedData, int length);

@Native<
    Int64 Function(
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
      Pointer<Int64>,
    )>(symbol: 'UnwrapInt64ListMany', isLeaf: true)
external int unwrapInt64ListMany(
  Int64List typedData0,
  Int64List typedData1,
  Int64List typedData2,
  Int64List typedData3,
  Int64List typedData4,
  Int64List typedData5,
  Int64List typedData6,
  Int64List typedData7,
  Int64List typedData8,
  Int64List typedData9,
  Int64List typedData10,
  Int64List typedData11,
  Int64List typedData12,
  Int64List typedData13,
  Int64List typedData14,
  Int64List typedData15,
  Int64List typedData16,
  Int64List typedData17,
  Int64List typedData18,
  Int64List typedData19,
);

void testUnwrapInt64List() {
  const length = 10;
  final typedData = Int64List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt64List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt64ListView() {
  const sourceLength = 30;
  const elementSize = 8;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Int64List(sourceLength);
  final view = Int64List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapInt64List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapInt64ListMany() {
  const length = 20;
  const elementSize = 8;
  final source = Int64List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i % 2 == 0 ? i : -i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapInt64ListMany(
    Int64List.view(source.buffer, elementSize * 0, 1),
    Int64List.view(source.buffer, elementSize * 1, 1),
    Int64List.view(source.buffer, elementSize * 2, 1),
    Int64List.view(source.buffer, elementSize * 3, 1),
    Int64List.view(source.buffer, elementSize * 4, 1),
    Int64List.view(source.buffer, elementSize * 5, 1),
    Int64List.view(source.buffer, elementSize * 6, 1),
    Int64List.view(source.buffer, elementSize * 7, 1),
    Int64List.view(source.buffer, elementSize * 8, 1),
    Int64List.view(source.buffer, elementSize * 9, 1),
    Int64List.view(source.buffer, elementSize * 10, 1),
    Int64List.view(source.buffer, elementSize * 11, 1),
    Int64List.view(source.buffer, elementSize * 12, 1),
    Int64List.view(source.buffer, elementSize * 13, 1),
    Int64List.view(source.buffer, elementSize * 14, 1),
    Int64List.view(source.buffer, elementSize * 15, 1),
    Int64List.view(source.buffer, elementSize * 16, 1),
    Int64List.view(source.buffer, elementSize * 17, 1),
    Int64List.view(source.buffer, elementSize * 18, 1),
    Int64List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Uint8 Function(Pointer<Uint8>, Size)>(
    symbol: 'UnwrapUint8List', isLeaf: true)
external int unwrapUint8List(Uint8List typedData, int length);

@Native<
    Uint8 Function(
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
    )>(symbol: 'UnwrapUint8ListMany', isLeaf: true)
external int unwrapUint8ListMany(
  Uint8List typedData0,
  Uint8List typedData1,
  Uint8List typedData2,
  Uint8List typedData3,
  Uint8List typedData4,
  Uint8List typedData5,
  Uint8List typedData6,
  Uint8List typedData7,
  Uint8List typedData8,
  Uint8List typedData9,
  Uint8List typedData10,
  Uint8List typedData11,
  Uint8List typedData12,
  Uint8List typedData13,
  Uint8List typedData14,
  Uint8List typedData15,
  Uint8List typedData16,
  Uint8List typedData17,
  Uint8List typedData18,
  Uint8List typedData19,
);

void testUnwrapUint8List() {
  const length = 10;
  final typedData = Uint8List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint8List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint8ListView() {
  const sourceLength = 30;
  const elementSize = 1;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Uint8List(sourceLength);
  final view = Uint8List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapUint8List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint8ListMany() {
  const length = 20;
  const elementSize = 1;
  final source = Uint8List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint8ListMany(
    Uint8List.view(source.buffer, elementSize * 0, 1),
    Uint8List.view(source.buffer, elementSize * 1, 1),
    Uint8List.view(source.buffer, elementSize * 2, 1),
    Uint8List.view(source.buffer, elementSize * 3, 1),
    Uint8List.view(source.buffer, elementSize * 4, 1),
    Uint8List.view(source.buffer, elementSize * 5, 1),
    Uint8List.view(source.buffer, elementSize * 6, 1),
    Uint8List.view(source.buffer, elementSize * 7, 1),
    Uint8List.view(source.buffer, elementSize * 8, 1),
    Uint8List.view(source.buffer, elementSize * 9, 1),
    Uint8List.view(source.buffer, elementSize * 10, 1),
    Uint8List.view(source.buffer, elementSize * 11, 1),
    Uint8List.view(source.buffer, elementSize * 12, 1),
    Uint8List.view(source.buffer, elementSize * 13, 1),
    Uint8List.view(source.buffer, elementSize * 14, 1),
    Uint8List.view(source.buffer, elementSize * 15, 1),
    Uint8List.view(source.buffer, elementSize * 16, 1),
    Uint8List.view(source.buffer, elementSize * 17, 1),
    Uint8List.view(source.buffer, elementSize * 18, 1),
    Uint8List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Uint16 Function(Pointer<Uint16>, Size)>(
    symbol: 'UnwrapUint16List', isLeaf: true)
external int unwrapUint16List(Uint16List typedData, int length);

@Native<
    Uint16 Function(
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
      Pointer<Uint16>,
    )>(symbol: 'UnwrapUint16ListMany', isLeaf: true)
external int unwrapUint16ListMany(
  Uint16List typedData0,
  Uint16List typedData1,
  Uint16List typedData2,
  Uint16List typedData3,
  Uint16List typedData4,
  Uint16List typedData5,
  Uint16List typedData6,
  Uint16List typedData7,
  Uint16List typedData8,
  Uint16List typedData9,
  Uint16List typedData10,
  Uint16List typedData11,
  Uint16List typedData12,
  Uint16List typedData13,
  Uint16List typedData14,
  Uint16List typedData15,
  Uint16List typedData16,
  Uint16List typedData17,
  Uint16List typedData18,
  Uint16List typedData19,
);

void testUnwrapUint16List() {
  const length = 10;
  final typedData = Uint16List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint16List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint16ListView() {
  const sourceLength = 30;
  const elementSize = 2;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Uint16List(sourceLength);
  final view = Uint16List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapUint16List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint16ListMany() {
  const length = 20;
  const elementSize = 2;
  final source = Uint16List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint16ListMany(
    Uint16List.view(source.buffer, elementSize * 0, 1),
    Uint16List.view(source.buffer, elementSize * 1, 1),
    Uint16List.view(source.buffer, elementSize * 2, 1),
    Uint16List.view(source.buffer, elementSize * 3, 1),
    Uint16List.view(source.buffer, elementSize * 4, 1),
    Uint16List.view(source.buffer, elementSize * 5, 1),
    Uint16List.view(source.buffer, elementSize * 6, 1),
    Uint16List.view(source.buffer, elementSize * 7, 1),
    Uint16List.view(source.buffer, elementSize * 8, 1),
    Uint16List.view(source.buffer, elementSize * 9, 1),
    Uint16List.view(source.buffer, elementSize * 10, 1),
    Uint16List.view(source.buffer, elementSize * 11, 1),
    Uint16List.view(source.buffer, elementSize * 12, 1),
    Uint16List.view(source.buffer, elementSize * 13, 1),
    Uint16List.view(source.buffer, elementSize * 14, 1),
    Uint16List.view(source.buffer, elementSize * 15, 1),
    Uint16List.view(source.buffer, elementSize * 16, 1),
    Uint16List.view(source.buffer, elementSize * 17, 1),
    Uint16List.view(source.buffer, elementSize * 18, 1),
    Uint16List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Uint32 Function(Pointer<Uint32>, Size)>(
    symbol: 'UnwrapUint32List', isLeaf: true)
external int unwrapUint32List(Uint32List typedData, int length);

@Native<
    Uint32 Function(
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
    )>(symbol: 'UnwrapUint32ListMany', isLeaf: true)
external int unwrapUint32ListMany(
  Uint32List typedData0,
  Uint32List typedData1,
  Uint32List typedData2,
  Uint32List typedData3,
  Uint32List typedData4,
  Uint32List typedData5,
  Uint32List typedData6,
  Uint32List typedData7,
  Uint32List typedData8,
  Uint32List typedData9,
  Uint32List typedData10,
  Uint32List typedData11,
  Uint32List typedData12,
  Uint32List typedData13,
  Uint32List typedData14,
  Uint32List typedData15,
  Uint32List typedData16,
  Uint32List typedData17,
  Uint32List typedData18,
  Uint32List typedData19,
);

void testUnwrapUint32List() {
  const length = 10;
  final typedData = Uint32List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint32List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint32ListView() {
  const sourceLength = 30;
  const elementSize = 4;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Uint32List(sourceLength);
  final view = Uint32List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapUint32List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint32ListMany() {
  const length = 20;
  const elementSize = 4;
  final source = Uint32List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint32ListMany(
    Uint32List.view(source.buffer, elementSize * 0, 1),
    Uint32List.view(source.buffer, elementSize * 1, 1),
    Uint32List.view(source.buffer, elementSize * 2, 1),
    Uint32List.view(source.buffer, elementSize * 3, 1),
    Uint32List.view(source.buffer, elementSize * 4, 1),
    Uint32List.view(source.buffer, elementSize * 5, 1),
    Uint32List.view(source.buffer, elementSize * 6, 1),
    Uint32List.view(source.buffer, elementSize * 7, 1),
    Uint32List.view(source.buffer, elementSize * 8, 1),
    Uint32List.view(source.buffer, elementSize * 9, 1),
    Uint32List.view(source.buffer, elementSize * 10, 1),
    Uint32List.view(source.buffer, elementSize * 11, 1),
    Uint32List.view(source.buffer, elementSize * 12, 1),
    Uint32List.view(source.buffer, elementSize * 13, 1),
    Uint32List.view(source.buffer, elementSize * 14, 1),
    Uint32List.view(source.buffer, elementSize * 15, 1),
    Uint32List.view(source.buffer, elementSize * 16, 1),
    Uint32List.view(source.buffer, elementSize * 17, 1),
    Uint32List.view(source.buffer, elementSize * 18, 1),
    Uint32List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Uint64 Function(Pointer<Uint64>, Size)>(
    symbol: 'UnwrapUint64List', isLeaf: true)
external int unwrapUint64List(Uint64List typedData, int length);

@Native<
    Uint64 Function(
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    )>(symbol: 'UnwrapUint64ListMany', isLeaf: true)
external int unwrapUint64ListMany(
  Uint64List typedData0,
  Uint64List typedData1,
  Uint64List typedData2,
  Uint64List typedData3,
  Uint64List typedData4,
  Uint64List typedData5,
  Uint64List typedData6,
  Uint64List typedData7,
  Uint64List typedData8,
  Uint64List typedData9,
  Uint64List typedData10,
  Uint64List typedData11,
  Uint64List typedData12,
  Uint64List typedData13,
  Uint64List typedData14,
  Uint64List typedData15,
  Uint64List typedData16,
  Uint64List typedData17,
  Uint64List typedData18,
  Uint64List typedData19,
);

void testUnwrapUint64List() {
  const length = 10;
  final typedData = Uint64List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint64List(typedData, typedData.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint64ListView() {
  const sourceLength = 30;
  const elementSize = 8;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Uint64List(sourceLength);
  final view = Uint64List.view(source.buffer, viewOffsetInBytes, viewLength);
  int expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = i;
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapUint64List(view, view.length);
  Expect.equals(expectedResult, result);
}

void testUnwrapUint64ListMany() {
  const length = 20;
  const elementSize = 8;
  final source = Uint64List(length);
  int expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = i;
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapUint64ListMany(
    Uint64List.view(source.buffer, elementSize * 0, 1),
    Uint64List.view(source.buffer, elementSize * 1, 1),
    Uint64List.view(source.buffer, elementSize * 2, 1),
    Uint64List.view(source.buffer, elementSize * 3, 1),
    Uint64List.view(source.buffer, elementSize * 4, 1),
    Uint64List.view(source.buffer, elementSize * 5, 1),
    Uint64List.view(source.buffer, elementSize * 6, 1),
    Uint64List.view(source.buffer, elementSize * 7, 1),
    Uint64List.view(source.buffer, elementSize * 8, 1),
    Uint64List.view(source.buffer, elementSize * 9, 1),
    Uint64List.view(source.buffer, elementSize * 10, 1),
    Uint64List.view(source.buffer, elementSize * 11, 1),
    Uint64List.view(source.buffer, elementSize * 12, 1),
    Uint64List.view(source.buffer, elementSize * 13, 1),
    Uint64List.view(source.buffer, elementSize * 14, 1),
    Uint64List.view(source.buffer, elementSize * 15, 1),
    Uint64List.view(source.buffer, elementSize * 16, 1),
    Uint64List.view(source.buffer, elementSize * 17, 1),
    Uint64List.view(source.buffer, elementSize * 18, 1),
    Uint64List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.equals(expectedResult, result);
}

@Native<Float Function(Pointer<Float>, Size)>(
    symbol: 'UnwrapFloat32List', isLeaf: true)
external double unwrapFloat32List(Float32List typedData, int length);

@Native<
    Float Function(
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
      Pointer<Float>,
    )>(symbol: 'UnwrapFloat32ListMany', isLeaf: true)
external double unwrapFloat32ListMany(
  Float32List typedData0,
  Float32List typedData1,
  Float32List typedData2,
  Float32List typedData3,
  Float32List typedData4,
  Float32List typedData5,
  Float32List typedData6,
  Float32List typedData7,
  Float32List typedData8,
  Float32List typedData9,
  Float32List typedData10,
  Float32List typedData11,
  Float32List typedData12,
  Float32List typedData13,
  Float32List typedData14,
  Float32List typedData15,
  Float32List typedData16,
  Float32List typedData17,
  Float32List typedData18,
  Float32List typedData19,
);

void testUnwrapFloat32List() {
  const length = 10;
  final typedData = Float32List(length);
  double expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = (i % 2 == 0 ? i : -i).toDouble();
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapFloat32List(typedData, typedData.length);
  Expect.approxEquals(expectedResult, result);
}

void testUnwrapFloat32ListView() {
  const sourceLength = 30;
  const elementSize = 4;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Float32List(sourceLength);
  final view = Float32List.view(source.buffer, viewOffsetInBytes, viewLength);
  double expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = (i % 2 == 0 ? i : -i).toDouble();
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapFloat32List(view, view.length);
  Expect.approxEquals(expectedResult, result);
}

void testUnwrapFloat32ListMany() {
  const length = 20;
  const elementSize = 4;
  final source = Float32List(length);
  double expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = (i % 2 == 0 ? i : -i).toDouble();
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapFloat32ListMany(
    Float32List.view(source.buffer, elementSize * 0, 1),
    Float32List.view(source.buffer, elementSize * 1, 1),
    Float32List.view(source.buffer, elementSize * 2, 1),
    Float32List.view(source.buffer, elementSize * 3, 1),
    Float32List.view(source.buffer, elementSize * 4, 1),
    Float32List.view(source.buffer, elementSize * 5, 1),
    Float32List.view(source.buffer, elementSize * 6, 1),
    Float32List.view(source.buffer, elementSize * 7, 1),
    Float32List.view(source.buffer, elementSize * 8, 1),
    Float32List.view(source.buffer, elementSize * 9, 1),
    Float32List.view(source.buffer, elementSize * 10, 1),
    Float32List.view(source.buffer, elementSize * 11, 1),
    Float32List.view(source.buffer, elementSize * 12, 1),
    Float32List.view(source.buffer, elementSize * 13, 1),
    Float32List.view(source.buffer, elementSize * 14, 1),
    Float32List.view(source.buffer, elementSize * 15, 1),
    Float32List.view(source.buffer, elementSize * 16, 1),
    Float32List.view(source.buffer, elementSize * 17, 1),
    Float32List.view(source.buffer, elementSize * 18, 1),
    Float32List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.approxEquals(expectedResult, result);
}

@Native<Double Function(Pointer<Double>, Size)>(
    symbol: 'UnwrapFloat64List', isLeaf: true)
external double unwrapFloat64List(Float64List typedData, int length);

@Native<
    Double Function(
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
      Pointer<Double>,
    )>(symbol: 'UnwrapFloat64ListMany', isLeaf: true)
external double unwrapFloat64ListMany(
  Float64List typedData0,
  Float64List typedData1,
  Float64List typedData2,
  Float64List typedData3,
  Float64List typedData4,
  Float64List typedData5,
  Float64List typedData6,
  Float64List typedData7,
  Float64List typedData8,
  Float64List typedData9,
  Float64List typedData10,
  Float64List typedData11,
  Float64List typedData12,
  Float64List typedData13,
  Float64List typedData14,
  Float64List typedData15,
  Float64List typedData16,
  Float64List typedData17,
  Float64List typedData18,
  Float64List typedData19,
);

void testUnwrapFloat64List() {
  const length = 10;
  final typedData = Float64List(length);
  double expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = (i % 2 == 0 ? i : -i).toDouble();
    typedData[i] = value;
    expectedResult += value;
  }
  final result = unwrapFloat64List(typedData, typedData.length);
  Expect.approxEquals(expectedResult, result);
}

void testUnwrapFloat64ListView() {
  const sourceLength = 30;
  const elementSize = 8;
  const viewStart = 10;
  const viewOffsetInBytes = viewStart * elementSize;
  const viewLength = 10;
  final viewEnd = viewStart + viewLength;
  final source = Float64List(sourceLength);
  final view = Float64List.view(source.buffer, viewOffsetInBytes, viewLength);
  double expectedResult = 0;
  for (int i = 0; i < sourceLength; i++) {
    final value = (i % 2 == 0 ? i : -i).toDouble();
    source[i] = value;
    if (viewStart <= i && i < viewEnd) {
      expectedResult += value;
    }
  }
  final result = unwrapFloat64List(view, view.length);
  Expect.approxEquals(expectedResult, result);
}

void testUnwrapFloat64ListMany() {
  const length = 20;
  const elementSize = 8;
  final source = Float64List(length);
  double expectedResult = 0;
  for (int i = 0; i < length; i++) {
    final value = (i % 2 == 0 ? i : -i).toDouble();
    source[i] = value;
    expectedResult += value;
  }
  final result = unwrapFloat64ListMany(
    Float64List.view(source.buffer, elementSize * 0, 1),
    Float64List.view(source.buffer, elementSize * 1, 1),
    Float64List.view(source.buffer, elementSize * 2, 1),
    Float64List.view(source.buffer, elementSize * 3, 1),
    Float64List.view(source.buffer, elementSize * 4, 1),
    Float64List.view(source.buffer, elementSize * 5, 1),
    Float64List.view(source.buffer, elementSize * 6, 1),
    Float64List.view(source.buffer, elementSize * 7, 1),
    Float64List.view(source.buffer, elementSize * 8, 1),
    Float64List.view(source.buffer, elementSize * 9, 1),
    Float64List.view(source.buffer, elementSize * 10, 1),
    Float64List.view(source.buffer, elementSize * 11, 1),
    Float64List.view(source.buffer, elementSize * 12, 1),
    Float64List.view(source.buffer, elementSize * 13, 1),
    Float64List.view(source.buffer, elementSize * 14, 1),
    Float64List.view(source.buffer, elementSize * 15, 1),
    Float64List.view(source.buffer, elementSize * 16, 1),
    Float64List.view(source.buffer, elementSize * 17, 1),
    Float64List.view(source.buffer, elementSize * 18, 1),
    Float64List.view(source.buffer, elementSize * 19, 1),
  );
  Expect.approxEquals(expectedResult, result);
}
