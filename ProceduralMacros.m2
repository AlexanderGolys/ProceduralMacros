newPackage(
    "ProceduralMacros",
    Version => "0.1",
    Date => "Jun 6, 2026",
    Headline => "procedural macros for Macaulay2",
    Authors => {
        {Name => "Flux", Email => "flux@example.com"}
    },
    Keywords => {"Macros", "Metaprogramming"},
    AuxiliaryFiles => false,
    DebuggingMode => true
    )

needsPackage "Parsing"

export {
    "MacroRegistry",
    "installMacro",
    "expandMacros",
    "parseSource"
    }

--------------------------------------------------------------------
-- Macro registry --------------------------------------------------
--------------------------------------------------------------------

MacroRegistry = new MutableHashTable

installMacro = method()
installMacro String := name -> (
    error "installMacro: second argument (function) required"
    )
installMacro(String, Function) := (name, fn) -> (
    MacroRegistry#name = fn;
    printerr("/// installed macro: " | name);
    )

--------------------------------------------------------------------
-- Source parsing --------------------------------------------------
--------------------------------------------------------------------

-- Parse a string of M2 source into a CST node (stub).
parseSource = method()
parseSource String := src -> (
    error "parseSource: not yet implemented"
    )

--------------------------------------------------------------------
-- Macro expansion -------------------------------------------------
--------------------------------------------------------------------

-- Expand all registered macros in a source string.
-- Scans for macro invocations of the form @macroName(...)
-- and replaces them with the macro's output.
expandMacros = method()
expandMacros String := src -> (
    -- TODO: implement CST walk + macro invocation detection
    src
    )

--------------------------------------------------------------------
-- Load macros from file -------------------------------------------
--------------------------------------------------------------------

-- Load a macro definition from a file in the Macros/ directory.
loadMacro = method()
loadMacro String := filename -> (
    path := currentFileDirectory | "Macros/" | filename;
    if not fileExists path then error("Macro file not found: " | path);
    load path
    )

beginDocumentation()

doc ///
Key
  ProceduralMacros
Headline
  procedural macros for Macaulay2
Description
  Text
    This package provides procedural macro facilities for Macaulay2
    using the built-in CST parser and execute.
///

-- Load built-in macros
loadMacro "OperatorFill.m2"

TEST /// -* placeholder *-
assert(true)
///

-- restart
-- debug needsPackage "ProceduralMacros"
-- check "ProceduralMacros"
--
-- uninstallPackage "ProceduralMacros"
-- restart
-- installPackage "ProceduralMacros"
-- viewHelp "ProceduralMacros"
