import Foundation

/// A unit the conversion syntax (`5 km in mi`) understands. Values
/// convert through a per-dimension base unit: metre, gram, second, byte,
/// and degree Celsius. `base = (value + offset) * factor`, where only
/// temperatures use a non-zero offset.
struct MathUnit: Sendable {
  enum Dimension: Sendable {
    case length
    case mass
    case time
    case data
    case temperature
  }

  let dimension: Dimension
  let factor: Double
  let offset: Double

  init(_ dimension: Dimension, _ factor: Double, offset: Double = 0) {
    self.dimension = dimension
    self.factor = factor
    self.offset = offset
  }

  func toBase(_ value: Double) -> Double { (value + offset) * factor }
  func fromBase(_ base: Double) -> Double { base / factor - offset }

  /// Every unit spelled `name`, case-insensitively. Most names are
  /// unique; `m` is both metre and minute and the caller picks by
  /// dimension (`5m in ft` vs `3h 20m in min`).
  static func units(named name: String) -> [MathUnit] {
    table[name.lowercased()] ?? []
  }

  private static let table: [String: [MathUnit]] = {
    var table: [String: [MathUnit]] = [:]
    for (aliases, unit) in definitions {
      for alias in aliases { table[alias.lowercased(), default: []].append(unit) }
    }
    return table
  }()

  private static let definitions: [([String], MathUnit)] =
    lengthUnits + massUnits + timeUnits + dataUnits + temperatureUnits

  private static let lengthUnits: [([String], MathUnit)] = [
    (["mm", "millimeter", "millimeters", "millimetre", "millimetres"], MathUnit(.length, 0.001)),
    (["cm", "centimeter", "centimeters", "centimetre", "centimetres"], MathUnit(.length, 0.01)),
    (["m", "meter", "meters", "metre", "metres"], MathUnit(.length, 1)),
    (["km", "kilometer", "kilometers", "kilometre", "kilometres"], MathUnit(.length, 1000)),
    (["in", "inch", "inches"], MathUnit(.length, 0.0254)),
    (["ft", "foot", "feet"], MathUnit(.length, 0.3048)),
    (["yd", "yard", "yards"], MathUnit(.length, 0.9144)),
    (["mi", "mile", "miles"], MathUnit(.length, 1609.344))
  ]

  private static let massUnits: [([String], MathUnit)] = [
    (["mg", "milligram", "milligrams"], MathUnit(.mass, 0.001)),
    (["g", "gram", "grams"], MathUnit(.mass, 1)),
    (["kg", "kilogram", "kilograms"], MathUnit(.mass, 1000)),
    (["lb", "lbs", "pound", "pounds"], MathUnit(.mass, 453.59237)),
    (["oz", "ounce", "ounces"], MathUnit(.mass, 28.349523125))
  ]

  private static let timeUnits: [([String], MathUnit)] = [
    (["ms", "millisecond", "milliseconds"], MathUnit(.time, 0.001)),
    (["s", "sec", "secs", "second", "seconds"], MathUnit(.time, 1)),
    (["m", "min", "mins", "minute", "minutes"], MathUnit(.time, 60)),
    (["h", "hr", "hrs", "hour", "hours"], MathUnit(.time, 3600)),
    (["d", "day", "days"], MathUnit(.time, 86400)),
    (["wk", "week", "weeks"], MathUnit(.time, 604_800))
  ]

  /// KB / MB / GB / TB are decimal (powers of 1000, as Finder reports);
  /// KiB / MiB / GiB / TiB are binary.
  private static let dataUnits: [([String], MathUnit)] = [
    (["b", "byte", "bytes"], MathUnit(.data, 1)),
    (["kb"], MathUnit(.data, 1e3)),
    (["mb"], MathUnit(.data, 1e6)),
    (["gb"], MathUnit(.data, 1e9)),
    (["tb"], MathUnit(.data, 1e12)),
    (["kib"], MathUnit(.data, 1024)),
    (["mib"], MathUnit(.data, 1_048_576)),
    (["gib"], MathUnit(.data, 1_073_741_824)),
    (["tib"], MathUnit(.data, 1_099_511_627_776))
  ]

  private static let temperatureUnits: [([String], MathUnit)] = [
    (["c", "°c", "celsius"], MathUnit(.temperature, 1)),
    (["f", "°f", "fahrenheit"], MathUnit(.temperature, 5.0 / 9.0, offset: -32)),
    (["k", "kelvin"], MathUnit(.temperature, 1, offset: -273.15))
  ]
}
