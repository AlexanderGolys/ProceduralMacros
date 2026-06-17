-- -*- coding: utf-8 -*-
-- ProceduralMacros / Cst.m2 -- the CST layer.
--
-- TokenTree (the tree macros work on), the hook-based `tokenTree` that builds it
-- from `parse` output, TokenStream (a cursor into a mutable TokenTree), the
-- source-order DFS iterator, and source reconstruction. Loaded by the package
-- body before the macro layer; defines the exported names listed there.

--------------------------------------------------------------------
-- Vocabulary -- protected symbols, never strings
--------------------------------------------------------------------
-- A TokenTree node is a MutableHashTable carrying exactly these four fields, ALWAYS
-- present: the text fields default to null and Items to an empty list. So reading a
-- node never needs an existence check, and there is no separate "kind" -- a node is
-- fully described by which of its values are non-null. Keeping the keys as protected
-- symbols (not strings) lets the LSP index and rename them.
protect symbol Opening      -- boundary text before the content (leaf text / prefix op / open bracket)
protect symbol Closing      -- boundary text after the content  (postfix op / close bracket)
protect symbol Items        -- the child nodes, in order        (a MutableList, possibly empty)
protect symbol Separator    -- what is placed between items      (infix op, sequence delim, or a synthetic symbol)

-- The three synthetic separators are protected symbols rather than text, so
-- `instance(delim, Symbol)` distinguishes them from a real operator (a String).
protect symbol spaceOperator        -- juxtaposition / function application (M2's SPACE)
protect symbol whitespaceDelimiter  -- the gap between clauses of a control form
-- The boundary between top-level statements. `parse` conflates `;`, a newline, a
-- trailing `;` and even an illegal `;;` into one flat top-level list, but they are
-- NOT equivalent: a trailing `;` SUPPRESSES the statement's print (an overridable
-- callback), so it is genuinely different logic. So the top level is its OWN node --
-- statements joined by this separator, each suppressed statement wrapped `stmt;`
-- (a postfix `;`) -- distinct from an in-cell `;` sequence, which parse represents
-- faithfully and we leave as `delimited(";", ...)`. tokenTree alone cannot recover
-- which statements were suppressed (parse dropped that); parseWithComments does, by
-- re-scanning the source. (See Comments.m2.)
protect symbol statementSeparator

--------------------------------------------------------------------
-- Raw CST predicates (operate on parse's output)
--------------------------------------------------------------------
-- parse returns nested Lists of Strings; a node is {"<Tag>", child, ...} and a
-- leaf is {"Token", "<text>"}. The tag strings are M2's data format, not our
-- vocabulary, so they stay as String literals here.

isNode = x -> instance(x, BasicList) and #x > 0 and instance(x#0, String)
isTag = (node, tag) -> isNode node and node#0 == tag
isCSTToken = node -> isTag(node, "Token")
isDummy = node -> isTag(node, "dummy")
leafText = node -> node#1
kids = node -> if isNode node then drop(node, 1) else toList node

eofSentinel = "-*end of file*-"
isEOF = node -> isCSTToken node and node#1 == eofSentinel

-- the M2 keywords that parse strips, each rebuilt as a prefix clause:
quoteKeyword = new HashTable from {
    "Quote" => "symbol",
    "GlobalQuote" => "global",
    "LocalQuote" => "local",
    "ThreadQuote" => "threadLocal"
}

-- Control forms whose keywords parse strips, each as its keywords in child order
-- (so a keyword's child is the slot at its position). A slot that parse left empty
-- shows up as a dummy and its clause is dropped. (Arrow and the quote keywords are
-- handled by their own hooks below.)
keywordLayout = new HashTable from {
    "IfThen"      => {"if", "then"},
    "IfThenElse"  => {"if", "then", "else"},
    "WhileDo"     => {"while", "do"},
    "WhileList"   => {"while", "list"},
    "WhileListDo" => {"while", "list", "do"},
    "Try"         => {"try"},
    "TryThen"     => {"try", "then"},
    "TryElse"     => {"try", "else"},
    "TryThenElse" => {"try", "then", "else"},
    "New"         => {"new", "of", "from"},
    "For"         => {"for", "in", "from", "to", "when", "list", "do"}
}

-- the binary operators that build associative sequences (flattened on construction)
sequenceDelimiters = set {",", ";"}

--------------------------------------------------------------------
-- TokenTree -- the tree macros work on
--------------------------------------------------------------------
-- One uniform node shape covers everything: a node flattens to
--     Opening  <Items joined by Separator>  Closing
-- so this single shape and one flatten method cover leaf / prefix / postfix /
-- infix / sequence / application / bracket alike, with no separate "kind".

TokenTree = new SelfInitializingType of MutableHashTable

-- the constructor: TokenTree(opening, items, closing, separator) builds a node, and
-- every node carries all four fields. It is installed as the type's own `new from`
-- (which is why TokenTree is a SelfInitializingType) rather than a standalone helper,
-- so a subtype constructs the same way and `type` keeps the requested subclass --
-- Comment(...) / Metavar(...) reuse this one layout and yield their own class.
new TokenTree from Sequence := (type, s) -> new type from {
    Opening => s#0,
    Items => new MutableList from s#1,
    Closing => s#2,
    Separator => s#3
}

--------------------------------------------------------------------
-- Constructors -- strict-typed methods. Operands are real TokenTree nodes (build a
-- text leaf with `leaf`); the small genuine type unions are handled by installing
-- one body over several domains, never by a catch-all `Thing`.
--------------------------------------------------------------------

leaf = method()
leaf String := TokenTree => s -> TokenTree(s, {}, null, null)

-- two operands joined by an operator. The operator is a real operator String, or a
-- synthetic Symbol: juxtaposition (`f x`) is just a binary operator whose symbol is
-- spaceOperator, so application is an infix and needs no constructor of its own.
infix = method()
infix(TokenTree, String, TokenTree) :=
infix(TokenTree, Symbol, TokenTree) := (l, op, r) -> TokenTree(null, {l, r}, null, op)

prefix = method()
prefix(String, TokenTree) := TokenTree => (op, r) -> TokenTree(op, {r}, null, null)

postfix = method()
postfix(TokenTree, String) := TokenTree => (l, op) -> TokenTree(null, {l}, op, null)

-- n operands joined by a delimiter (a real delimiter String, or the synthetic
-- whitespaceDelimiter Symbol of a clause sequence)
delimited = method()
delimited(String, BasicList) :=
delimited(Symbol, BasicList) := (delim, items) -> TokenTree(null, toList items, null, delim)

-- a fenced node; the inner is a TokenTree, or absent for an empty `()`
bracketed = method()
bracketed(String, TokenTree, String) := TokenTree => (o, inner, c) -> TokenTree(o, {inner}, c, null)
bracketed(String, Nothing, String) := TokenTree => (o, inner, c) -> TokenTree(o, {}, c, null)

-- a comment is its own node KIND, not a separator or a flavour of leaf: a
-- self-initializing subtype of TokenTree built with the same Comment(...) constructor
-- as a plain node, so instance(t, Comment) tells it apart from a string/identifier
-- leaf and every TokenTree accessor still dispatches to it by inheritance. Its full
-- text (including the -- or -* *- delimiters) is the Opening, so it flattens verbatim;
-- the other three fields stay at their leaf defaults.
Comment = new SelfInitializingType of TokenTree

commentNode = method()
commentNode String := Comment => text -> Comment(text, {}, null, null)

isComment = method()
isComment TokenTree := Boolean => t -> instance(t, Comment)


--------------------------------------------------------------------
-- Accessors and predicates (a field reads back as its value, null when unset)
--------------------------------------------------------------------

contentOf = method()
contentOf TokenTree := List => t -> toList t#Items

isLeaf = method()
isLeaf TokenTree := Boolean => t -> #t#Items == 0

leftOf = method()
leftOf TokenTree := String => t -> t#Opening

rightOf = method()
rightOf TokenTree := String => t -> t#Closing

-- a delimiter is either a real operator (String) or a synthetic symbol, so no
-- single typical value is declared
delimiterOf = method()
delimiterOf TokenTree := t -> t#Separator

length TokenTree := ZZ => t -> #contentOf t
TokenTree _ ZZ := TokenTree => (t, i) -> (contentOf t)#i

--------------------------------------------------------------------
-- Mutation in place (strict-typed methods): boundary text and a user-set delimiter
-- are Strings; an item is a TokenTree node (use `leaf` to wrap text).
--------------------------------------------------------------------

setLeft = method()
setLeft(TokenTree, String) := String => (t, s) -> t#Opening = s

setRight = method()
setRight(TokenTree, String) := String => (t, s) -> t#Closing = s

-- the synthetic Symbol delimiters come only from the constructors / parse; a
-- hand-set delimiter is a real operator, i.e. a String
setDelimiter = method()
setDelimiter(TokenTree, String) := String => (t, d) -> t#Separator = d

setItem = method()
setItem(TokenTree, ZZ, TokenTree) := TokenTree => (t, i, v) -> (t#Items)#i = v

appendItem = method()
appendItem(TokenTree, TokenTree) := TokenTree => (t, v) -> (
    t#Items = new MutableList from append(contentOf t, v); t)

--------------------------------------------------------------------
-- Construction: raw CST -> TokenTree (tag dispatch via hooks)
--------------------------------------------------------------------

-- An empty element of a delimited sequence is the value null -- `(a,,b)` is
-- `(a, null, b)` -- so it round-trips as a leaf whose text is the M2 null literal.
nullElement = () -> leaf "null"

-- collapse a run of the same delimiter into a flat list of operand trees. A
-- leading delimiter (`, a`) parses as a Unary with a missing left side; a lone
-- trailing one yields a dummy operand.
flattenSpine = (node, delim) -> (
    if isTag(node, "Binary") and leafText(node#2) == delim then
        join(flattenSpine(node#1, delim), flattenSpine(node#3, delim))
    else if isTag(node, "Unary") and leafText(node#1) == delim then
        prepend(nullElement(), flattenSpine(node#2, delim))
    else if isDummy node then {nullElement()}
    else {tokenTree node}
)

-- a control form becomes a whitespace-delimited sequence of `keyword <child>`
-- prefix clauses; an optional clause is dropped when its child slot is a dummy
buildClauses = (c, layout) -> for i to #layout - 1 list (
    if isDummy c#i then continue;
    prefix(layout#i, tokenTree c#i)
)

-- tokenTree maps a raw CST node onto a TokenTree. The leaf, top-level-sequence
-- and dangling-EOF cases are handled directly; every tagged node is dispatched
-- through hooks, so the recognized tag set is open -- a new construct is added
-- with another addHook, and an unrecognized tag falls through to a clear error.
tokenTree = method()
tokenTree BasicList := TokenTree => node -> (
    if isEOF node then 
        error "tokenTree: a dangling quote keyword consumed EOF";
    if isCSTToken node then
        leaf leafText node
    else if not isNode node then
        -- the top-level statement list: its own node KIND, NOT a `;` sequence (see the
        -- statementSeparator note). Every statement starts out un-suppressed here;
        -- parseWithComments marks the suppressed ones from the source.
        delimited(statementSeparator, apply(toList node, tokenTree))
    else (
        built := runHooks(symbol tokenTree, node);
        if built === null then 
            error("tokenTree: unhandled CST tag " | node#0);
        built
    )
)

addHook(symbol tokenTree, node -> if isTag(node, "Binary") then (
    op := leafText node#2;
    if sequenceDelimiters#?op then
        delimited(op, flattenSpine(node, op))
    else infix(tokenTree node#1, op, tokenTree node#3)
))
-- juxtaposition is an infix whose operator is the synthetic spaceOperator
addHook(symbol tokenTree, node -> if isTag(node, "Adjacent") then
    infix(tokenTree node#1, spaceOperator, tokenTree node#2))

addHook(symbol tokenTree, node -> if isTag(node, "Unary") then (
    op := leafText node#1;
    if sequenceDelimiters#?op then delimited(op, flattenSpine(node, op))
    else if isDummy node#2 then leaf op
    else prefix(op, tokenTree node#2)
))
addHook(symbol tokenTree, node -> if isTag(node, "Postfix") then
    postfix(tokenTree node#1, leafText node#2))

addHook(symbol tokenTree, node -> if isTag(node, "Arrow") then
    infix(tokenTree node#1, "->", tokenTree node#2))

addHook(symbol tokenTree, node -> if isTag(node, "Parentheses") then (
    c := kids node; bracketed(leafText first c, tokenTree c#1, leafText last c)))

addHook(symbol tokenTree, node -> if isTag(node, "EmptyParentheses") then (
    c := kids node; bracketed(leafText first c, null, leafText last c)))

-- quote keywords (symbol/global/local/threadLocal), table-driven
addHook(symbol tokenTree, node -> if isNode node and quoteKeyword#?(node#0) then
    prefix(quoteKeyword#(node#0), tokenTree node#1))

-- control forms (if/while/for/try/new), table-driven
addHook(symbol tokenTree, node -> if isNode node and keywordLayout#?(node#0) then
    delimited(whitespaceDelimiter, buildClauses(kids node, keywordLayout#(node#0))))

-- `parse` mutates its argument in place, so hand it a fresh copy (s | "") to keep
-- the caller's string intact -- this is load-bearing, not a no-op.
cstParse = s -> parse(s | "")

cstToSource = root -> sourceOf tokenTree root

--------------------------------------------------------------------
-- Reconstruction: TokenTree -> source (the inverse of tokenTree)
--------------------------------------------------------------------

-- sourceOf wraps flatten to absorb a null child
sourceOf = t -> if t === null then "" else flatten t

-- the visible separator between items: a real operator is padded with spaces; a
-- synthetic separator (application / clause gap) collapses to a single space
separatorOf = t -> (
    d := delimiterOf t;
    if d === statementSeparator then "\n"          -- top-level statements sit on their own lines
    else if d === null or instance(d, Symbol) then " " else " " | d | " "
)

-- join a node's children. A recovered comment carries its own surrounding
-- newlines and is NOT wrapped in the node's operator separator (a `;`/`,`/`+`
-- around a comment would be wrong, and a trailing `--` comment must end the line
-- so it does not swallow what follows); ordinary children join with the separator.
joinChildren = (sep, cs) -> (
    if #cs == 0 then return "";
    piece := c -> if isComment c then "\n" | leftOf c | "\n" else sourceOf c;
    out := piece first cs;
    for i from 1 to #cs - 1 do (
        glue := if isComment cs#(i - 1) or isComment cs#i then "" else sep;
        out = out | glue | piece cs#i
    );
    out
)

flatten TokenTree := String => t -> (
    body := joinChildren(separatorOf t, contentOf t);
    pre := leftOf t ?? "";
    post := rightOf t ?? "";
    demark(" ", select({pre, body, post}, s -> s != ""))
)

--------------------------------------------------------------------
-- Token classification (derived on demand, never stored)
--------------------------------------------------------------------
-- The lexical class of a token's text -- information the tree shape does NOT
-- show. The class names stay Strings: they are display labels, and the obvious
-- symbol forms (Symbol, Keyword) already name M2 types.
m2Keywords = set select(keys Core.Dictionary, s -> instance(Core.Dictionary#s, Keyword))

tokenClass = method()
tokenClass String := String => s -> (
    if #s == 0 then "punctuation"
    else if match(///^(--|-\*)///, s) then "comment"
    else if s#0 == "\"" or match("^[0-9]", s) then "literal"
    else if match("^[A-Za-z]", s) then
        if m2Keywords#?s then "keyword" else "symbol"
    else "punctuation"
)

--------------------------------------------------------------------
-- Display: an indented tree with box-drawing connectors
--------------------------------------------------------------------

indentBranches = blocks -> flatten apply(#blocks, i -> (
    block := blocks#i;
    isLast := i == #blocks - 1;
    connector := if isLast then "└─ " else "├─ ";
    indent := if isLast then "   " else "│  ";
    apply(#block, j -> (if j == 0 then connector else indent) | block#j)
))

labelFor = s -> tokenClass s | " " | format s
capitalize = s -> if #s == 0 then s else toUpper substring(0, 1, s) | substring(1, s)

-- the header names the node's characteristic token by its lexical class, read
-- straight off the fields: a delimiter names the join (the synthetic ones name
-- their role), a fence pair names a bracket, else the boundary token
nodeLabel = t -> (
    if isComment t then "comment " | format leftOf t
    else (
    d := delimiterOf t;
    if d =!= null then (
        if d === spaceOperator then "apply"
        else if d === statementSeparator then "statements"
        else if d === whitespaceDelimiter then (
            cs := contentOf t;
            if #cs == 0 then "clauses" else capitalize leftOf cs#0
        )
        else labelFor d
    )
    else if leftOf t =!= null and rightOf t =!= null then leftOf t | " " | rightOf t
    else if leftOf t =!= null then labelFor leftOf t
    else if rightOf t =!= null then labelFor rightOf t
    else "·"
    )
)

treeBlock = t -> (
    if t === null then {"·"}
    else (
        children := contentOf t;
        if #children == 0 then {nodeLabel t}
        else prepend(nodeLabel t, indentBranches apply(children, treeBlock))
    )
)

-- net shows the structure (an indented tree); the linear forms show the source
net TokenTree := Net => t -> stack treeBlock t
toString TokenTree := String => t -> sourceOf t
texMath TokenTree := String => t -> texMath sourceOf t

--------------------------------------------------------------------
-- TokenStream -- a cursor into a (mutable) TokenTree
--------------------------------------------------------------------
-- A cursor is the chain of nodes from the root down to the focused node (held as
-- a List in ts#0). It stores node *references*, not content indices, so a
-- structural edit elsewhere in the shared tree -- inserting or removing a sibling
-- -- cannot silently repoint it: every node keeps its identity. Nodes are mutable,
-- so an edit below the focus is seen through every cursor that shares the tree.

TokenStream = new Type of BasicList

tokenStream = method()
tokenStream TokenTree := TokenStream => root -> new TokenStream from {{root}}

-- the chain of nodes; rootOf / focus are its two ends
chainOf = ts -> ts#0
rootOf = ts -> first chainOf ts

focus = method()
focus TokenStream := TokenTree => ts -> last chainOf ts

atTop = method()
atTop TokenStream := Boolean => ts -> #chainOf ts == 1

childCount = method()
childCount TokenStream := ZZ => ts -> #contentOf focus ts

-- navigation: each move returns a new cursor over the same (mutable) tree
child = method()
child(TokenStream, ZZ) := TokenStream => (ts, i) ->
    new TokenStream from {append(chainOf ts, (contentOf focus ts)#i)}

up = method()
up TokenStream := TokenStream => ts -> (
    if atTop ts then
        error "up: already at the root";
    new TokenStream from {drop(chainOf ts, -1)}
)

-- ascend to the root (the cursor at the top of the same tree)
root = method()
root TokenStream := TokenStream => ts -> new TokenStream from {{rootOf ts}}

-- the focused node's index among its parent's children (located by identity, so it
-- is correct however the siblings have shifted); null at the root, which has none
childIndex = method()
childIndex TokenStream := ts -> if atTop ts then null else indexInParent ts

-- move to the sibling `offset` positions over (offset 0 is the focus itself,
-- 1 the next sibling, -1 the previous): up to the parent, then down to that child
siblingOf = method()
siblingOf(TokenStream, ZZ) := TokenStream => (ts, offset) -> (
    if atTop ts then error "siblingOf: the root has no siblings";
    child(up ts, childIndex ts + offset))

length TokenStream := ZZ => ts -> childCount ts
-- `_` descends to a child; its dual `^` ascends k levels (k = 0 is the focus, k = 1
-- the parent). M2 has no usable prefix `&`, so the terse ascend is this binary `^`.
TokenStream _ ZZ := TokenStream => (ts, i) -> child(ts, i)
TokenStream ^ ZZ := TokenStream => (ts, k) -> (
    if k < 0 then error "TokenStream ^ k: cannot ascend a negative number of levels";
    if k >= #chainOf ts then error "TokenStream ^ k: cannot ascend past the root";
    new TokenStream from {take(chainOf ts, #chainOf ts - k)})

net TokenStream := Net => ts -> ("TokenStream @ depth " | toString(#chainOf ts - 1)) || net focus ts

--------------------------------------------------------------------
-- Editing through the cursor (mutates the shared tree in place)
--------------------------------------------------------------------

-- make target become a copy of src while keeping target's object identity; the
-- Items list is cloned so the two nodes do not share one mutable content list
overwrite = (target, src) -> (
    scan(keys target, k -> remove(target, k));
    scan(keys src, k -> target#k = if k === Items then new MutableList from src#k else src#k);
    target
)

-- store a content list back on a node (Items is always present, empty when none)
setContent = (node, items) -> (node#Items = new MutableList from items; node)

-- the focused node's parent, and the focused node's position within it -- located
-- by identity, so it is correct no matter how the siblings have since shifted
parentOf = ts -> (chainOf ts)#(#chainOf ts - 2)
indexInParent = ts -> position(contentOf parentOf ts, c -> c === focus ts)

-- replace the focused subtree (the returned cursor points at the replacement)
replaceFocus = method()
replaceFocus(TokenStream, TokenTree) := TokenStream => (ts, n) -> (
    if atTop ts then (overwrite(rootOf ts, n); ts)
    else (
        p := parentOf ts;
        (p#Items)#(indexInParent ts) = n;
        new TokenStream from {append(drop(chainOf ts, -1), n)}
    )
)

-- detach the focused subtree from its parent; the cursor moves up to the parent
removeFocus = method()
removeFocus TokenStream := TokenStream => ts -> (
    if atTop ts then 
        error "removeFocus: the root has no parent to detach it from";
    p := parentOf ts;
    i := indexInParent ts;
    setContent(p, drop(contentOf p, {i, i}));
    up ts
)

-- splice a node into the focused node's content; prepend / append are the two ends
insertContent = method()
insertContent(TokenStream, ZZ, TokenTree) := TokenStream => (ts, i, node) -> (
    f := focus ts;
    setContent(f, insert(i, node, contentOf f));
    ts
)

prependContent = method()
prependContent(TokenStream, TokenTree) := TokenStream => (ts, node) -> insertContent(ts, 0, node)

appendContent = method()
appendContent(TokenStream, TokenTree) := TokenStream => (ts, node) -> insertContent(ts, childCount ts, node)

--------------------------------------------------------------------
-- Iteration -- a source-order DFS over the focused subtree
--------------------------------------------------------------------
-- The twist that keeps the walk in source order: a node with a left boundary (a
-- leaf / prefix / bracket -- its head token comes first) is read out BEFORE its
-- children; a node without one (an infix / sequence / postfix / application, whose
-- operator or delimiter sits BETWEEN operands) is read out right AFTER its first
-- child. So `for c in ts do (...)` visits every subtree once, in token order, each
-- `c` a live cursor you can read (`focus c`) or edit in place.

hasBoundary = ts -> leftOf focus ts =!= null

dfsCursors = ts -> (
    kids := apply(childCount ts, i -> ts_i);
    if hasBoundary ts then prepend(ts, flatten apply(kids, dfsCursors))
    else if #kids == 0 then {ts}
    else join(dfsCursors first kids, {ts}, flatten apply(drop(kids, 1), dfsCursors))
)

iterator TokenStream := ts -> (
    nodes := dfsCursors ts;
    i := 0;
    Iterator(() -> if i >= #nodes then StopIteration else (c := nodes#i; i = i + 1; c))
)
