#!/usr/bin/env python3
# Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import argparse
import os
import sys
import utils


def ParseArgs(args):
    args = args[1:]
    parser = argparse.ArgumentParser(
        description='A script to write the revision string to a file')

    parser.add_argument(
        '--output', '-o', type=str, required=True, help='File to write')
    parser.add_argument('--no-git-hash',
                        help='Omit the git hash in the output',
                        dest='no_git_hash',
                        action='store_true')

    return parser.parse_args(args)


def Main(argv):
    args = ParseArgs(argv)
    if not args.no_git_hash:
        revision = utils.GetGitRevision()
    else:
        revision = ''
    if revision is not None:
        with open(args.output, 'w') as f:
            f.write('%s\n' % revision)
    return 0


if __name__ == '__main__':
    sys.exit(Main(sys.argv))
