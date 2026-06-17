-- -*- coding: utf-8 -*-
-- ProceduralMacros / Documentation.m2 -- the package manual.
-- Loaded by ProceduralMacros.m2 after beginDocumentation().

--------------------------------------------------------------------
-- Overview
--------------------------------------------------------------------

document {
    Key => "ProceduralMacros",
    Headline => "source-to-source macros over the Macaulay2 parse CST",
    PARA {
        "This package implements two flavors of macro that rewrite Macaulay2 source
        before evaluation, operating over the concrete syntax tree (CST) that
        ", TO "tokenTree", " builds from ", TO "cstParse", "."
    },
    PARA {
        BOLD "Macro application syntax.", "  A macro invocation is written
        ", TT "$name <block> $", " in source: the sigil ", TT "$", " opens the
        call, immediately followed by the name; the block runs to a bare closing
        ", TT "$", " (preceded by whitespace, not followed by a name character).
        A ", TT "$", " inside a string literal, raw string, or comment is never
        a sigil and is passed through verbatim.  ", TO "expandSource",
        " rewrites every invocation in a source string; ", TO "runSource",
        " expands and then evaluates."
    },
    PARA {
        BOLD "Two macro flavors."
    },
    UL {
        LI { BOLD "Procedural.", "  A function ", TT "ts -> ...", " on a ",
             TO "TokenStream", " cursor, registered with ", TO "installMacro",
             ".  The function receives the macro block as a cursor and returns
             a TokenTree or TokenStream.  Full M2 code can inspect, traverse,
             and mutate the tree before returning the expansion." },
        LI { BOLD "Declarative.", "  A pattern-to-template rewrite, registered
             with ", TO "declMacro", ".  The pattern is matched structurally;
             metavariables capture subtrees; the template is instantiated.
             Multiple ordered rules can be supplied." }
    },
    PARA {
        BOLD "The metavariable sigil in patterns and templates is ", TT "'",
        " (a leading apostrophe), not ", TT "$", ".  A leading ",
        TT "'", " is a parse error in normal M2, so it is free for this use;
        a trailing or interior ", TT "'", " stays a normal prime identifier
        (", TT "f'", ", ", TT "x'", ")."
    },
    PARA {
        BOLD "value / File overrides.", "  Installing the package hooks
        ", TT "value String", " and ", TT "value File", " so that any source
        string containing ", TT "$name", " is expanded before evaluation.
        The REPL and ", TT "value openIn", " therefore honor macros automatically.
        NOTE: ", TT "load", " and ", TT "needs", " use M2's own compiled reader
        and do NOT expand macros."
    },
    SeeAlso => {
        installMacro, expandSource, runSource,
        declMacro, quote,
        TokenTree, tokenTree, cstParse,
        TokenStream, tokenStream,
        parseWithComments
    },
    Subnodes => {
        "Macro objects",
        TO Macro,
        TO macroNamed,
        "Macro registration and expansion",
        TO installMacro,
        TO expandSource,
        TO expandMacro,
        "Declarative macros and patterns",
        TO declMacro,
        TO quote,
        TO matchesIn,
        TO nodeKind,
        TO Metavar,
        "The TokenTree node model",
        TO TokenTree,
        TO tokenTree,
        TO cstParse,
        "Constructors",
        TO leaf,
        TO spaceOperator,
        "Accessors",
        TO leftOf,
        TO tokenClass,
        "Mutation",
        TO setLeft,
        TO setItem,
        "Comments",
        TO Comment,
        TO parseWithComments,
        "TokenStream cursors",
        TO TokenStream,
        TO tokenStream,
        TO focus,
        TO child,
        TO siblingOf,
        "Cursor editing",
        TO replaceFocus,
        TO insertContent
    }
}

--------------------------------------------------------------------
-- Macro objects
--------------------------------------------------------------------

document {
    Key => {Macro, nameOf, (nameOf, Macro), transformOf, (transformOf, Macro)},
    Headline => "a named source-to-source transform",
    PARA {
        "A ", TT "Macro", " wraps a name (a ", TO "String", ") and a transform
        function (a ", TO "Function", ").  ", TO "installMacro", " constructs
        one and registers it in the global macro registry.  The transform receives
        the macro block as a ", TO "TokenStream", " cursor and must return a
        ", TT "TokenTree", " or a ", TT "TokenStream", "; the result is
        flattened back to source to form the expansion."
    },
    PARA {
        TT "nameOf m", " returns the name string.  ",
        TT "transformOf m", " returns the transform function."
    },
    EXAMPLE {
        ///installMacro("wrap", ts -> quote("list('e)", "e" => focus ts))///,
        ///m = macroNamed "wrap"///,
        ///nameOf m///,
        ///class m///
    },
    SeeAlso => {installMacro, macroNamed, expandMacro}
}

document {
    Key => {macroNamed, (macroNamed, String)},
    Headline => "look up a registered macro by name",
    Usage => "macroNamed name",
    Inputs => {"name" => String => "the macro name, without the $ sigil"},
    Outputs => {{"the ", TO "Macro", " registered under that name"}},
    PARA {
        "Looks up ", TT "name", " in the global macro registry and returns
        its ", TO "Macro", " object.  Errors if the name is unknown, so a
        typo'd name fails loudly rather than silently."
    },
    EXAMPLE {
        ///installMacro("id", ts -> focus ts)///,
        ///macroNamed "id"///,
        ///(try macroNamed "zzz" else "error: unknown macro")///
    },
    SeeAlso => {Macro, installMacro, expandMacro}
}

--------------------------------------------------------------------
-- Macro registration and expansion
--------------------------------------------------------------------

document {
    Key => {installMacro, (installMacro, String, Function)},
    Headline => "register a procedural macro",
    Usage => "installMacro(name, fn)",
    Inputs => {
        "name" => String => "the macro name used in $name <block> $ invocations",
        "fn"   => Function => {"a transform ", TT "ts -> ...",
            " on a ", TO "TokenStream", " cursor that returns a ",
            TO "TokenTree", " or a ", TO "TokenStream"}
    },
    Outputs => {{"the installed ", TO "Macro", " object"}},
    PARA {
        "Constructs a ", TO "Macro", " and registers it under ", TT "name", ".
        The transform ", TT "fn", " is called with a freshly-parsed cursor
        for the block between the opening ", TT "$name", " and the closing
        ", TT "$", ".  The focus of the cursor is the top-level content of
        that block (its single statement, after stripping the statement-list
        wrapper)."
    },
    PARA {
        "A procedural macro body typically uses ", TO "quote", " to build the
        output tree from a template, or manipulates the tree directly via
        cursor editing methods."
    },
    EXAMPLE {
        ///installMacro("double", ts -> quote("2 * ('e)", "e" => focus ts))///,
        ///expandSource "$double 3 + 4 $"///
    },
    PARA {
        "The block passed to the transform is the raw source between the name
        and the closing ", TT "$", ".  Use ", TO "focus", " to retrieve the
        parsed subtree."
    },
    SeeAlso => {Macro, expandSource, runSource, expandMacro, quote, "ProceduralMacros"}
}

document {
    Key => {expandSource, runSource},
    Headline => "expand macro invocations in a source string",
    PARA {
        TT "expandSource src", " scans ", TT "src", ", rewrites every
        ", TT "$name <block> $", " invocation with its macro's expansion,
        and returns the rewritten source string.  Content inside string
        literals, raw strings, and comments is copied verbatim; a ",
        TT "$", " inside any of these is never a sigil."
    },
    PARA {
        TT "runSource src", " calls ", TT "expandSource src", " and then
        evaluates the result with ", TT "value", "."
    },
    PARA {
        "The package also overrides ", TT "value String", " and
        ", TT "value File", " so that any source containing ", TT "$name",
        " is expanded automatically before evaluation.  The REPL and
        ", TT "value openIn \"f.m2\"", " therefore honor macros without
        an explicit call to ", TT "expandSource", "."
    },
    EXAMPLE {
        ///declMacro("sq", "'x", "'x * 'x")///,
        ///expandSource "$sq a + b $"///,
        ///runSource "$sq 5 $"///
    },
    PARA {
        "A ", TT "$", " inside a string or comment is not a sigil:"
    },
    EXAMPLE {
        ///expandSource "s = \"$sq not expanded $\""///,
        ///expandSource "-- $sq not expanded $"///
    },
    SeeAlso => {installMacro, declMacro, "ProceduralMacros"}
}

document {
    Key => {expandMacro, (expandMacro, Macro, String)},
    Headline => "apply a macro to a block source string",
    Usage => "expandMacro(m, block)",
    Inputs => {
        "m"     => Macro,
        "block" => String => "the raw source of the macro block"
    },
    Outputs => {String => "the expanded source"},
    PARA {
        "Parses ", TT "block", " into a TokenTree, wraps it in a cursor, calls
        the macro's transform, and returns the flattened source of the result.
        This is the primitive that ", TO "expandSource", " calls for each
        invocation."
    },
    EXAMPLE {
        ///installMacro("neg", ts -> prefix("-", focus ts))///,
        ///expandMacro(macroNamed "neg", " x + y ")///
    },
    SeeAlso => {Macro, expandSource, installMacro}
}

--------------------------------------------------------------------
-- Declarative macros
--------------------------------------------------------------------

document {
    Key => {declMacro,
        (declMacro, String, String, String),
        (declMacro, String, List)},
    Headline => "register a declarative (pattern => template) macro",
    Usage => "declMacro(name, pattern, template)\ndeclMacro(name, rules)",
    Inputs => {
        "name"     => String,
        "pattern"  => String => "a source string with metavariables",
        "template" => String => "a source string with metavariables",
        "rules"    => List => {"a list of ", TT "(pattern, template)", " pairs,
            each a ", TT "Sequence", " or a ", TT "List"}
    },
    Outputs => {{"the installed ", TO "Macro", " object"}},
    PARA {
        "A declarative macro matches its input against each pattern in order
        and expands via the first matching template.  If no rule matches, the
        macro errors.  Patterns and templates are parsed once and cached."
    },
    SUBSECTION "Metavariables",
    PARA {
        "A leading apostrophe opens a metavariable: ", TT "'x", " binds any
        subtree and splices it into the template.  A typed hole ", TT "'x:Kind",
        " binds only a node whose ", TO "nodeKind", " equals ", TT "Kind", ".
        Valid kinds: Comment, Metavar, Repetition, Alternation, String, Number,
        Keyword, Identifier, Operator, Apply, Sequence, Arrow, Infix, Bracket,
        Prefix, Postfix, If, While, For, Try, New, Statements, Clause, Node."
    },
    SUBSECTION "Repetition",
    PARA {
        TT "'{unit}+", " matches a run of one or more elements in a ",
        TT ","," or ", TT ";", " sequence (or the top-level statement list),
        consuming elements in chunks the size of ", TT "unit", ".  ",
        TT "'{unit}*", " allows zero elements.  Metavariables inside ",
        TT "unit", " accumulate lists, one entry per chunk."
    },
    SUBSECTION "Alternation",
    PARA {
        TT "'{ a | b | ... }", " matches if any branch matches, contributing
        that branch's bindings.  Alternation is pattern-only; it is rejected
        in a template.  Each branch must parse as an operand of the ", TT "|",
        " infix, so bare control keywords like ", TT "if", " cannot be branches."
    },
    EXAMPLE {
        ///declMacro("commute", "'a + 'b", "'b + 'a")///,
        ///expandSource "$commute 2 + x*y $"///
    },
    PARA { "A typed hole restricts which nodes bind:" },
    EXAMPLE {
        ///declMacro("numSq", "'n:Number", "'n * 'n")///,
        ///expandSource "$numSq 5 $"///,
        ///(try expandSource "$numSq x $" else "no match")///
    },
    PARA { "Multiple rules, tried in order:" },
    EXAMPLE {
        ///declMacro("flip", {("'a + 'b", "'b + 'a"), ("'a * 'b", "'b * 'a")})///,
        ///expandSource "$flip 1 + 2 $"///,
        ///expandSource "$flip 3 * 4 $"///,
        ///(try expandSource "$flip 1 - 2 $" else "no match")///
    },
    PARA { "Repetition collects elements:" },
    EXAMPLE {
        ///declMacro("collect", "f('{'x,}+)", "g('{'x,}+)")///,
        ///expandSource "$collect f(a, b, c) $"///,
        ///expandSource "$collect f(a) $"///
    },
    PARA { "Alternation as a variant rule:" },
    EXAMPLE {
        ///declMacro("wrap2", "'{ 'a + 'b | 'a * 'b }", "h('a, 'b)")///,
        ///expandSource "$wrap2 1 + 2 $"///,
        ///expandSource "$wrap2 3 * 4 $"///
    },
    SeeAlso => {installMacro, quote, matchesIn, nodeKind,
        Metavar, Repetition, Alternation, expandSource}
}

document {
    Key => {quote, (quote, String), (quote, Sequence)},
    Headline => "instantiate a template against a binding",
    Usage => "quote(template, bindings...)\nquote(template, hashTable bindings)\nquote template",
    Inputs => {
        "template" => String => "a source string with metavariables",
        "bindings" => {"optional: inline ", TT "\"name\" => node", " pairs, or
            a single ", TO "HashTable", " mapping names to TokenTrees"}
    },
    Outputs => {TokenTree => "the instantiated tree"},
    PARA {
        "Parses ", TT "template", " (caching the result), then splices a deep
        copy of each bound subtree for every metavariable hole.  Each use of
        a metavariable receives an independent copy; editing one copy does not
        mutate another or the original bound subtree."
    },
    PARA {
        "Bindings may be given as inline ", TT "String => TokenTree", " options
        (the common case in a macro body), as a ", TO "HashTable", " (for
        programmatically-built tables), or omitted entirely when the template
        has no holes."
    },
    EXAMPLE {
        ///quote("f('a, 'b)", "a" => leaf "1", "b" => leaf "2")///,
        ///quote("g('x)", hashTable{"x" => leaf "9"})///,
        ///toString quote("1 + 2")///
    },
    PARA {
        "A typical procedural macro body:"
    },
    EXAMPLE {
        ///installMacro("twice", ts -> quote("2 * ('e)", "e" => focus ts))///,
        ///expandSource "$twice 3 + 4 $"///
    },
    PARA {
        "The copies are independent -- repeated metavariables yield distinct nodes:"
    },
    EXAMPLE {
        ///e = leaf "x"///,
        ///t = quote("('v, 'v)", hashTable{"v" => e})///,
        ///seq = (t_0)_0///,
        ///(seq_0 =!= seq_1)///,
        ///(seq_0 =!= e)///
    },
    SeeAlso => {declMacro, installMacro, matchesIn}
}

document {
    Key => {matchesIn, (matchesIn, String, TokenTree), (matchesIn, TokenTree, TokenTree)},
    Headline => "search a tree for all subtrees matching a pattern",
    Usage => "matchesIn(pattern, tree)",
    Inputs => {
        "pattern" => String => {"a pattern source string or ", TO "TokenTree",
            " with metavariables"},
        "tree"    => TokenTree => "the tree to search"
    },
    Outputs => {List => {"a list of ", TT "(node, bindings)", " pairs, one per match,
        where ", TT "node", " is the matched ", TO "TokenTree", " and ",
        TT "bindings", " is a ", TO "HashTable", " mapping name strings to subtrees"}},
    PARA {
        "Searches ", TT "tree", " in pre-order, testing every node.  Matches may
        nest: a node and its descendants are both tested.  Returns an empty list
        when nothing matches."
    },
    EXAMPLE {
        ///tree = tokenTree cstParse "f(1) + g(2) + f(3)"///,
        ///ms = matchesIn("f('x)", tree)///,
        ///#ms///,
        ///apply(ms, m -> toString (m#1)#"x")///
    },
    PARA {
        "Repetition patterns capture lists:"
    },
    EXAMPLE {
        ///ms2 = matchesIn("f('{'x,}+)", tokenTree cstParse "f(1, 2, 3)")///,
        ///apply((ms2#0)#1#"x", toString)///
    },
    PARA {
        "Alternation patterns capture from the matching branch:"
    },
    EXAMPLE {
        ///ms3 = matchesIn("f('{ 'x:Number | 'x:String })", tokenTree cstParse "f(1) + f(\"s\") + f(z)")///,
        ///#ms3///
    },
    SeeAlso => {declMacro, quote, nodeKind}
}

document {
    Key => {nodeKind},
    Headline => "the structural kind of a TokenTree node",
    Usage => "nodeKind t",
    Inputs => {"t" => TokenTree},
    Outputs => {String => "a kind label string"},
    PARA {
        "Derives a kind string from the node's four fields without storing it.
        Most distinctions are structural; the one exception -- String vs Number
        (both leaf literals) -- is read off the token text."
    },
    PARA {
        "Kinds for leaves: ", TT "String", " (text starts with ", TT "\"", "),
        ", TT "Number", " (text starts with a digit), ",
        TT "Identifier", " (letter-starting, not a keyword), ",
        TT "Keyword", " (an M2 keyword), ", TT "Operator", " (all other single-token
        leaves)."
    },
    PARA {
        "Kinds for internal nodes: ", TT "Apply", " (juxtaposition, delimiter is ",
        TO "spaceOperator", "), ", TT "Sequence", " (comma or semicolon delimiter),
        ", TT "Statements", " (top-level statement list), ", TT "Arrow",
        " (", TT "->", "), ", TT "Infix", " (any other binary operator), ",
        TT "Bracket", " (fenced by an open/close pair), ", TT "Prefix", ",
        ", TT "Postfix", ".  Control forms -- ", TT "If", ", ", TT "While", ",
        ", TT "For", ", ", TT "Try", ", ", TT "New", " -- are whitespace-delimited
        clause sequences named after their leading keyword."
    },
    EXAMPLE {
        ///nodeKind leaf "17"///,
        ///nodeKind leaf "\"hi\""///,
        ///nodeKind leaf "foo"///,
        ///nodeKind leaf "while"///,
        ///nodeKind (tokenTree cstParse "a + b")_0///,
        ///nodeKind (tokenTree cstParse "f x")_0///,
        ///nodeKind (tokenTree cstParse "if c then x")_0///
    },
    SeeAlso => {declMacro, matchesIn, Metavar, TokenTree}
}

document {
    Key => {Metavar, Repetition, Alternation},
    Headline => "pattern node subtypes of TokenTree",
    PARA {
        TO "Metavar", ", ", TO "Repetition", ", and ", TO "Alternation", " are
        self-initializing subtypes of ", TO "TokenTree", " that appear in
        parsed patterns and templates.  They are produced by ", TO "declMacro",
        " and ", TO "quote", " during template parsing; they never appear in
        ordinary input trees."
    },
    PARA {
        BOLD "Metavar.", "  Represents a hole ", TT "'x", " or typed hole
        ", TT "'x:Kind", ".  The name is in ", TT "leftOf", "; the optional
        kind constraint is in ", TT "delimiterOf", " (null when untyped).
        An untyped hole binds any subtree; a typed hole binds only nodes
        whose ", TO "nodeKind", " equals the constraint."
    },
    PARA {
        BOLD "Repetition.", "  Represents ", TT "'{unit}+", " or
        ", TT "'{unit}*", ".  The quantifier (", TT "+", " or ", TT "*", ")
        is in ", TT "leftOf", "; the element separator (", TT ",", " or
        ", TT ";", ") is in ", TT "delimiterOf", "; the unit elements are in
        ", TT "contentOf", ".  Metavariables in the unit accumulate lists."
    },
    PARA {
        BOLD "Alternation.", "  Represents ", TT "'{ a | b | ... }", ".
        The branch patterns are in ", TT "contentOf", ".  Pattern-only;
        ", TO "quote", " rejects an alternation in a template."
    },
    PARA {
        "All three subtypes inherit every ", TO "TokenTree", " accessor."
    },
    SeeAlso => {declMacro, quote, matchesIn, nodeKind}
}

--------------------------------------------------------------------
-- TokenTree
--------------------------------------------------------------------

document {
    Key => {TokenTree},
    Headline => "a mutable CST node",
    PARA {
        "The uniform node type macros work on.  Every node -- leaf, infix,
        prefix, postfix, bracket, sequence, application, control form -- is a
        ", TT "TokenTree", " (a ", TO "MutableHashTable", ") with exactly four
        fields, always present:"
    },
    UL {
        LI { BOLD "Opening", " -- boundary text before the content:
            the leaf's text, a prefix operator, or an open bracket; null otherwise." },
        LI { BOLD "Closing", " -- boundary text after the content:
            a postfix operator, a close bracket; null otherwise." },
        LI { BOLD "Items", " -- the child nodes (a MutableList, empty for leaves)." },
        LI { BOLD "Separator", " -- what sits between children:
            a real operator String, or one of the three synthetic
            ", TO "spaceOperator", "/", TO "whitespaceDelimiter", "/",
            TO "statementSeparator", " Symbols." }
    },
    PARA {
        "A node is fully described by which fields are non-null; there is no
        stored kind.  ", TO "nodeKind", " derives a label on demand.
        ", TT "flatten t", " reconstructs normalized source
        (operators space-padded), which ", TO "cstParse", " re-parses
        identically.  ", TT "net t", " renders the structure as an
        indented tree."
    },
    EXAMPLE {
        ///t = tokenTree cstParse "a + b"///,
        ///flatten t///,
        ///net t_0///
    },
    PARA {
        TT "t_i", " is the i-th child (0-based); ", TT "length t", " is the
        number of children.  ", TO "Comment", ", ", TO "Metavar", ",
        ", TO "Repetition", ", and ", TO "Alternation", " are subtypes of
        ", TT "TokenTree", "."
    },
    SeeAlso => {tokenTree, cstParse, cstToSource, leaf, infix, prefix, postfix,
        delimited, bracketed, leftOf, rightOf, delimiterOf, contentOf, isLeaf,
        setLeft, setRight, setDelimiter, setItem, appendItem, nodeKind, tokenClass}
}

document {
    Key => {tokenTree, (tokenTree, BasicList)},
    Headline => "convert a raw parse CST to a TokenTree",
    Usage => "tokenTree node",
    Inputs => {"node" => BasicList => {"the raw output of ", TO "cstParse"}},
    Outputs => {TokenTree},
    PARA {
        "Maps the nested-list CST that ", TO "cstParse", " returns onto a
        uniform ", TO "TokenTree", ".  The mapping is hook-dispatched on the
        tag string, so new constructs can be added with ", TT "addHook", "."
    },
    PARA {
        "The top-level node -- a plain ", TT "BasicList", ", not a tagged node
        -- becomes a ", TT "statementSeparator", "-delimited sequence
        (kind ", TT "Statements", ").  Every other node is dispatched by its
        tag string."
    },
    EXAMPLE {
        ///t = tokenTree cstParse "if x then y else z"///,
        ///nodeKind t_0///,
        ///nodeKind (tokenTree cstParse "f(a, b)")_0///
    },
    SeeAlso => {cstParse, cstToSource, TokenTree, "ProceduralMacros"}
}

document {
    Key => {cstParse, cstToSource},
    Headline => "parse source to raw CST and reconstruct source from TokenTree",
    PARA {
        TT "cstParse src", " calls ", TT "parse(src | \"\")", " to obtain a
        raw nested-list CST.  The extra concatenation passes a fresh copy of
        the string to ", TT "parse", ", which mutates its argument in place."
    },
    PARA {
        TT "cstToSource node", " converts the raw CST directly to a normalized
        source string, bypassing the ", TO "TokenTree", " representation.
        Equivalent to ", TT "flatten(tokenTree node)", "."
    },
    PARA {
        "Both operate on M2's built-in parser output.  They discard comments
        and cannot recover whether a top-level statement was semicolon-suppressed.
        Use ", TO "parseWithComments", " to recover that information."
    },
    EXAMPLE {
        ///cstToSource cstParse "f(a, b) + 3"///,
        ///cstToSource cstParse "if x then y else z"///
    },
    SeeAlso => {tokenTree, TokenTree, parseWithComments}
}

--------------------------------------------------------------------
-- Constructors
--------------------------------------------------------------------

document {
    Key => {
        leaf, (leaf, String),
        infix, (infix, TokenTree, String, TokenTree), (infix, TokenTree, Symbol, TokenTree),
        prefix, (prefix, String, TokenTree),
        postfix, (postfix, TokenTree, String),
        delimited, (delimited, String, BasicList), (delimited, Symbol, BasicList),
        bracketed, (bracketed, String, TokenTree, String), (bracketed, String, Nothing, String)
    },
    Headline => "TokenTree node constructors",
    PARA {
        "All constructors take typed arguments (operands must be TokenTree nodes;
        use ", TT "leaf", " to wrap raw text)."
    },
    UL {
        LI { TT "leaf s", " -- a single-token leaf with text ", TT "s", "." },
        LI { TT "infix(l, op, r)", " -- a two-operand infix node.  ",
            TT "op", " may be a real operator String (", TT "+", ", ",
            TT "->", ", ...) or a synthetic Symbol (",
            TO "spaceOperator", " for function application)." },
        LI { TT "prefix(op, r)", " -- a prefix node (operator before its operand)." },
        LI { TT "postfix(l, op)", " -- a postfix node (operator after its operand)." },
        LI { TT "delimited(sep, items)", " -- a flat sequence joined by ",
            TT "sep", " (a String or synthetic Symbol)." },
        LI { TT "bracketed(open, inner, close)", " -- a fenced node.  Pass ",
            TT "null", " as ", TT "inner", " for an empty bracket ", TT "()", "." }
    },
    EXAMPLE {
        ///t = infix(infix(leaf "f", spaceOperator, bracketed("(", delimited(",", {leaf "1", leaf "2"}), ")")), "+", leaf "y")///,
        ///flatten t///,
        ///isLeaf leaf "z"///,
        ///leftOf leaf "z"///
    },
    SeeAlso => {TokenTree, spaceOperator, whitespaceDelimiter, statementSeparator,
        setLeft, setRight, setDelimiter, setItem, appendItem}
}

--------------------------------------------------------------------
-- Synthetic separators
--------------------------------------------------------------------

document {
    Key => {spaceOperator, whitespaceDelimiter, statementSeparator},
    Headline => "synthetic separator symbols",
    PARA {
        "Three protected Symbols distinguished from real operator Strings by
        ", TT "instance(d, Symbol)", ".  They are used as the ", TT "Separator",
        " field of certain nodes:"
    },
    UL {
        LI { TT "spaceOperator", " -- juxtaposition / function application (",
            TT "f x", ").  A node with this separator has kind ", TT "Apply", "." },
        LI { TT "whitespaceDelimiter", " -- the gap between clauses of a control form (",
            TT "if/then/else", ", ", TT "while/do", ", ", TT "for/in/do", ", etc.).
            Clauses are prefix nodes whose ", TO "leftOf", " is the keyword." },
        LI { TT "statementSeparator", " -- the boundary between top-level statements.
            The top-level node (kind ", TT "Statements", ") uses this separator.
            A suppressed statement (trailing ", TT ";", ") is wrapped as a postfix
            ", TT ";", " node by ", TO "parseWithComments", "." }
    },
    EXAMPLE {
        ///app = (tokenTree cstParse "f(a)")_0///,
        ///delimiterOf app === spaceOperator///,
        ///nodeKind app///,
        ///ite = (tokenTree cstParse "if x then y else z")_0///,
        ///delimiterOf ite === whitespaceDelimiter///,
        ///tt = tokenTree cstParse "a; b"///,
        ///delimiterOf tt === statementSeparator///
    },
    SeeAlso => {delimiterOf, delimited, infix, nodeKind}
}

--------------------------------------------------------------------
-- Accessors
--------------------------------------------------------------------

document {
    Key => {
        leftOf, (leftOf, TokenTree),
        rightOf, (rightOf, TokenTree),
        delimiterOf, (delimiterOf, TokenTree),
        contentOf, (contentOf, TokenTree),
        isLeaf, (isLeaf, TokenTree)
    },
    Headline => "TokenTree field accessors",
    PARA {
        "Read the four fields of a ", TO "TokenTree", " node.
        Every field is always present; unset fields return null."
    },
    UL {
        LI { TT "leftOf t", " -- the Opening field: leaf text, prefix operator,
            or open bracket; null otherwise." },
        LI { TT "rightOf t", " -- the Closing field: postfix operator or close
            bracket; null otherwise." },
        LI { TT "delimiterOf t", " -- the Separator field: a real operator String,
            or one of the three synthetic Symbols (",
            TO "spaceOperator", ", ", TO "whitespaceDelimiter", ", ",
            TO "statementSeparator", "); null for leaves and brackets." },
        LI { TT "contentOf t", " -- the Items field as an immutable List.
            Use ", TT "t_i", " to index directly (0-based); ", TT "length t",
            " or ", TT "#(contentOf t)", " for the child count." },
        LI { TT "isLeaf t", " -- true when the node has no children." }
    },
    EXAMPLE {
        ///t = (tokenTree cstParse "a + b")_0///,
        ///delimiterOf t///,
        ///contentOf t / leftOf///,
        ///isLeaf (contentOf t)_0///,
        ///br = (tokenTree cstParse "(a, b)")_0///,
        ///leftOf br///,
        ///rightOf br///
    },
    SeeAlso => {TokenTree, setLeft, setRight, setDelimiter, setItem, appendItem}
}

document {
    Key => {tokenClass, (tokenClass, String)},
    Headline => "lexical class of a token's text",
    Usage => "tokenClass s",
    Inputs => {"s" => String => "the token text (as stored in Opening or Closing)"},
    Outputs => {String => {"one of: ", TT "\"symbol\"", ", ", TT "\"keyword\"",
        ", ", TT "\"literal\"", ", ", TT "\"punctuation\"", ", ", TT "\"comment\""}},
    PARA {
        "Classifies a raw token string by its first character.  This is the
        lexical class the tree-display uses to label each token; it is not the
        same as ", TO "nodeKind", " (which describes whole nodes)."
    },
    EXAMPLE {
        ///tokenClass "x"///,
        ///tokenClass "while"///,
        ///tokenClass "+"///,
        ///tokenClass "42"///,
        ///tokenClass "\"hello\""///,
        ///tokenClass "--"///
    },
    SeeAlso => {nodeKind, TokenTree}
}

--------------------------------------------------------------------
-- Mutation
--------------------------------------------------------------------

document {
    Key => {
        setLeft, (setLeft, TokenTree, String),
        setRight, (setRight, TokenTree, String),
        setDelimiter, (setDelimiter, TokenTree, String)
    },
    Headline => "mutate the boundary text or delimiter of a TokenTree in place",
    PARA {
        TT "setLeft(t, s)", " replaces the Opening field;
        ", TT "setRight(t, s)", " replaces the Closing field;
        ", TT "setDelimiter(t, s)", " replaces the Separator with a real
        operator String (synthetic Symbol separators come only from constructors
        or ", TO "tokenTree", ")."
    },
    EXAMPLE {
        ///bin = (tokenTree cstParse "a + b")_0///,
        ///setLeft(bin, "x")///,
        ///setDelimiter(bin, "-")///,
        ///flatten bin///
    },
    SeeAlso => {setItem, appendItem, TokenTree}
}

document {
    Key => {setItem, (setItem, TokenTree, ZZ, TokenTree),
            appendItem, (appendItem, TokenTree, TokenTree)},
    Headline => "mutate the children of a TokenTree in place",
    PARA {
        TT "setItem(t, i, v)", " replaces the i-th child (0-based).  ",
        TT "appendItem(t, v)", " appends a child at the end.  Both mutate
        the node in place and return the node.  To insert at an arbitrary
        position, use ", TO "insertContent", " on a ", TO "TokenStream", " cursor."
    },
    EXAMPLE {
        ///s = delimited(",", {leaf "1", leaf "2"})///,
        ///setItem(s, 0, leaf "9")///,
        ///appendItem(s, leaf "3")///,
        ///flatten s///
    },
    SeeAlso => {setLeft, setRight, setDelimiter,
        insertContent, appendContent, prependContent, TokenTree}
}

--------------------------------------------------------------------
-- Comments
--------------------------------------------------------------------

document {
    Key => {Comment, commentNode, (commentNode, String),
            isComment, (isComment, TokenTree)},
    Headline => "comment nodes in a TokenTree",
    PARA {
        TO "Comment", " is a self-initializing subtype of ", TO "TokenTree", "
        whose ", TT "leftOf", " field holds the full comment text (including
        the ", TT "--", " or ", TT "-* *-", " delimiters).  A comment node
        flattens to its text verbatim."
    },
    PARA {
        TT "commentNode text", " constructs a Comment node.  ",
        TT "isComment t", " tests whether a node is a Comment."
    },
    EXAMPLE {
        ///t = parseWithComments "-- doc\nx = 1  -- trailing"///,
        ///cs = contentOf t///,
        ///comments = select(cs, isComment)///,
        ///comments / leftOf///,
        ///isComment leaf "x"///
    },
    SeeAlso => {parseWithComments, attachComments, isLeaf, leftOf}
}

document {
    Key => {parseWithComments, (parseWithComments, String),
            attachComments, (attachComments, TokenTree, String)},
    Headline => "parse source with comment and suppression recovery",
    PARA {
        TT "parseWithComments src", " parses ", TT "src", " into a TokenTree and
        re-scans the source to recover the information that ", TT "parse", " discards:"
    },
    UL {
        LI { BOLD "Comments.", "  Each ", TT "--", " or ", TT "-* *-", "
            comment is re-attached as a ", TO "Comment", " node among the top-level
            children, in source order.  Comments buried mid-expression are floated
            to their enclosing statement." },
        LI { BOLD "Suppression.", "  A top-level statement followed by ", TT ";", "
            (which suppresses the REPL's print callback) becomes a postfix ",
            TT ";", " node.  A printed statement stays bare." },
        LI { BOLD "Validation.", "  The illegal ", TT ";;", " (an empty statement
            that ", TT "parse", " silently accepts) is rejected with an error." }
    },
    PARA {
        TT "attachComments(root, src)", " is the lower-level primitive:
        it mutates an already-built ", TT "root", " (which must be
        ", TT "tokenTree cstParse src", ") in place."
    },
    EXAMPLE {
        ///t = parseWithComments "a = 1;\nb = 2"///,
        ///nodeKind t///,
        ///cs = contentOf t///,
        ///nodeKind cs_0///,
        ///rightOf cs_0///,
        ///nodeKind cs_1///,
        ///toString t///
    },
    PARA { "Comment recovery:" },
    EXAMPLE {
        ///u = parseWithComments "-- doc\nx = 1  -- trailing"///,
        ///(select(contentOf u, isComment)) / leftOf///
    },
    SeeAlso => {cstParse, tokenTree, Comment, isComment, commentNode}
}

--------------------------------------------------------------------
-- TokenStream
--------------------------------------------------------------------

document {
    Key => {TokenStream},
    Headline => "a cursor into a mutable TokenTree",
    PARA {
        "A cursor holds the path from the root of the tree down to the currently
        focused node (as a chain of node references).  Several cursors may
        coexist over the same mutable tree; structural edits are visible through
        all of them."
    },
    PARA {
        "Navigation operators: ", TT "ts_i", " descends to the i-th child
        (0-based); ", TT "ts^k", " ascends ", TT "k", " levels (0 = the focus
        itself, 1 = the parent).  Both return new cursors."
    },
    PARA {
        "Source-order DFS iteration: ", TT "for c in ts do ...", " visits every
        subtree of the focused node exactly once, in token order, binding ", TT "c",
        " to a live cursor at each.  (Equivalently, ", TT "iterator ts", " returns a
        function that yields each cursor in turn, or ", TT "StopIteration", " when
        the walk is complete.)"
    },
    EXAMPLE {
        ///ts = tokenStream tokenTree cstParse "f(a, b)"///,
        ///toString focus (ts_0)///,
        ///toString focus ((ts_0)^1)///,
        ///for c in ts list toString focus c///
    },
    SeeAlso => {tokenStream, focus, rootOf, atTop, childCount, childIndex,
        child, up, root, siblingOf, replaceFocus, removeFocus,
        insertContent, appendContent, prependContent}
}

document {
    Key => {tokenStream, (tokenStream, TokenTree)},
    Headline => "create a cursor at the root of a TokenTree",
    Usage => "tokenStream t",
    Inputs => {"t" => TokenTree},
    Outputs => {TokenStream},
    PARA {
        "Returns a cursor whose focus is ", TT "t", " (the root of the tree).
        The cursor shares the mutable tree; every edit through any cursor
        derived from it is immediately visible through all others."
    },
    EXAMPLE {
        ///ts = tokenStream tokenTree cstParse "a + b"///,
        ///toString focus ts///,
        ///atTop ts///
    },
    SeeAlso => {TokenStream, focus, rootOf}
}

document {
    Key => {focus, (focus, TokenStream),
            rootOf, (rootOf, TokenStream),
            atTop, (atTop, TokenStream),
            childCount, (childCount, TokenStream)},
    Headline => "cursor state: focus, root, position",
    PARA {
        TT "focus ts", " returns the currently focused ", TO "TokenTree", " node.
        ", TT "rootOf ts", " returns the root of the whole tree, regardless of
        the current focus.  ", TT "atTop ts", " is true when the cursor is at
        the root.  ", TT "childCount ts", " is the number of children of the
        focused node."
    },
    EXAMPLE {
        ///ts = tokenStream tokenTree cstParse "f(a)"///,
        ///toString focus ts///,
        ///atTop ts///,
        ///childCount ts///,
        ///child0 = ts_0///,
        ///atTop child0///,
        ///toString rootOf child0///
    },
    SeeAlso => {TokenStream, tokenStream, child, up, root}
}

document {
    Key => {child, (child, TokenStream, ZZ),
            up, (up, TokenStream),
            root, (root, TokenStream)},
    Headline => "cursor navigation: descend, ascend, return to root",
    PARA {
        TT "child(ts, i)", " descends to the i-th child of the focus
        (equivalent to ", TT "ts_i", ").  ",
        TT "up ts", " ascends one level; errors at the root.  ",
        TT "root ts", " returns a cursor at the tree's root, regardless of depth."
    },
    PARA {
        "The ", TT "_", " and ", TT "^", " operators are the terse forms:
        ", TT "ts_i", " descends to child ", TT "i", ";
        ", TT "ts^k", " ascends ", TT "k", " levels
        (0 = focus, 1 = parent, 2 = grandparent, ...)."
    },
    EXAMPLE {
        ///ts = tokenStream tokenTree cstParse "f(a, b, c)"///,
        ///seq = ((ts_0)_1)_0///,
        ///b = seq_1///,
        ///toString focus b///,
        ///toString focus (b^1)///,
        ///toString focus (b^2)///,
        ///toString focus root b///
    },
    SeeAlso => {TokenStream, focus, siblingOf, childIndex, up, root}
}

document {
    Key => {siblingOf, (siblingOf, TokenStream, ZZ),
            childIndex, (childIndex, TokenStream)},
    Headline => "cursor sibling navigation and position query",
    PARA {
        TT "childIndex ts", " returns the 0-based index of the focused node
        among its parent's children (located by object identity).  Returns
        null at the root.  ",
        TT "siblingOf(ts, offset)", " moves to the sibling ",
        TT "offset", " positions over (0 = self, 1 = next, -1 = previous).
        Errors at the root."
    },
    EXAMPLE {
        ///ts = tokenStream tokenTree cstParse "f(a, b, c)"///,
        ///seq = ((ts_0)_1)_0///,
        ///b = seq_1///,
        ///childIndex b///,
        ///toString focus siblingOf(b, 1)///,
        ///toString focus siblingOf(b, -1)///,
        ///childIndex root b///
    },
    SeeAlso => {TokenStream, child, up, focus}
}

--------------------------------------------------------------------
-- Cursor editing
--------------------------------------------------------------------

document {
    Key => {replaceFocus, (replaceFocus, TokenStream, TokenTree),
            removeFocus, (removeFocus, TokenStream)},
    Headline => "replace or detach the focused node",
    PARA {
        TT "replaceFocus(ts, n)", " replaces the focused node with ", TT "n",
        " in the shared tree; returns a cursor pointing at ", TT "n", ".
        At the root, the root node is overwritten in place."
    },
    PARA {
        TT "removeFocus ts", " detaches the focused node from its parent
        and returns a cursor at the parent.  Errors at the root."
    },
    EXAMPLE {
        ///ts = tokenStream tokenTree cstParse "f(a, b)"///,
        ///app = ts_0///,
        ///replaceFocus(app_0, leaf "g")///,
        ///toString focus ts///,
        ///seq = (app_1)_0///,
        ///removeFocus(seq_0)///,
        ///toString focus ts///
    },
    SeeAlso => {insertContent, appendContent, prependContent, TokenStream}
}

document {
    Key => {insertContent, (insertContent, TokenStream, ZZ, TokenTree),
            prependContent, (prependContent, TokenStream, TokenTree),
            appendContent, (appendContent, TokenStream, TokenTree)},
    Headline => "insert a child into the focused node",
    PARA {
        "All three splice a node into the content of the focused node in place.
        ", TT "insertContent(ts, i, node)", " inserts before index ", TT "i", ".
        ", TT "prependContent(ts, node)", " inserts at position 0.
        ", TT "appendContent(ts, node)", " appends at the end.
        Each returns the cursor (unchanged focus, updated content)."
    },
    EXAMPLE {
        ///ts = tokenStream tokenTree cstParse "f(a, b)"///,
        ///app = ts_0///,
        ///seq = (app_1)_0///,
        ///appendContent(seq, leaf "c")///,
        ///prependContent(seq, leaf "z")///,
        ///toString focus ts///
    },
    SeeAlso => {replaceFocus, removeFocus, appendItem, setItem, TokenStream}
}
