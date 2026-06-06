# ProceduralMacros

Procedural macros for Macaulay2, shipped as a regular M2 package. Uses the
built-in CST parser and `execute` to transform source code at compile/load
time without modifying the compiler.

## Obsidian Project Manifest

```yaml
project: ProceduralMacros
vault: ~/obsidian/flux
docs_root: projects/ProceduralMacros
index: Index
roadmap: Roadmap
features: Features
plans: Plans
decisions: Decisions
releases: Releases
```

## Commands

```bash
# Run tests
cd /home/flux/m2/ProceduralMacros && M2 --script -e 'check "ProceduralMacros"'

# Install package
cd /home/flux/m2/ProceduralMacros && M2 --script -e 'installPackage "ProceduralMacros"'
```

## Code conventions

- Macaulay2 package layout: declarations in `ProceduralMacros.m2`, tests
  inline via `TEST /// ... ///`, exports via `export { ... }`.
- Each procedural macro is a function in a separate file under `Macros/`.
- Use the CST parser (`parsing` package) to inspect/rewrite ASTs.
- Prefer `execute` for running generated code.
