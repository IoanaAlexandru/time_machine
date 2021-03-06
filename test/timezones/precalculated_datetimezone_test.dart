// Portions of this work are Copyright 2018 The Time Machine Authors. All rights reserved.
// Portions of this work are Copyright 2018 The Noda Time Authors. All rights reserved.
// Use of this source code is governed by the Apache License 2.0, as found in the LICENSE.txt file.

import 'dart:async';

import 'package:time_machine/src/time_machine_internal.dart';
import 'package:test/test.dart';
import 'package:matcher/matcher.dart';

import '../time_machine_testing.dart';

Future main() async {
  await runTests();
}

final ZoneInterval FirstInterval =
IZoneInterval.newZoneInterval('First', IInstant.beforeMinValue, Instant.utc(2000, 3, 10, 10, 0), Offset.hours(3), Offset.zero);

// Note that this is effectively UTC +3 + 1 hour DST.
final ZoneInterval SecondInterval =
IZoneInterval.newZoneInterval('Second', FirstInterval.end, Instant.utc(2000, 9, 15, 5, 0), Offset.hours(4), Offset.hours(1));

final ZoneInterval ThirdInterval =
IZoneInterval.newZoneInterval('Third', SecondInterval.end, Instant.utc(2005, 1, 20, 8, 0), Offset.hours(-5), Offset.zero);

final ZoneRecurrence Winter = ZoneRecurrence('Winter', Offset.zero,
ZoneYearOffset(TransitionMode.wall, 10, 5, 0, false, LocalTime(2, 0, 0)), 1960, Platform.int32MaxValue);

final ZoneRecurrence Summer = ZoneRecurrence('Summer', Offset.hours(1),
ZoneYearOffset(TransitionMode.wall, 3, 10, 0, false, LocalTime(1, 0, 0)), 1960, Platform.int32MaxValue);

final StandardDaylightAlternatingMap TailZone =
StandardDaylightAlternatingMap(Offset.hours(-6), Winter, Summer);

// We don't actually want an interval from the beginning of time when we ask our composite time zone for an interval
// - because that could give the wrong idea. So we clamp it at the end of the precalculated interval.
final ZoneInterval ClampedTailZoneInterval = IZoneInterval.withStart(TailZone.getZoneInterval(ThirdInterval.end), ThirdInterval.end);

final PrecalculatedDateTimeZone TestZone =
PrecalculatedDateTimeZone('Test', [ FirstInterval, SecondInterval, ThirdInterval ], TailZone);

@Test()
void MinMaxOffsets()
{
  expect(Offset.hours(-6), TestZone.minOffset);
  expect(Offset.hours(4), TestZone.maxOffset);
}

@Test()
void MinMaxOffsetsWithOtherTailZone()
{
  var tailZone = FixedDateTimeZone.forIdOffset('TestFixed', Offset.hours(8));
  var testZone = PrecalculatedDateTimeZone('Test',
      [ FirstInterval, SecondInterval, ThirdInterval ], tailZone);
  expect(Offset.hours(-5), testZone.minOffset);
  expect(Offset.hours(8), testZone.maxOffset);
}

@Test()
void MinMaxOffsetsWithNullTailZone()
{
  var testZone = PrecalculatedDateTimeZone('Test',
      [ FirstInterval, SecondInterval, ThirdInterval,
      IZoneInterval.newZoneInterval('Last', ThirdInterval.end, IInstant.afterMaxValue, Offset.zero, Offset.zero) ], null);
  expect(Offset.hours(-5), testZone.minOffset);
  expect(Offset.hours(4), testZone.maxOffset);
}

@Test()
void GetZoneIntervalInstant_End()
{
  expect(SecondInterval, TestZone.getZoneInterval(SecondInterval.end - Time.epsilon));
}

@Test()
void GetZoneIntervalInstant_Start()
{
  expect(SecondInterval, TestZone.getZoneInterval(SecondInterval.start));
}

@Test()
void GetZoneIntervalInstant_FinalInterval_End()
{
  expect(ThirdInterval, TestZone.getZoneInterval(ThirdInterval.end - Time.epsilon));
}

@Test()
void GetZoneIntervalInstant_FinalInterval_Start()
{
  expect(ThirdInterval, TestZone.getZoneInterval(ThirdInterval.start));
}

@Test()
void GetZoneIntervalInstant_TailZone()
{
  expect(ClampedTailZoneInterval, TestZone.getZoneInterval(ThirdInterval.end));
}

@Test()
void MapLocal_UnambiguousInPrecalculated()
{
  CheckMapping(LocalDateTime(2000, 6, 1, 0, 0, 0), SecondInterval, SecondInterval, 1);
}

@Test()
void MapLocal_UnambiguousInTailZone()
{
  CheckMapping(LocalDateTime(2005, 2, 1, 0, 0, 0), ClampedTailZoneInterval, ClampedTailZoneInterval, 1);
}

@Test()
void MapLocal_AmbiguousWithinPrecalculated()
{
  // Transition from +4 to -5 has a 9 hour ambiguity
  CheckMapping(ThirdInterval.isoLocalStart, SecondInterval, ThirdInterval, 2);
}

@Test()
void MapLocal_AmbiguousAroundTailZoneTransition()
{
  // Transition from -5 to -6 has a 1 hour ambiguity
  // CheckMapping(ThirdInterval.IsoLocalEnd.PlusNanoseconds(-1L), ThirdInterval, ClampedTailZoneInterval, 2);
  CheckMapping(ThirdInterval.isoLocalEnd.addNanoseconds(-1), ThirdInterval, ClampedTailZoneInterval, 2);
}

@Test()
void MapLocal_AmbiguousButTooEarlyInTailZoneTransition()
{
  // Tail zone is +10 / +8, with the transition occurring just after
  // the transition *to* the tail zone from the precalculated zone.
  // A local instant of one hour before after the transition from the precalculated zone (which is -5)
  // will therefore be ambiguous, but the resulting instants from the ambiguity occur
  // before our transition into the tail zone, so are ignored.
  var tailZone = SingleTransitionDateTimeZone.around(ThirdInterval.end + Time(hours: 1), 10, 8);
  var gapZone = PrecalculatedDateTimeZone('Test',
      [ FirstInterval, SecondInterval, ThirdInterval ], tailZone);
  var mapping = gapZone.mapLocal(ThirdInterval.isoLocalEnd.addHours(-1));
  expect(ThirdInterval, mapping.earlyInterval);
  expect(ThirdInterval, mapping.lateInterval);
  expect(1, mapping.count);
}

@Test()
void MapLocal_GapWithinPrecalculated()
{
  // Transition from +3 to +4 has a 1 hour gap
  expect(FirstInterval.isoLocalEnd < SecondInterval.isoLocalStart, isTrue);
  CheckMapping(FirstInterval.isoLocalEnd, FirstInterval, SecondInterval, 0);
}

@Test()
void MapLocal_SingleIntervalAroundTailZoneTransition()
{
  // Tail zone is fixed at +5. A local instant of one hour before the transition
  // from the precalculated zone (which is -5) will therefore give an instant from
  // the tail zone which occurs before the precalculated-to-tail transition,
  // and can therefore be ignored, resulting in an overall unambiguous time.
  var tailZone = FixedDateTimeZone.forOffset(Offset.hours(5));
  var gapZone = PrecalculatedDateTimeZone('Test',
      [ FirstInterval, SecondInterval, ThirdInterval ], tailZone);
  var mapping = gapZone.mapLocal(ThirdInterval.isoLocalEnd.addHours(-1));
  expect(ThirdInterval, mapping.earlyInterval);
  expect(ThirdInterval, mapping.lateInterval);
  expect(1, mapping.count);
}

@Test()
void MapLocal_GapAroundTailZoneTransition()
{
  // Tail zone is fixed at +5. A local time at the transition
  // from the precalculated zone (which is -5) will therefore give an instant from
  // the tail zone which occurs before the precalculated-to-tail transition,
  // and can therefore be ignored, resulting in an overall gap.
  var tailZone = FixedDateTimeZone.forOffset(Offset.hours(5));
  var gapZone = PrecalculatedDateTimeZone('Test',
      [ FirstInterval, SecondInterval, ThirdInterval ], tailZone);
  var mapping = gapZone.mapLocal(ThirdInterval.isoLocalEnd);
  expect(ThirdInterval, mapping.earlyInterval);
  expect(mapping.lateInterval,
      IZoneInterval.newZoneInterval('UTC+05', ThirdInterval.end, IInstant.afterMaxValue, Offset.hours(5), Offset.zero));
  expect(0, mapping.count);
}

@Test()
void MapLocal_GapAroundAndInTailZoneTransition()
{
  // Tail zone is -10 / +5, with the transition occurring just after
  // the transition *to* the tail zone from the precalculated zone.
  // A local time of one hour after the transition from the precalculated zone (which is -5)
  // will therefore be in the gap.
  var tailZone = SingleTransitionDateTimeZone.around(ThirdInterval.end + Time(hours: 1), -10, 5);
  var gapZone = PrecalculatedDateTimeZone('Test',
      [ FirstInterval, SecondInterval, ThirdInterval ], tailZone);
  var mapping = gapZone.mapLocal(ThirdInterval.isoLocalEnd.addHours(1));
  expect(ThirdInterval, mapping.earlyInterval);
  expect(IZoneInterval.newZoneInterval('Single-Early', ThirdInterval.end, tailZone.Transition, Offset.hours(-10), Offset.zero),
      mapping.lateInterval);
  expect(0, mapping.count);
}

@Test()
void GetZoneIntervals_NullTailZone_Eot()
{
  List<ZoneInterval> intervals =
  [
    IZoneInterval.newZoneInterval('foo', IInstant.beforeMinValue, Instant.fromEpochMicroseconds(2), Offset.zero, Offset.zero),
  IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(2), IInstant.afterMaxValue, Offset.zero, Offset.zero)
];
var zone = PrecalculatedDateTimeZone('Test', intervals, null);
expect(intervals[1], zone.getZoneInterval(Instant.maxValue));
}

void CheckMapping(LocalDateTime localDateTime, ZoneInterval earlyInterval, ZoneInterval lateInterval, int count)
{
  var mapping = TestZone.mapLocal(localDateTime);
  expect(earlyInterval, mapping.earlyInterval);
  expect(lateInterval, mapping.lateInterval);
  expect(count, mapping.count);
}

@Test()
void Validation_EmptyPeriodArray() {
  // Assert.Throws<ArgumentException>
  expect(() =>
      PrecalculatedDateTimeZone.validatePeriods([] /*new ZoneInterval[0]*/,
          DateTimeZone.utc), throwsArgumentError);
}

@Test()
void Validation_BadFirstStartingPoint() {
  List<ZoneInterval> intervals =
  [
    IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(1), Instant.fromEpochMicroseconds(2), Offset.zero, Offset.zero),
    IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(2), Instant.fromEpochMicroseconds(3), Offset.zero, Offset.zero)
  ];
  // Assert.Throws<ArgumentException>
  expect(() => PrecalculatedDateTimeZone.validatePeriods(intervals, DateTimeZone.utc), throwsArgumentError);
}

@Test()
void Validation_NonAdjoiningIntervals() {
  List<ZoneInterval> intervals =
  [
    IZoneInterval.newZoneInterval('foo', IInstant.beforeMinValue, Instant.fromEpochMicroseconds(2), Offset.zero, Offset.zero),
    IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(2).add(Time(nanoseconds: 500)), Instant.fromEpochMicroseconds(3), Offset.zero, Offset.zero)
  ];
  // Assert.Throws<ArgumentException>
  expect(() => PrecalculatedDateTimeZone.validatePeriods(intervals, DateTimeZone.utc), throwsArgumentError);
}

@Test()
void Validation_Success()
{
  List<ZoneInterval> intervals =
  [
    IZoneInterval.newZoneInterval('foo', IInstant.beforeMinValue, Instant.fromEpochMicroseconds(2), Offset.zero, Offset.zero),
  IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(2), Instant.fromEpochMicroseconds(3), Offset.zero, Offset.zero),
  IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(3), Instant.fromEpochMicroseconds(10), Offset.zero, Offset.zero),
  IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(10), Instant.fromEpochMicroseconds(20), Offset.zero, Offset.zero)
  ];
  PrecalculatedDateTimeZone.validatePeriods(intervals, DateTimeZone.utc);
}

@Test()
void Validation_NullTailZoneWithMiddleOfTimeFinalPeriod() {
  List<ZoneInterval> intervals =
  [
    IZoneInterval.newZoneInterval('foo', IInstant.beforeMinValue, Instant.fromEpochMicroseconds(2), Offset.zero, Offset.zero),
    IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(2), Instant.fromEpochMicroseconds(3), Offset.zero, Offset.zero)
  ];
  // Assert.Throws<ArgumentException>
  expect(() => PrecalculatedDateTimeZone.validatePeriods(intervals, null), throwsArgumentError);
}

@Test()
void Validation_NullTailZoneWithEotPeriodEnd()
{
  List<ZoneInterval> intervals =
  [
    IZoneInterval.newZoneInterval('foo', IInstant.beforeMinValue, Instant.fromEpochMicroseconds(2), Offset.zero, Offset.zero),
  IZoneInterval.newZoneInterval('foo', Instant.fromEpochMicroseconds(2), IInstant.afterMaxValue, Offset.zero, Offset.zero)
];
PrecalculatedDateTimeZone.validatePeriods(intervals, null);
}

//@Test()
//void Serialization()
//{
//  var stream = new MemoryStream();
//  var writer = new DateTimeZoneWriter(stream, null);
//  TestZone.Write(writer);
//  stream.Position = 0;
//  var reloaded = PrecalculatedDateTimeZone.Read(new DateTimeZoneReader(stream, null), TestZone.Id);
//
//  // Check equivalence by finding zone intervals
//  var interval = new Interval(new Instant.fromUtc(1990, 1, 1, 0, 0), new Instant.fromUtc(2010, 1, 1, 0, 0));
//  var originalZoneIntervals = TestZone.GetZoneIntervals(interval, ZoneEqualityComparer.Options.StrictestMatch).ToList();
//  var reloadedZoneIntervals = TestZone.GetZoneIntervals(interval, ZoneEqualityComparer.Options.StrictestMatch).ToList();
//  Collectionexpect(originalZoneIntervals, reloadedZoneIntervals);
//}

