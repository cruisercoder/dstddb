#!/bin/bash
set -e -x -o pipefail

dub test :sqlite

