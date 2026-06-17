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

-- a repetition ${ unit }+ / ${ unit }* matches a RUN of elements in a "," or ";"
-- sequence (the only nodes M2 makes genuinely n-ary, hence the only place repetition
-- stays a functor). Its own node KIND: the quantifier "+"/"*" is the Opening, the
-- separator "," / ";" is the Separator, and the unit (the per-repetition element
-- patterns) are the children. Metavars inside the unit bind to LISTS, one per rep.
Repetition = new SelfInitializingType of TokenTree

repetitionNode = (quantifier, sep, unit) -> Repetition(quantifier, unit, null, sep)
isRepetition = t -> instance(t, Repetition)
repQuantifier = t -> leftOf t
repSeparator = t -> delimiterOf t
repUnit = t -> contentOf t

-- a genuinely n-ary sequence node (the associative delimiters), never a repetition
isSeqNode = t -> not isRepetition t and (delimiterOf t === "," or delimiterOf t === ";")

-- the placeholder lives only between the pre-scan and the node conversion; its
-- prefix is reserved (a literal identifier starting with it is not supported)
metavarPlaceholderPrefix = "MetavarHolePlaceholder"
toPlaceholders = src -> replace(///\$([A-Za-z][A-Za-z0-9]*)///, metavarPlaceholderPrefix | "$1", src)

-- pre-scan: ${ P }+ / ${ P }* are not valid M2, so rewrite them to a function call
-- RepPlus( P ) / RepStar( P ) that parses normally and is recognised in markNodes.
-- Brace-balanced so a list literal {..} inside P is left alone; `$` before `{` opens.
repCallNames = new HashTable from {"+" => "RepPlus", "*" => "RepStar"}
scanReps = src -> (
    n := #src;
    at := i -> if i < n then substring(i, 1, src) else "";
    stack := {};                                  -- {bracePos, isRepOpen}
    spans := {};                                  -- {dollarPos, closeBracePos, quantifier}
    i := 0;
    while i < n do (
        c := at i;
        if c == "{" then (stack = append(stack, (i, i >= 1 and at(i-1) == "$")); i = i + 1)
        else if c == "}" then (
            if #stack == 0 then error "scanReps: unbalanced }";
            top := last stack; stack = drop(stack, -1);
            if top#1 and (at(i+1) == "+" or at(i+1) == "*")
            then spans = append(spans, (top#0 - 1, i, at(i+1)));
            i = i + 1)
        else i = i + 1);
    if #spans == 0 then return src;
    opens := hashTable apply(spans, s -> (s#0, repCallNames#(s#2) | "("));
    closes := set apply(spans, s -> s#1);
    out := ""; j := 0;
    while j < n do (
        if opens#?j then (out = out | opens#j; j = j + 2)          -- "${" -> "RepX("
        else if closes#?j then (out = out | ")"; j = j + 2)        -- "}+" / "}*" -> ")"
        else (out = out | at j; j = j + 1));
    out)

-- a RepPlus(...) / RepStar(...) application produced by scanReps
quantifierOf = t -> (
    if delimiterOf t === spaceOperator and #contentOf t == 2 and isLeaf (contentOf t)#0
    then (n := leftOf (contentOf t)#0; if n === "RepPlus" then "+" else if n === "RepStar" then "*")
    else null)

-- the unit of a repetition call: the bracket's inner elements, with the trailing
-- "null" element left by the conventional trailing separator (`$x,`) dropped
isNullElement = t -> isLeaf t and leftOf t === "null"
unitOf = t -> (
    inner := (contentOf (contentOf t)#1)#0;             -- RepX ( <inner> )
    sep := if isSeqNode inner then delimiterOf inner else ",";
    elems := if isSeqNode inner then contentOf inner else {inner};
    while #elems > 0 and isNullElement last elems do elems = drop(elems, -1);
    (sep, elems))

-- convert pre-scanned placeholders into nodes: metavar leaves -> Metavar, and
-- RepPlus/RepStar calls -> Repetition (its unit recursively converted)
markNodes = t -> (
    if isLeaf t then (
        if leftOf t =!= null and match("^" | metavarPlaceholderPrefix, leftOf t)
        then metavarNode substring(#metavarPlaceholderPrefix, leftOf t) else t)
    else if quantifierOf t =!= null then (
        (sep, elems) := unitOf t;
        repetitionNode(quantifierOf t, sep, apply(elems, markNodes)))
    else (setContent(t, apply(contentOf t, markNodes)); t))

-- parse a pattern/template source into a tree with metavar / repetition nodes. The
-- parse is pure and the result is treated read-only by matchPattern/instantiate, so
-- it is cached -- a quote-based macro body no longer re-parses its template each
-- call. A CacheTable (not a plain MutableHashTable) is the M2 idiom for memoised
-- computed values: it names the role, its contents stay invisible to === comparison.
templateCache = new CacheTable
parseTemplate = src -> (
    if not templateCache#?src
    then templateCache#src = markNodes tokenTree cstParse toPlaceholders scanReps src;
    templateCache#src)

-- the metavariable names appearing anywhere in a subtree (a repetition unit's holes)
metavarNamesIn = t -> (
    if isMetavar t then {metavarName t}
    else flatten apply(contentOf t, metavarNamesIn))

-- exact structural equality (boundaries, delimiter, arity, children) -- used for
-- non-linear patterns instead of re-flattening both subtrees to compare strings
treeEquals = (a, b) -> (
    leftOf a === leftOf b and rightOf a === rightOf b and delimiterOf a === delimiterOf b
    and #contentOf a == #contentOf b
    and all(#contentOf a, i -> treeEquals((contentOf a)#i, (contentOf b)#i)))

-- match a run of input elements against a repetition: consume them in chunks the
-- size of the unit, each chunk matched element-wise; every unit metavar accumulates
-- a list (one entry per chunk). "+" needs >= 1 chunk, "*" allows 0.
matchRepetition = (rep, ielems, b) -> (
    unit := repUnit rep; u := #unit;
    if u == 0 then error "empty ${ } repetition unit";
    if #ielems % u != 0 then return false;
    nChunks := #ielems // u;
    if repQuantifier rep === "+" and nChunks == 0 then return false;
    ok := all(nChunks, ci -> (
        tb := new MutableHashTable;
        chunkOK := all(u, j -> matchInto(unit#j, ielems#(ci * u + j), tb));
        if chunkOK then scan(keys tb, nm -> b#nm = append(if b#?nm then b#nm else {}, tb#nm));
        chunkOK));
    if ok and nChunks == 0 then scan(metavarNamesIn rep, nm -> if not b#?nm then b#nm = {});
    ok)

-- match a list of pattern elements (at most one of them a repetition) against a list
-- of input elements: fixed elements before/after match 1:1, the repetition covers
-- the remaining middle run
matchElems = (pelems, ielems, b) -> (
    reps := positions(pelems, isRepetition);
    if #reps == 0 then #pelems == #ielems and all(#pelems, i -> matchInto(pelems#i, ielems#i, b))
    else if #reps > 1 then error "a pattern sequence may hold at most one ${ } repetition"
    else (
        r := first reps;
        before := take(pelems, r);
        after := drop(pelems, r + 1);
        if #ielems < #before + #after then return false;
        nRep := #ielems - #before - #after;
        all(#before, i -> matchInto(before#i, ielems#i, b))
        and all(#after, i -> matchInto(after#i, ielems#(#before + nRep + i), b))
        and matchRepetition(pelems#r, take(drop(ielems, #before), nRep), b)))

-- accumulate name -> subtree bindings while walking pattern and input in lockstep; a
-- repeated metavariable must bind structurally-equal subtrees (non-linear pattern). A
-- repetition pattern (alone, or among a "," / ";" sequence) matches a variable run.
matchInto = (pat, inp, b) -> (
    if isMetavar pat then (
        name := metavarName pat;
        if b#?name then treeEquals(b#name, inp)
        else (b#name = inp; true)
    )
    else if isRepetition pat then
        matchRepetition(pat, if isSeqNode inp then contentOf inp else {inp}, b)
    else if isSeqNode pat and any(contentOf pat, isRepetition) then (
        if isSeqNode inp and delimiterOf pat === delimiterOf inp then matchElems(contentOf pat, contentOf inp, b)
        else if isSeqNode inp then false              -- a different delimiter cannot match
        else matchElems(contentOf pat, {inp}, b)      -- a single element is a run of one
    )
    -- a bracket whose sole content is a repetition: match its run against the input
    -- bracket's elements (0 for `()`, the sequence's children, or a lone element)
    else if #contentOf pat == 1 and isRepetition first contentOf pat
            and leftOf pat === leftOf inp and rightOf pat === rightOf inp
            and delimiterOf pat === delimiterOf inp then
        matchRepetition(first contentOf pat,
            flatten apply(contentOf inp, ic -> if isSeqNode ic then contentOf ic else {ic}), b)
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

-- expand a repetition template into its run of elements: the unit's list-valued
-- metavariables drive the repetition count (which must agree), and each rep
-- instantiates the unit against the i-th element of every such list
expandRepetition = (rep, b) -> (
    unit := repUnit rep;
    names := select(metavarNamesIn rep, nm -> b#?nm);
    lengths := unique apply(names, nm -> #(b#nm));
    if #lengths > 1 then error "template repetition metavariables have differing lengths";
    nReps := if #names == 0 then 0 else first lengths;
    flatten apply(nReps, i -> (
        perRep := hashTable apply(names, nm -> (nm, (b#nm)#i));
        apply(unit, u -> instantiate(u, perRep)))))

-- rebuild a template tree, splicing a fresh COPY of the bound subtree for each
-- metavariable -- copying so the result aliases neither the input nor a repeated
-- hole (editing one occurrence must not mutate the others or the macro input). A
-- repetition child expands to a run: spliced into an enclosing "," / ";" sequence,
-- or wrapped in a fresh such sequence when it is a bracket's sole content.
instantiate = (tmpl, b) -> (
    if isMetavar tmpl then (
        name := metavarName tmpl;
        if not b#?name
            then error("template metavariable $" | name | " is unbound");
        cloneTree b#name
    )
    else if any(contentOf tmpl, isRepetition) then (
        if isSeqNode tmpl then
            TokenTree(leftOf tmpl,
                flatten apply(contentOf tmpl, c -> if isRepetition c then expandRepetition(c, b) else {instantiate(c, b)}),
                rightOf tmpl, delimiterOf tmpl)
        else (
            rep := first select(contentOf tmpl, isRepetition);
            inner := delimited(repSeparator rep, expandRepetition(rep, b));
            TokenTree(leftOf tmpl, {inner}, rightOf tmpl, delimiterOf tmpl))
    )
    else TokenTree(leftOf tmpl, apply(contentOf tmpl, c -> instantiate(c, b)), rightOf tmpl, delimiterOf tmpl))

-- quote: instantiate a template written as source against name -> subtree
-- bindings. The output half of declarative macros, exposed so a procedural
-- `ts -> ...` body can build trees without string surgery. Bindings are given
-- inline as `"name" => node` options -- quote("print($e)", "e" => focus ts) --
-- which is lighter than wrapping them in a hashTable; a single HashTable is still
-- accepted (for programmatically-built bindings), and a template with no holes
-- needs no bindings at all.
quote = method(Dispatch => Thing)
quote String := TokenTree => src -> instantiate(parseTemplate src, new HashTable)
quote Sequence := TokenTree => s -> (
    rest := drop(s, 1);
    binding := if #rest == 1 and instance(first rest, HashTable) then first rest
               else hashTable apply(rest, o -> (toString o#0, o#1));
    instantiate(parseTemplate first s, binding))

-- search the whole subtree, not just the root: every (matched node, bindings) pair
-- in pre-order. A node and its descendants are all tested, so matches may nest. The
-- node is returned alongside its bindings so a caller can replace it in place or
-- instantiate a template against the bindings.
matchesIn = method()
matchesIn(TokenTree, TokenTree) := List => (pat, tree) -> (
    below := flatten apply(contentOf tree, c -> matchesIn(pat, c));
    here := matchPattern(pat, tree);
    if here =!= null then prepend((tree, here), below) else below)
-- a source pattern parses as a one-cell top-level ";" sequence; we search against
-- bare subtrees, so match the cell itself, not its sequence wrapper
patternCell = src -> (
    p := parseTemplate src;
    if delimiterOf p === ";" and #contentOf p == 1 then (contentOf p)#0 else p)
matchesIn(String, TokenTree) := List => (patSrc, tree) -> matchesIn(patternCell patSrc, tree)

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
