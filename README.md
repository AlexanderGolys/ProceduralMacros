# ProceduralMacros

Procedural macros for Macaulay2, shipped as a regular M2 package. Uses the
built-in CST parser and `execute` to transform source code at compile/load
time without modifying the compiler.

## Install

```m2
installPackage "ProceduralMacros"
```

## Usage

```m2
needsPackage "ProceduralMacros"

-- register a macro
installMacro("MyMacro", node -> ...)

-- expand macros in source before executing
expandMacros " ... "
```

## License

MIT
