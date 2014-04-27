#!/bin/sh
#DART_SDK=~/dart/dart-sdk
DART_SDK=~/bin/dart/dart-sdk
perf record -g -- $DART_SDK/bin/dart --generate_perf_events_symbols multi_bench.dart
perf report --call-graph flat
