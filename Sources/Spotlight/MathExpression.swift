import Foundation

/// A number flowing through the evaluator. `isPercent` marks values that
/// came from a postfix percent (`10%` -> 0.1) so `+` / `-` can apply them
/// relative to the left operand: `150 + 10%` is `150 * 1.1`.
struct MathValue: Equatable, Sendable {
  let value: Double
  let isPercent: Bool

  init(_ value: Double, isPercent: Bool = false) {
    self.value = value
    self.isPercent = isPercent
  }
}

/// Shunting-yard evaluator for the token stream produced by
/// `MathTokenizer`. Supports `+ - * / % ^`, prefix negation, postfix
/// percent, and parentheses.
enum MathExpression {
  static let operators: Set<Character> = ["+", "-", "*", "/", "%", "^"]
  /// Internal token for prefix negation (`-2`, `3 * -(1 + 1)`).
  static let unaryMinus: Character = "~"

  enum Token: Equatable {
    case number(MathValue)
    case op(Character)
    /// Postfix percent: divides its operand by 100 and tags it.
    case percent
    case lparen
    case rparen

    var isBinaryOperator: Bool {
      if case .op(let op) = self { return op != MathExpression.unaryMinus }
      return false
    }
  }

  /// Evaluates an infix token stream.
  /// - Complexity: O(n) in the number of tokens.
  static func evaluate(_ tokens: [Token]) -> MathValue? {
    guard let rpn = shuntingYard(tokens) else { return nil }
    return evaluateRPN(rpn)
  }

  // MARK: Shunting yard

  private static func precedence(_ op: Character) -> Int {
    switch op {
    case "+", "-": return 1
    case "*", "/", "%": return 2
    // Negation binds tighter than * / % but looser than ^, so
    // `-2^2 == -4` and `2^-1 == 0.5`.
    case unaryMinus: return 3
    case "^": return 4
    default: return 0
    }
  }

  private static func isRightAssociative(_ op: Character) -> Bool {
    op == "^" || op == unaryMinus
  }

  private static func shuntingYard(_ tokens: [Token]) -> [Token]? {
    var output: [Token] = []
    var stack: [Token] = []
    for token in tokens where !applyToken(token, output: &output, stack: &stack) {
      return nil
    }
    while let top = stack.popLast() {
      if case .lparen = top { return nil }
      output.append(top)
    }
    return output
  }

  private static func applyToken(_ token: Token, output: inout [Token], stack: inout [Token]) -> Bool {
    switch token {
    case .number, .percent:
      // Postfix percent binds tighter than anything and its operand is
      // already complete in `output`, so it is emitted immediately.
      output.append(token)
    case .op(let op):
      // Prefix operators have no left operand, so nothing on the stack
      // can be reduced before them.
      if op != unaryMinus {
        drainOperators(higherThan: op, output: &output, stack: &stack)
      }
      stack.append(token)
    case .lparen:
      stack.append(token)
    case .rparen:
      return drainToLParen(output: &output, stack: &stack)
    }
    return true
  }

  private static func drainOperators(
    higherThan op: Character,
    output: inout [Token],
    stack: inout [Token]
  ) {
    while let top = stack.last, case .op(let topOp) = top {
      let topPrec = precedence(topOp)
      let curPrec = precedence(op)
      guard topPrec > curPrec || (topPrec == curPrec && !isRightAssociative(op)) else { return }
      output.append(stack.removeLast())
    }
  }

  private static func drainToLParen(output: inout [Token], stack: inout [Token]) -> Bool {
    while let top = stack.last {
      if case .lparen = top {
        stack.removeLast()
        return true
      }
      output.append(stack.removeLast())
    }
    return false
  }

  // MARK: RPN evaluation

  private static func evaluateRPN(_ rpn: [Token]) -> MathValue? {
    var stack: [MathValue] = []
    for token in rpn {
      switch token {
      case .number(let value):
        stack.append(value)
      case .percent:
        guard let operand = stack.popLast() else { return nil }
        stack.append(MathValue(operand.value / 100, isPercent: true))
      case .op(let op) where op == unaryMinus:
        guard let operand = stack.popLast() else { return nil }
        stack.append(MathValue(-operand.value, isPercent: operand.isPercent))
      case .op(let op):
        guard let rhs = stack.popLast(), let lhs = stack.popLast() else { return nil }
        guard let value = applyBinary(op, lhs, rhs) else { return nil }
        stack.append(value)
      case .lparen, .rparen:
        return nil
      }
    }
    return stack.count == 1 ? stack[0] : nil
  }

  /// `+` / `-` with a plain left operand and a percent right operand is
  /// relative (`150 - 10%` = 135). Two percents add as percents
  /// (`50% + 10%` = 60%). Everything else is plain arithmetic on the
  /// already-divided value (`20% of 150` = `0.2 * 150`).
  private static func applyBinary(_ op: Character, _ lhs: MathValue, _ rhs: MathValue) -> MathValue? {
    let isAdditive = op == "+" || op == "-"
    if isAdditive, rhs.isPercent, !lhs.isPercent {
      let factor = op == "+" ? 1 + rhs.value : 1 - rhs.value
      return MathValue(lhs.value * factor)
    }
    guard let raw = applyRaw(op, lhs.value, rhs.value) else { return nil }
    return MathValue(raw, isPercent: isAdditive && lhs.isPercent && rhs.isPercent)
  }

  private static func applyRaw(_ op: Character, _ lhs: Double, _ rhs: Double) -> Double? {
    switch op {
    case "+": return lhs + rhs
    case "-": return lhs - rhs
    case "*": return lhs * rhs
    case "/":
      guard rhs != 0 else { return nil }
      return lhs / rhs
    case "%":
      guard rhs != 0 else { return nil }
      return lhs.truncatingRemainder(dividingBy: rhs)
    case "^": return pow(lhs, rhs)
    default: return nil
    }
  }
}
