-- -*- coding: utf-8 -*-
-- ProceduralMacros / Patterns.m2 -- declarative (pattern => template) macros.
--
-- The two primitives everything else re-skins:
--   matchPattern(pattern, input)  -- structural match; binds metavariables
--   instantiate(template, binding) -- splice bound subtrees into a template
-- A declarative macro pairs them: match the input, expand the template.
--
-- A metavariable `$x` binds (in a pattern) and splices (in a template). `$x` is
-- not valid M2 -- `parse` rejects `$` -- so pattern/template source is pre-scanned,
-- rewriting each `$x` to a marker leaf that the two primitives recognise.

-- the marker must be a valid M2 identifier (letter-led, no `_` -- that is the
-- subscript operator), distinctive enough not to collide with ordinary names
metavarMarker = "metavarHole"
toMarkers = src -> replace(///\$([A-Za-z][A-Za-z0-9]*)///, metavarMarker | "$1", src)

isMetavar = t -> isLeaf t and leftOf t =!= null and match("^" | metavarMarker, leftOf t)
metavarName = t -> substring(#metavarMarker, leftOf t)

-- accumulate name -> subtree bindings while walking pattern and input in lockstep;
-- a repeated metavariable must bind equal subtrees (a non-linear pattern)
matchInto = (pat, inp, b) -> (
    if isMetavar pat then (
        name := metavarName pat;
        if b#?name then toString b#name == toString inp
        else (b#name = inp; true)
    )
    else if leftOf pat =!= leftOf inp or rightOf pat =!= rightOf inp
         or delimiterOf pat =!= delimiterOf inp
         or #contentOf pat =!= #contentOf inp then false
    else (
        cs := contentOf pat; ds := contentOf inp;
        all(#cs, i -> matchInto(cs#i, ds#i, b))
    )
)

-- match a pattern tree against an input tree; the bindings, or null on mismatch
matchPattern = (pat, inp) -> (
    b := new MutableHashTable;
    if matchInto(pat, inp, b) then new HashTable from b else null
)

-- rebuild a template tree, splicing the bound subtree for each metavariable
instantiate = (tmpl, b) -> (
    if isMetavar tmpl then (
        name := metavarName tmpl;
        if not b#?name then error("template metavariable $" | name | " is unbound");
        b#name
    )
    else mkNode(leftOf tmpl, apply(contentOf tmpl, c -> instantiate(c, b)), rightOf tmpl, delimiterOf tmpl)
)

-- a declarative macro: parse the pattern and template once, then on each
-- invocation match the input and expand the template (error if no match)
declMacro = method()
declMacro(String, String, String) := Macro => (name, patternSrc, templateSrc) -> (
    pat := tokenTree cstParse toMarkers patternSrc;
    tmpl := tokenTree cstParse toMarkers templateSrc;
    installMacro(name, ts -> (
        b := matchPattern(pat, focus ts);
        if b === null then error(name | ": input does not match `" | patternSrc | "`");
        instantiate(tmpl, b)
    ))
)
