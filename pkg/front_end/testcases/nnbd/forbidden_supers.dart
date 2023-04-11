// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This test checks for compile-time errors in cases when either Never or T? is
// extended, implemented, or mixed in, where T is a type.

mixin class Aoo {}

class Boo {}

class Coo extends Boo with Aoo? {}

class Doo extends Aoo? {}

class Eoo implements Boo? {}

class Foo extends Boo? with Aoo {}

class Goo = Boo? with Aoo?;

class Hoo extends Object with Aoo implements Boo? {}

class Ioo = Object with Aoo implements Boo?;

class Joo extends Boo with Never {}

class Koo extends Never {}

class Loo implements Never {}

mixin Moo1 on Aoo? implements Boo? {}

mixin Moo2 on Aoo?, Boo? {}

mixin Moo3 implements Aoo?, Boo? {}

mixin Moo4 on Aoo implements Never {}

mixin Moo5 on Aoo, Never {}

mixin Moo6 on Never {}

mixin Moo7 implements Aoo, Never {}

mixin Moo8 implements Never {}

class Noo = Never with Aoo;
class NooDynamic = dynamic with Aoo;
class NooVoid = void with Aoo;

class Ooo = Aoo with Never;

main() {}
