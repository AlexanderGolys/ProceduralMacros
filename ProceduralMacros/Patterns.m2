-- -*- coding: utf-8 -*-
-- ProceduralMacros / Patterns.m2 -- declarative (pattern => template) macros.
--
-- The two primitives everything else re-skins:
--   matchPattern(pattern, input)   -- structural match; binds metavariables
--   instantiate(template, binding) -- splice bound subtrees into a template
-- A declarative macro pairs them: match the input, expand the template.
--
-- A metavariable `'x` binds (in a pattern) and splices (in a template). The sigil is
-- a leading apostrophe (NOT `$`, which is reserved for macro application) -- a leading
-- `'` is a parse error, so it is free to pre-scan, while a trailing/interior `'` stays
-- a normal prime identifier (f', x'). Each `'x` becomes a reserved placeholder
-- identifier, parsed, then converted to a dedicated metavar NODE (a Metavar, its own
-- TokenTree subtype). A hole may be typed, `'x:If`, to bind only nodes of that kind.
-- Because a metavar is its own node type it never collides with a real identifier
-- leaf; INPUT trees are never marked, so only the reserved prefixes are unavailable.

-- a metavar is its own node KIND, like Comment: a self-initializing subtype of
-- TokenTree built with the same Metavar(...) constructor as a plain node, so
-- instance(t, Metavar) tells a hole apart from a real leaf and every accessor still
-- dispatches by inheritance. The metavariable name is its Opening; it has no children.
-- a metavar optionally carries a KIND constraint (from `'x:If`): the kind name
-- lives in the Separator slot, null when the hole is untyped.
Metavar = new SelfInitializingType of TokenTree

metavarNode = method()
metavarNode String := Metavar => name -> Metavar(name, {}, null, null)
metavarNode(String, String) := Metavar => (name, kind) -> Metavar(name, {}, null, kind)

isMetavar = t -> instance(t, Metavar)
metavarName = t -> leftOf t
metavarKind = t -> delimiterOf t

-- a repetition '{ unit }+ / '{ unit }* matches a RUN of elements in a "," or ";"
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

-- an alternation '{ a | b | ... } matches if ANY of its branches matches the same
-- input node (a variant rule). Its own node KIND, like Metavar / Repetition: the
-- branch patterns are its children, the other three fields are null. It is a
-- PATTERN-only construct -- meaningless in a template, where instantiate rejects it.
-- The branch that matches contributes its bindings; a branch that fails leaves none.
Alternation = new SelfInitializingType of TokenTree

alternationNode = branches -> Alternation(null, branches, null, null)
isAlternation = t -> instance(t, Alternation)
altBranches = t -> contentOf t

-- a genuinely n-ary sequence node (the freely-associative delimiters: "," and ";",
-- plus the top-level statement list, which is "," / ";"'s associative sibling), never
-- a repetition. These are the only nodes a repetition / element match may range over.
isSeqNode = t -> not isRepetition t and
    (delimiterOf t === "," or delimiterOf t === ";" or delimiterOf t === statementSeparator)

-- the matchable KIND of a node, derived from the four fields (nothing stored). Most
-- distinctions are structural; the one the shape can't make -- String vs Number, both
-- leaf literals -- is read off the token text (a string keeps its quotes). Specific
-- values are matched literally in the pattern; kinds are for matching by category.
nodeKind = t -> (
    if isComment t then "Comment"
    else if isMetavar t then "Metavar"
    else if isRepetition t then "Repetition"
    else if isAlternation t then "Alternation"
    else if isLeaf t then (
        s := leftOf t;
        if s === null then "Node"
        else if s#0 == "\"" then "String"
        else if match("^[0-9]", s) then "Number"
        else if match("^[A-Za-z]", s) then (if m2Keywords#?s then "Keyword" else "Identifier")
        else "Operator")
    else (
        d := delimiterOf t;
        if d === spaceOperator then "Apply"
        else if d === statementSeparator then "Statements"   -- the top-level statement list
        else if d === whitespaceDelimiter then (
            cs := contentOf t; if #cs == 0 then "Clause" else capitalize leftOf cs#0)  -- If/While/For/Try/New
        else if d === "," or d === ";" then "Sequence"
        else if d === "->" then "Arrow"
        else if instance(d, String) then "Infix"
        else if leftOf t =!= null and rightOf t =!= null then "Bracket"
        else if leftOf t =!= null then "Prefix"
        else if rightOf t =!= null then "Postfix"
        else "Node"))

-- the kinds a `'x:Kind` hole may name (control forms contribute If/While/For/Try/New)
nodeKindNames = set {"Comment", "Metavar", "Repetition", "Alternation", "String",
    "Number", "Keyword", "Identifier", "Operator", "Apply", "Sequence", "Arrow",
    "Infix", "Bracket", "Prefix", "Postfix", "If", "While", "For", "Try", "New",
    "Statements", "Clause", "Node"}

-- a metavariable is written 'name (leading apostrophe), NOT $name -- the $ sigil is
-- reserved for macro APPLICATION, so patterns use ' to avoid the clash. A leading '
-- is a parse error (free for us to pre-scan); a trailing or interior ' is a normal
-- prime identifier (f', x'), so the sigil only fires when not preceded by an
-- identifier character. Both placeholders below are reserved identifier prefixes.
-- A typed hole `'x:If` is rewritten to a call MetavarKindIf( <name placeholder> ) --
-- atomic, so it never tangles with operator precedence -- and recognised in markNodes.
metavarPlaceholderPrefix = "MetavarHolePlaceholder"
metavarKindPrefix = "MetavarKind"
toPlaceholders = src -> (
    typed := replace(///(?<![A-Za-z0-9'])'([A-Za-z][A-Za-z0-9]*):([A-Za-z][A-Za-z0-9]*)///,
        concatenate(metavarKindPrefix, "$2(", metavarPlaceholderPrefix, "$1)"), src);
    replace(///(?<![A-Za-z0-9'])'([A-Za-z][A-Za-z0-9]*)///, metavarPlaceholderPrefix | "$1", typed))

-- pre-scan: the brace forms '{ P }+ / '{ P }* / '{ A | B } are not valid M2, so
-- rewrite each to a function call -- RepPlus(P) / RepStar(P) / Alt(A|B) -- that parses
-- normally and is recognised in markNodes. The form is fixed by what follows `}`: a
-- trailing `+`/`*` is a repetition, anything else an alternation (its branches are
-- separated by the ordinary `|` infix). Brace-balanced, so a list literal {..} inside
-- is left alone; a `'` before `{` opens only when it is not a prime on an identifier
-- (so f'{..} is left alone).
repCallNames = new HashTable from {"+" => "RepPlus", "*" => "RepStar", "|" => "Alt"}
isIdentChar = c -> match("[A-Za-z0-9']", c)
scanReps = src -> (
    n := #src;
    at := i -> if i >= 0 and i < n then substring(i, 1, src) else "";   -- "" off either end (negative would wrap)
    stack := {};                                  -- {bracePos, isBraceFormOpen}
    spans := {};                                  -- {sigilPos, closeBracePos, form}
    for i to n - 1 do (
        c := at i;
        if c == "{" then (
            isFormOpen := i >= 1 and at(i-1) == "'" and (i < 2 or not isIdentChar at(i-2));
            stack = append(stack, (i, isFormOpen)))
        else if c == "}" then (
            if #stack == 0 then error "scanReps: unbalanced }";
            top := last stack; stack = drop(stack, -1);
            -- `}+` / `}*` is a repetition; a `'{`-opened brace with neither is alternation
            -- (form "|", the brace consumes only `}`); the `|` separators are kept verbatim
            if top#1 then (
                form := if at(i+1) == "+" or at(i+1) == "*" then at(i+1) else "|";
                spans = append(spans, (top#0 - 1, i, form)))));
    if #spans == 0 then return src;
    opens := hashTable apply(spans, s -> (s#0, repCallNames#(s#2) | "("));
    closes := hashTable apply(spans, s -> (s#1, if s#2 === "|" then 1 else 2));
    out := ""; j := 0;
    while j < n do (
        if opens#?j then (out |= opens#j; j += 2)          -- "'{" -> "RepX(" / "Alt("
        else if closes#?j then (out |= ")"; j += closes#j) -- "}+"/"}*"/"}" -> ")"
        else (out |= at j; j += 1));
    out)

-- a RepPlus(...) / RepStar(...) application produced by scanReps
quantifierOf = t -> (
    if delimiterOf t === spaceOperator and #contentOf t == 2 and isLeaf (contentOf t)#0
    then (n := leftOf (contentOf t)#0; if n === "RepPlus" then "+" else if n === "RepStar" then "*"))

-- the unit of a repetition call: the bracket's inner elements, with the trailing
-- "null" element left by the conventional trailing separator (`'x,`) dropped
isNullElement = t -> isLeaf t and leftOf t === "null"
unitOf = t -> (
    inner := (contentOf (contentOf t)#1)#0;             -- RepX ( <inner> )
    sep := if isSeqNode inner then delimiterOf inner else ",";
    elems := if isSeqNode inner then contentOf inner else {inner};
    while #elems > 0 and isNullElement last elems do elems = drop(elems, -1);
    (sep, elems))

-- an Alt(...) application produced by scanReps for an alternation '{ A | B }; returns
-- the inner tree (the `|` infix chain) or null when t is not such a call
altCallName = "Alt"
altInnerOf = t -> (
    if delimiterOf t === spaceOperator and #contentOf t == 2 and isLeaf (contentOf t)#0
       and leftOf (contentOf t)#0 === altCallName
    then (inner := contentOf (contentOf t)#1;
        if #inner == 0 then error "empty '{ | } alternation"; inner#0))

-- flatten the left-associative `|` infix spine into the list of alternation branches
-- ('{ a | b | c } parses as ((a|b)|c)), so a, b, c are recovered as three branches)
altBranchesOf = t -> (
    if delimiterOf t === "|" and #contentOf t == 2
    then join(altBranchesOf (contentOf t)#0, altBranchesOf (contentOf t)#1)
    else {t})

-- a MetavarKind<Kind>( <name placeholder> ) call produced for a typed hole `'x:If`;
-- returns the named kind, or null when t is not such a call
typedKindOf = t -> (
    if delimiterOf t === spaceOperator and #contentOf t == 2 and isLeaf (contentOf t)#0
       and match("^" | metavarKindPrefix, leftOf (contentOf t)#0)
    then substring(#metavarKindPrefix, leftOf (contentOf t)#0))

-- convert pre-scanned placeholders into nodes: metavar leaves -> Metavar, typed-hole
-- calls -> Metavar with a kind, and RepPlus/RepStar calls -> Repetition (unit recursed)
markNodes = t -> (
    if isLeaf t then (
        if leftOf t =!= null and match("^" | metavarPlaceholderPrefix, leftOf t)
        then metavarNode substring(#metavarPlaceholderPrefix, leftOf t) else t)
    else if typedKindOf t =!= null then (
        kind := typedKindOf t;
        if not nodeKindNames#?kind then error("unknown node kind in pattern: '" | kind);
        hole := leftOf (contentOf (contentOf t)#1)#0;     -- the name placeholder leaf
        metavarNode(substring(#metavarPlaceholderPrefix, hole), kind))
    else if quantifierOf t =!= null then (
        (sep, elems) := unitOf t;
        repetitionNode(quantifierOf t, sep, apply(elems, markNodes)))
    else if altInnerOf t =!= null then
        alternationNode apply(altBranchesOf altInnerOf t, markNodes)
    else (setContent(t, apply(contentOf t, markNodes)); t))

-- parse a pattern/template source into a tree with metavar / repetition nodes. The
-- parse is pure and the result is treated read-only by matchPattern/instantiate, so
-- it is cached -- a quote-based macro body no longer re-parses its template each
-- call. A CacheTable (not a plain MutableHashTable) is the M2 idiom for memoised
-- computed values: it names the role, its contents stay invisible to === comparison.
templateCache = new CacheTable
parseTemplate = src -> templateCache#src ??= markNodes tokenTree cstParse toPlaceholders scanReps src

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
    if u == 0 then error "empty '{ } repetition unit";
    -- a unit metavar accumulates a LIST across chunks; if the same name is already
    -- bound to a single subtree (reused from outside the repetition) the accumulation
    -- is ill-defined, so reject it up front rather than crashing on the list append
    scan(metavarNamesIn rep, nm -> if b#?nm and not instance(b#nm, List) then
        error("metavariable '" | nm | " is bound both outside and inside a repetition"));
    if #ielems % u != 0 then return false;
    nChunks := #ielems // u;
    if repQuantifier rep === "+" and nChunks == 0 then return false;
    ok := all(nChunks, ci -> (
        tb := new MutableHashTable;
        chunkOK := all(u, j -> matchInto(unit#j, ielems#(ci * u + j), tb));
        if chunkOK then scan(keys tb, nm -> b#nm = append(b#nm ?? {}, tb#nm));
        chunkOK));
    if ok and nChunks == 0 then scan(metavarNamesIn rep, nm -> b#nm ??= {});
    ok)

-- match a list of pattern elements (at most one of them a repetition) against a list
-- of input elements: fixed elements before/after match 1:1, the repetition covers
-- the remaining middle run
matchElems = (pelems, ielems, b) -> (
    reps := positions(pelems, isRepetition);
    if #reps == 0 then #pelems == #ielems and all(#pelems, i -> matchInto(pelems#i, ielems#i, b))
    else if #reps > 1 then error "a pattern sequence may hold at most one '{ } repetition"
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
        if metavarKind pat =!= null and nodeKind inp =!= metavarKind pat then false
        else (
            name := metavarName pat;
            if b#?name then treeEquals(b#name, inp)
            else (b#name = inp; true))
    )
    else if isAlternation pat then (
        -- try each branch on a private table; commit the first that matches AND agrees
        -- with bindings already made (a repeated metavar must stay structurally equal)
        matched := false;
        for branch in altBranches pat when not matched do (
            tb := new MutableHashTable;
            if matchInto(branch, inp, tb) and all(keys tb, k -> not b#?k or treeEquals(b#k, tb#k))
            then (scan(keys tb, k -> b#k = tb#k); matched = true));
        matched
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
    if matchInto(pat, inp, b) then new HashTable from b)

-- a deep copy of a tree, so a spliced subtree never aliases the input or a sibling.
-- `class t` keeps the node's exact (sub)type -- a cloned Comment / Metavar stays one
cloneTree = t -> (class t)(leftOf t, apply(contentOf t, cloneTree), rightOf t, delimiterOf t)

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
    if isAlternation tmpl then
        error "alternation '{ a | b } is a pattern-only construct, not valid in a template";
    if isMetavar tmpl then (
        name := metavarName tmpl;
        if not b#?name
            then error("template metavariable '" | name | " is unbound");
        cloneTree b#name
    )
    else if any(contentOf tmpl, isRepetition) then (
        if isSeqNode tmpl then
            TokenTree(leftOf tmpl,
                flatten apply(contentOf tmpl, c -> if isRepetition c then expandRepetition(c, b) else {instantiate(c, b)}),
                rightOf tmpl, delimiterOf tmpl)
        -- a repetition only expands into a run, which needs a delimiter to splice into:
        -- a "," / ";" sequence (handled above) or a bracket whose SOLE content it is.
        -- Anywhere else (e.g. `1 + '{ 'x }+`) the run has no home -- fail fast rather
        -- than silently dropping the repetition's siblings.
        else (
            if #contentOf tmpl != 1 then
                error "a repetition '{ }+ in a template must be the only content of a sequence or bracket";
            rep := first contentOf tmpl;
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
-- a source pattern parses as a one-cell top-level statement list; we search against
-- bare subtrees, so match the cell itself, not its statement-list wrapper
patternCell = src -> (
    p := parseTemplate src;
    if delimiterOf p === statementSeparator and #contentOf p == 1 then (contentOf p)#0 else p)
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
