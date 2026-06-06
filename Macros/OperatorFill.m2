--------------------------------------------------------------------
-- OperatorFill -- fill dependent algebraic operators --------------
--------------------------------------------------------------------
--
-- If you define `T + T` for a type T, this macro can auto-generate
-- `T - T` via `T + (-T)`. Similarly, `T * T` implies `T / T` via
-- `T * (T^-1)` for invertible types.
--
-- Invocation:
--   @OperatorFill(MyType, "+" => "-", "+" => "Neg")
--     Generates subtraction from addition + negation.
--   @OperatorFill(MyType, "*" => "/", "*" => "Inv")
--     Generates division from multiplication + inverse.
--------------------------------------------------------------------

OperatorFill = method()
OperatorFill(Type, List) := (T, specs) -> (
    "TODO: CST-based operator fill macro"
    )

-- Register the macro
installMacro("OperatorFill", OperatorFill)
