-- -*- coding: utf-8 -*-
newPackage(
    "ProceduralMacros",
    Version => "0.1",
    Date => "June 15, 2026",
    Authors => {
        {Name => "Alexander Golys", Email => "visuallyexplained2137@gmail.com"}
    },
    Headline => "Rust-style procedural macros for Macaulay2",
    Keywords => {"Programming"},
    DebuggingMode => false,
    AuxiliaryFiles => true
)

export {
    "installMacro", "expandSource", "runSource",
    "Macro", "nameOf", "transformOf", "macroNamed", "expandMacro", "declMacro", "quote", "Metavar", "Repetition", "matchesIn",
    "TokenTree", "tokenTree",
    "leaf", "infix", "prefix", "postfix", "delimited", "bracketed",
    "spaceOperator", "whitespaceDelimiter", "Comment",
    "commentNode", "isComment", "attachComments", "parseWithComments",
    "isLeaf", "tokenClass",
    "leftOf", "rightOf", "delimiterOf", "contentOf",
    "setLeft", "setRight", "setDelimiter", "setItem", "appendItem",
    "TokenStream", "tokenStream", "focus", "child", "up", "childCount", "atTop",
    "replaceFocus", "removeFocus", "appendContent", "prependContent", "insertContent",
    "cstParse", "cstToSource"
}

-- The CST layer lives in an auxiliary file; the macro layer below builds on it.
load "./ProceduralMacros/Cst.m2"

-- comment recovery (re-scans the source to re-attach the comments parse discards)
load "./ProceduralMacros/Comments.m2"

--------------------------------------------------------------------
-- Macro -- a named source-to-source transform
--------------------------------------------------------------------
-- A Macro wraps a name and a transform on a TokenStream. Constructing one (via
-- installMacro) registers it under its name; both the scanner and the `value`
-- wrapper resolve a `$name` through the registry. The transform returns the
-- expansion as a TokenStream (a cursor) or a bare TokenTree.

MacroRegistry = new MutableHashTable

Macro = new Type of BasicList       -- {name, transform}

nameOf = method()
nameOf Macro := String => m -> m#0

transformOf = method()
transformOf Macro := Function => m -> m#1

net Macro := Net => m -> net ("$" | nameOf m)

-- the constructor: dispatch enforces (name, transform), and building one installs
-- it into the registry under its name
installMacro = method()
installMacro(String, Function) := Macro => (name, fn) ->
    MacroRegistry#name = new Macro from {name, fn}

-- resolve a registered macro by name (a typo'd $name must fail, not pass silently)
macroNamed = method()
macroNamed String := Macro => name -> (
    if not MacroRegistry#?name then error("unknown macro $" | name);
    MacroRegistry#name)

-- a macro's expansion reduces to source: it returns a TokenStream or a TokenTree
resultSource = r -> (
    if instance(r, TokenStream) then sourceOf rootOf r
    else if instance(r, TokenTree) then sourceOf r
    else error "macro must return a TokenStream or a TokenTree"
)

-- run a macro on a freshly-parsed block, yielding its expansion as source
expandMacro = method()
expandMacro(Macro, String) := String => (m, block) ->
    resultSource (transformOf m)(tokenStream tokenTree cstParse block)

--------------------------------------------------------------------
-- Source scanning & macro expansion
--------------------------------------------------------------------
-- A macro invocation is `$name <block> $`: the sigil `$` sits at a word boundary,
-- immediately followed by the name; the block runs to a bare closing `$` (one
-- preceded by whitespace and not followed by a name character). Expansion scans
-- the raw source, copying string literals and comments through verbatim, so a `$`
-- inside them is never read as a sigil -- there is no in-band escaping to collide.

isSpaceChar = c -> match(///\s///, c)
isNameChar = c -> match("[A-Za-z0-9]", c)

-- the index just past the lexical construct that starts at i: a string literal
-- (honouring \" escapes), a -- line comment, or a -* *- block comment
pastString = (src, i) -> (
    n := #src; j := i + 1;
    while j < n and src#j != "\"" do j = if src#j == "\\" then j + 2 else j + 1;
    if j < n then j + 1 else n
)
pastLineComment = (src, i) -> (
    n := #src; j := i + 2;
    while j < n and src#j != "\n" do j = j + 1;
    j
)
pastBlockComment = (src, i) -> (
    n := #src; j := i + 2;
    while j + 1 < n and substring(j, 2, src) != "*-" do j = j + 1;
    if j + 1 < n then j + 2 else n
)

-- the index just past whichever lexical construct starts at k, else k+1
pastConstruct = (src, k) -> (
    if src#k == "\"" then pastString(src, k)
    else if k + 1 < #src and substring(k, 2, src) == "--" then pastLineComment(src, k)
    else if k + 1 < #src and substring(k, 2, src) == "-*" then pastBlockComment(src, k)
    else k + 1
)

-- a `$` at i opens an invocation iff it is at a word boundary and a name follows
opensMacro = (src, i) -> src#i == "$" and (i == 0 or isSpaceChar src#(i - 1)) and
    i + 1 < #src and isNameChar src#(i + 1)

-- a `$` at k closes the block iff it is whitespace-separated and not a new sigil
closesMacro = (src, k) -> src#k == "$" and (k == 0 or isSpaceChar src#(k - 1)) and
    (k + 1 >= #src or not isNameChar src#(k + 1))

-- expand the invocation that opens at i; returns (expanded source, index past it)
expandInvocation = (src, i) -> (
    n := #src;
    j := i + 1;
    while j < n and isNameChar src#j do j = j + 1;
    m := macroNamed substring(i + 1, j - i - 1, src);
    k := j;
    while k < n and not closesMacro(src, k) do k = pastConstruct(src, k);
    if k >= n then error("expandSource: unterminated macro $" | nameOf m);
    (expandMacro(m, substring(j, k - j, src)), k + 1)
)

-- walk the source, expanding invocations and copying everything else verbatim
expandSource = src -> (
    out := "";
    i := 0;
    n := #src;
    while i < n do (
        (piece, next) := (
            if opensMacro(src, i) then expandInvocation(src, i)
            else (j := pastConstruct(src, i); (substring(i, j - i, src), j))
        );
        out = out | piece;
        i = next
    );
    out
)

runSource = src -> value expandSource src

--------------------------------------------------------------------
-- value wrapper -- evaluating source expands its macros first
--------------------------------------------------------------------
-- So `value someSource` (and the REPL, indirectly) expands `$name <block> $`
-- invocations before evaluating. The sigil pre-check is coarse -- a `$` before a
-- letter -- but a false positive is harmless: a `$` only inside a string literal
-- or comment is reproduced verbatim by expandSource, so the result is unchanged.
-- The base evaluator is the compiled primitive `value'` fetched from Core, never
-- this wrapper, so reinstalling it on a package reload cannot recurse.
macroSigil = ///\$[A-Za-z]///
-- value' is M2 Core's compiled string-evaluator; it has no public accessor, so we
-- reach it once through Core's private dictionary -- asserting it is present, to
-- fail loudly rather than silently if a future M2 renames it. Delegating to the
-- primitive (never to `value` itself) is what keeps this wrapper from recursing
-- into itself when the package is reloaded in a live session.
assert ((Core#"private dictionary")#?"value'")
valuePrimitive = value (Core#"private dictionary")#"value'"
value String := s -> valuePrimitive(if match(macroSigil, s) then expandSource s else s)

-- a File evaluates by the very same path: read its contents, then dispatch as
-- source -- so `value openIn "f.m2"` expands the macros in a file just as
-- `value "..."` expands them in a string. NOTE: `load`/`needs` use M2's own
-- compiled file reader, not `value`, so they do NOT expand macros -- evaluate a
-- macro file with `value openIn` (a macro-aware loader is future work).
value File := f -> value get f

-- Declarative (pattern => template) macros build on the macro layer above.
load "./ProceduralMacros/Patterns.m2"

--------------------------------------------------------------------
-- Built-in demo macros
--------------------------------------------------------------------

installMacro("show", ts -> (
    e := focus ts;
    quote("print($label | toString($e))",
        hashTable{"label" => leaf format(toString e | " = "), "e" => e})
))

installMacro("sig", ts -> (
    bin := focus (ts_0);
    if not (delimiterOf bin =!= null and length bin == 2 and delimiterOf bin =!= spaceOperator) then
        error "sig: expected a binary expression `a op b`";
    lhs := toString bin_0;
    op := delimiterOf bin;
    rhs := toString bin_1;
    tokenTree cstParse concatenate(
        "print(", format(op | " : ("),
        " | toString class (", lhs, ") | ", format ", ",
        " | toString class (", rhs, ") | ", format ") -> ",
        " | toString class (", lhs, " ", op, " ", rhs, "))"
    )
))

-- Documentation is intentionally omitted while the API is in flux.
beginDocumentation()

--------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------

TEST ///
  assert ( cstToSource cstParse "f(a, b) + 3" == "f ( a , b ) + 3" )
///

TEST ///
  -- a declarative macro: pattern => template, with $-metavariables
  declMacro("commute", "$a + $b", "$b + $a");
  assert ( expandSource "$commute 2 + x*y $" == "x * y + 2" )       -- binds, swaps, splices
  declMacro("dup", "$x", "($x, $x)");
  assert ( expandSource "$dup f a $" == "( f a , f a )" )           -- one metavar, used twice
  -- a non-matching input is rejected
  assert ( (try expandSource "$commute 2 * 3 $" else "rejected") == "rejected" )
///

TEST ///
  -- multiple rules, tried in order; first match wins, no match errors
  declMacro("flip", {("$a + $b", "$b + $a"), ("$a * $b", "$b * $a")});
  assert ( expandSource "$flip 1 + 2 $" == "2 + 1" )
  assert ( expandSource "$flip 3 * 4 $" == "4 * 3" )
  assert ( (try expandSource "$flip 1 - 2 $" else "no rule") == "no rule" )
///

TEST ///
  -- quote: build output from a template + binding (the procedural-authoring win)
  installMacro("twice2", ts -> quote("2 * ($e)", hashTable{"e" => focus ts}));
  assert ( expandSource "$twice2 3 + 4 $" == "2 * ( 3 + 4 )" )
///

TEST ///
  -- quote splices a COPY: repeated metavars are independent and the bound input
  -- is never aliased, so editing the result cannot mutate the input or a sibling
  e = leaf "x";
  t = quote("($v, $v)", hashTable{"v" => e});
  seq = (t_0)_0;                       -- the comma sequence inside the brackets
  assert ( seq_0 =!= seq_1 )           -- the two $v slots are distinct objects
  assert ( seq_0 =!= e and seq_1 =!= e )   -- and neither aliases the bound input
///

TEST ///
  assert ( expandSource "$show 1 + 2 $" == "print ( \"1 + 2 = \" | toString ( 1 + 2 ) )" )
///

TEST ///
  installMacro("twice", ts -> tokenTree cstParse ("2 * (" | toString focus ts | ")"));
  assert ( expandSource "$twice 3 + 4 $" == "2 * ( 3 + 4 )" )
///

TEST ///
  -- the cursor navigates the TokenTree: focus / child (_) / length
  ts = tokenStream tokenTree cstParse "f(a, b)";
  assert ( length ts == 1 )                         -- one statement at the root
  assert ( toString focus (ts_0) == "f ( a , b )" ) -- descend to the first statement
///

TEST ///
  -- the cursor edits the shared mutable tree in place
  ts = tokenStream tokenTree cstParse "f(a, b)";
  app = ts_0;                       -- the application f(a, b)
  seq = (app_1)_0;                  -- the comma sequence inside the bracket
  appendContent(seq, leaf "c");     -- add c as the rightmost element
  prependContent(seq, leaf "z");    -- add z as the leftmost element
  assert ( toString focus ts == "f ( z , a , b , c )" )
  replaceFocus(app_0, leaf "g");    -- rename the function f -> g
  assert ( toString focus ts == "g ( z , a , b , c )" )
  removeFocus (seq_1);              -- detach the element a
  assert ( toString focus ts == "g ( z , b , c )" )
///

TEST ///
  -- tokenTree and flatten are inverses at the tree level: flatten then re-parse is stable
  inputs = {"f(a, b) + 3", "if x then y else z", "while c list e do g",
            "for i in L when p list e do z", "new T of B from C", "symbol x",
            "try a then b else c", "x -> x^2", "(a; b; c)", "a;; b", "(a;)",
            ",a", "a,", "a,,b", "(,a)", "f(a,)"};   -- empty sequence slots are null elements
  scan(inputs, s -> (
      src := flatten tokenTree cstParse s;
      assert ( cstToSource cstParse src == src )))
///

TEST ///
  -- the unified node: the shape is read straight off the four field accessors
  t = tokenTree cstParse "a + b";
  assert ( delimiterOf t == ";" )                            -- top level is a ";" sequence
  bin = t_0;                                                  -- the a + b infix node
  assert ( delimiterOf bin == "+" )
  assert ( contentOf bin / leftOf == {"a", "b"} )            -- operands are leaves; the text is in Opening
  assert ( isLeaf (contentOf bin)#0 )
///

TEST ///
  -- the delimiter lives on the node; control forms are whitespace-delimited clause sequences
  app = (tokenTree cstParse "f(a, b, c)")_0;                   -- application: f SPACE (a, b, c)
  assert ( delimiterOf app === spaceOperator )
  assert ( leftOf (contentOf app)#0 == "f" )                  -- left operand is the leaf f
  br = (contentOf app)#1;                                       -- the bracket (a, b, c)
  assert ( leftOf br == "(" and rightOf br == ")" )            -- a bracket = a fence pair
  seq = (contentOf br)#0;                                       -- its inner comma sequence
  assert ( delimiterOf seq == "," and contentOf seq / leftOf == {"a", "b", "c"} )
  ite = (tokenTree cstParse "if x then y else z")_0;
  assert ( delimiterOf ite === whitespaceDelimiter )           -- clauses are whitespace-delimited
  assert ( contentOf ite / (c -> leftOf c | " " | leftOf (contentOf c)#0) == {"if x", "then y", "else z"} )
  assert ( first unstack net ite == "If" )                     -- the sequence is named by its control form
  assert ( first unstack net (tokenTree cstParse "for i in L do z")_0 == "For" )
///

TEST ///
  -- constructors: operands are nodes (leaf for text); application is infix on spaceOperator
  t = infix(infix(leaf "f", spaceOperator, bracketed("(", delimited(",", {leaf "1", leaf "2"}), ")")), "+", leaf "y");
  assert ( flatten t == "f ( 1 , 2 ) + y" )
  assert ( isLeaf leaf "z" and leftOf leaf "z" == "z" )
///

TEST ///
  -- mutation in place: content items and the node delimiter
  bin = (tokenTree cstParse "a + b")_0;
  setItem(bin, 0, leaf "z");
  setDelimiter(bin, "*");
  assert ( flatten bin == "z * b" )
  s = delimited(",", {leaf "1", leaf "2"});
  setItem(s, 0, leaf "9");
  appendItem(s, leaf "3");
  assert ( flatten s == "9 , 2 , 3" )
///

TEST ///
  -- net renders the structure as an indented tree
  ls = unstack net (tokenTree cstParse "a + b")_0;
  assert ( ls#0 == "punctuation \"+\"" )           -- the node is labelled by its token's class
  assert ( ls#1 == "├─ symbol \"a\"" )
  assert ( ls#2 == "└─ symbol \"b\"" )
///

TEST ///
  -- quote takes bindings inline as options (no hashTable wrapper); a HashTable
  -- still works, and a hole-free template needs none
  assert ( toString quote("f($a, $b)", "a" => leaf "1", "b" => leaf "2") == "f ( 1 , 2 )" )
  assert ( toString quote("g($x)", hashTable{"x" => leaf "9"}) == "g ( 9 )" )
  assert ( toString quote("1 + 2") == "1 + 2" )
///

TEST ///
  -- repetition ${ unit }+ / ${ unit }* over "," and ";" sequences; unit metavars
  -- bind to lists, one entry per repetition
  declMacro("collect", "f(${$x,}+)", "g(${$x,}+)");
  assert ( expandSource "$collect f(a, b, c) $" == "g ( a , b , c )" )
  assert ( expandSource "$collect f(a) $" == "g ( a )" )          -- + matches a run of one
  -- a multi-element unit repeats in chunks; here each (a,b) pair is swapped
  declMacro("swap2", "[${$a, $b,}+]", "[${$b, $a,}+]");
  assert ( expandSource "$swap2 [1, 2, 3, 4] $" == "[ 2 , 1 , 4 , 3 ]" )
  -- the unit may drop part of each repetition (keys of key => value pairs)
  declMacro("keysOf", "{${$k => $v,}+}", "L(${$k,}+)");
  assert ( expandSource "$keysOf {a => 1, b => 2, c => 3} $" == "L ( a , b , c )" )
  -- fixed elements may sit beside the repetition
  declMacro("firstArg", "f($h, ${$t,}+)", "only($h)");
  assert ( expandSource "$firstArg f(a, b, c) $" == "only ( a )" )
  -- * matches zero, + does not
  declMacro("star", "g(${$x,}*)", "h(${$x,}*)");
  assert ( expandSource "$star g() $" == "h ( )" )
  -- repetition feeds matchesIn too: the run is captured as a list
  ms = matchesIn("f(${$x,}+)", tokenTree cstParse "f(1, 2, 3)");
  assert ( #ms == 1 and apply(ms#0#1#"x", toString) == {"1", "2", "3"} )
///

TEST ///
  -- matchesIn searches the whole tree, returning every (node, bindings) pair
  tree = tokenTree cstParse "f(1) + g(2) + f(3)";
  ms = matchesIn("f($x)", tree);
  assert ( #ms == 2 )                                          -- f(1) and f(3)
  assert ( apply(ms, m -> toString m#1#"x") == {"1", "3"} )    -- their captured args
  assert ( #matchesIn("$a + $b", tree) == 2 )                  -- matches nest (both + nodes)
  assert ( #matchesIn("zzz($x)", tree) == 0 )                  -- no match -> empty list
///

TEST ///
  -- comment recovery: parse discards comments, parseWithComments re-attaches them
  t = parseWithComments "-- doc\nx = 1  -- trailing";
  comments = select(contentOf t, isComment);
  assert ( #comments == 2 )                                 -- both comments recovered
  assert ( comments / leftOf == {"-- doc", "-- trailing"} ) -- full text, delimiters kept
  assert ( instance(comments#0, Comment) )                  -- a comment is its own node type
  assert ( not isComment leaf "x" )                         -- a real leaf is not a Comment
  -- a -- inside a string is text, not a comment; a real block comment is recovered
  u = parseWithComments "s = \"-- text\"  -* note *-";
  assert ( (select(contentOf u, isComment)) / leftOf == {"-* note *-"} )
///

--end--

-- Development loop:
-- restart
-- debug needsPackage "ProceduralMacros"
-- check "ProceduralMacros"
-- uninstallPackage "ProceduralMacros"; restart; installPackage "ProceduralMacros"; viewHelp "ProceduralMacros"

-- Inspect parsed examples (net shows the structure tree; _0 drops the top ";" wrapper):
--   gallery = examples -> scan(examples, s -> << s << endl << net (tokenTree cstParse s)_0 << endl << endl)
--   gallery {"f(a, b) + 3", "if x then y else z", "x -> x^2", "-a!", "new T of B from C"}
