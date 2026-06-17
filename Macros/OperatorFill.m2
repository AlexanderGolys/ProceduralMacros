--------------------------------------------------------------------
-- OperatorFill -- fill dependent algebraic operators --------------
--------------------------------------------------------------------
--
-- If you define `T + T` for a type T, this macro can auto-generate
-- `T - T` via `T + (-T)`. Similarly, `T * T` implies `T / T` via
-- `T * (T^-1)` for invertible types.
--
-- Invocation: $OperatorFill{{ ... M2 code ... }}$
--
-- The macro receives the CST of the body and returns a transformed
-- CST containing the original definitions plus auto-generated ones.
--------------------------------------------------------------------

-- For now, identity — passes the CST through unchanged.
OperatorFill = cst -> cst

installMacro("OperatorFill", OperatorFill)

