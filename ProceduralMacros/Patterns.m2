-- -*- coding: utf-8 -*-
-- ProceduralMacros / Patterns.m2 -- declarative (pattern => template) macros.
--
-- The two primitives everything else re-skins:
--   matchPattern(pattern, input)   -- structural match; binds metavariables
--   instantiate(template, binding) -- splice bound subtrees into a template
-- A declarative macro pairs them: match the input, expand the template.
--
-- A metavariable `$x` binds (in a pattern) and splices (in a template). `$x` is
-- not valid M2 -- `parse` rejects `$` -- so pattern/template source is pre-scanned:
-- each `$x` becomes a reserved placeholder identifier, parsed, then converted to a
-- dedicated metavar NODE (a Metavar, its own TokenTree subtype). Because a metavar
-- is its own node type, it can never collide with a real identifier leaf; and INPUT
-- trees are never marked, so only the reserved placeholder prefix is unavailable
-- inside a pattern or template.

-- a metavar is its own node KIND, like Comment: a self-initializing subtype of
-- TokenTree built with the same Metavar(...) constructor as a plain node, so
-- instance(t, Metavar) tells a hole apart from a real leaf and every accessor still
-- dispatches by inheritance. The metavariable name is its Opening; it has no children.
Metavar = new SelfInitializingType of TokenTree

metavarNode = method()
metavarNode String := Metavar => name -> Metavar(name, {}, null, null)

isMetavar = t -> instance(t, Metavar)
metavarName = t -> leftOf t

-- the placeholder lives only between the pre-scan and the node conversion; its
-- prefix is reserved (a literal identifier starting with it is not supported)
metavarPlaceholderPrefix = "MetavarHolePlaceholder"
toPlaceholders = src -> replace(///\$([A-Za-z][A-Za-z0-9]*)///, metavarPlaceholderPrefix | "$1", src)
markMetavars = t -> (
    if isLeaf t and leftOf t =!= null and match("^" | metavarPlaceholderPrefix, leftOf t)
    then metavarNode substring(#metavarPlaceholderPrefix, leftOf t)
    else (setContent(t, apply(contentOf t, markMetavars)); t))

-- parse a pattern/template source into a tree with metavar nodes. The parse is
-- pure and the result is treated read-only by matchPattern/instantiate, so it is
-- cached -- a quote-based macro body no longer re-parses its template each call.
templateCache = new MutableHashTable
parseTemplate = src -> (
    if not templateCache#?src
    then templateCache#src = markMetavars tokenTree cstParse toPlaceholders src;
    templateCache#src)

-- exact structural equality (boundaries, delimiter, arity, children) -- used for
-- non-linear patterns instead of re-flattening both subtrees to compare strings
treeEquals = (a, b) -> (
    leftOf a === leftOf b and rightOf a === rightOf b and delimiterOf a === delimiterOf b
    and #contentOf a == #contentOf b
    and all(#contentOf a, i -> treeEquals((contentOf a)#i, (contentOf b)#i)))

-- accumulate name -> subtree bindings while walking pattern and input in lockstep;
-- a repeated metavariable must bind structurally-equal subtrees (non-linear pattern)
matchInto = (pat, inp, b) -> (
    if isMetavar pat then (
        name := metavarName pat;
        if b#?name then treeEquals(b#name, inp)
        else (b#name = inp; true)
    )
    else if leftOf pat =!= leftOf inp or rightOf pat =!= rightOf inp
         or delimiterOf pat =!= delimiterOf inp
         or #contentOf pat =!= #contentOf inp then false
    else (
        cs := contentOf pat; ds := contentOf inp;
        all(#cs, i -> matchInto(cs#i, ds#i, b))
    ))

-- match a pattern tree against an input tree; the bindings, or null on mismatch
matchPattern = (pat, inp) -> (
    b := new MutableHashTable;
    if matchInto(pat, inp, b) then new HashTable from b else null)

-- a deep copy of a tree, so a spliced subtree never aliases the input or a sibling
cloneTree = t -> TokenTree(leftOf t, apply(contentOf t, cloneTree), rightOf t, delimiterOf t)

-- rebuild a template tree, splicing a fresh COPY of the bound subtree for each
-- metavariable -- copying so the result aliases neither the input nor a repeated
-- hole (editing one occurrence must not mutate the others or the macro input)
instantiate = (tmpl, b) -> (
    if isMetavar tmpl then (
        name := metavarName tmpl;
        if not b#?name
            then error("template metavariable $" | name | " is unbound");
        cloneTree b#name
    )
    else TokenTree(leftOf tmpl, apply(contentOf tmpl, c -> instantiate(c, b)), rightOf tmpl, delimiterOf tmpl))

-- quote: instantiate a template written as source against a name -> subtree
-- binding. The output half of declarative macros, exposed so a procedural
-- `ts -> ...` body can build trees without string surgery.
quote = method()
quote(String, HashTable) := TokenTree => (templateSrc, binding) ->
    instantiate(parseTemplate templateSrc, binding)

-- expand the first (pattern, template) rule whose pattern matches the input
expandRules = (name, rules, inp) -> (
    for r in rules do (
        (pat, tmpl) := r;
        b := matchPattern(pat, inp);
        if b =!= null then
            return instantiate(tmpl, b)
    ); error(name | ": no rule matched the input"))

-- a declarative macro: a list of (pattern, template) source pairs, tried in order;
-- each pair is parsed once. A rule may be a {p, t} list or a (p, t) sequence.
declMacro = method()

declMacro(String, List) := Macro => (name, rules) -> (
    scan(rules, r -> if not ((instance(r, Sequence) or instance(r, List)) and #r == 2) then
        error(name | ": each rule must be a (pattern, template) pair, got " | toString r));
    parsed := apply(rules, r -> (parseTemplate r#0, parseTemplate r#1));
    installMacro(name, ts -> expandRules(name, parsed, focus ts)))

declMacro(String, String, String) := Macro => (name, p, t) -> declMacro(name, {(p, t)})
