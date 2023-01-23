// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of "core_patch.dart";

@patch
external bool identical(Object? a, Object? b);

@patch
int identityHashCode(Object? object) =>
    object == null ? Null._HASH_CODE : object._identityHashCode;
