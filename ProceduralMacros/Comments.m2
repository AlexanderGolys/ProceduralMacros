-- -*- coding: utf-8 -*-
-- ProceduralMacros / Comments.m2 -- recover the comments `parse` discards.
--
-- `parse` strips every comment with no trace and records no source offsets, so a
-- CST alone cannot round-trip the documentation a file keeps in its comments. We
-- still hold the raw source, so we re-scan it in lockstep with the token spine the
-- tree implies and re-attach each comment as a commentTrivia node -- the
-- trivia-as-token model tree-sitter uses (the node KIND lives in Cst.m2).
--
-- First cut: top-level granularity. A comment becomes an extra child of the root
-- cell sequence, placed before the cell it precedes (or after the last cell) --
-- which is exactly where documentation comments live. Comments buried mid-
-- expression are floated to their enclosing cell rather than lost.

-- the source-ordered list of literal token texts a tree implies -- the same walk
-- flatten does, but collecting tokens instead of joining them. A real operator
-- (a String separator) is itself a source token and is interleaved between
-- operands; the synthetic separators (application / clause gaps) are not.
spineTokens = t -> (
    if t === null then return {};
    cs := contentOf t;
    sepTok := if instance(delimiterOf t, String) then {delimiterOf t} else {};
    childToks := apply(cs, spineTokens);
    joined := if #childToks == 0 then {} else fold((a, b) -> join(a, sepTok, b), childToks);
    pre := if leftOf t =!= null then {leftOf t} else {};
    post := if rightOf t =!= null then {rightOf t} else {};
    join(pre, joined, post)
)

-- a keyword whose spelling parse normalised away (canonical => the synonyms that
-- also produce the same node), so the lockstep scan still recognises the source.
keywordSynonyms = new HashTable from {"threadLocal" => {"threadVariable"}}

-- walk `src` alongside the token spine of `root` (which must be tokenTree cstParse
-- of that same src), attaching every comment encountered to the root cell sequence
-- in source order. Mutates and returns root.
attachComments = method()
attachComments(TokenTree, String) := TokenTree => (root, src) -> (
    n := #src;
    st := new MutableHashTable from {"pos" => 0, "pending" => {}};
    at := i -> if i < n then substring(i, 1, src) else "";
    starts := (i, s) -> i + #s <= n and substring(i, #s, src) == s;
    isWSat := i -> (c := at i; c === " " or c === "\t" or c === "\n" or c === "\r");

    -- capture one comment (positioned at -- or -*) into the pending list
    addComment := text -> st#"pending" = append(st#"pending", commentNode text);
    captureComment := () -> (
        p := st#"pos";
        e := if starts(p, "--") then (
            lineEnd := p + 2;
            while lineEnd < n and at lineEnd =!= "\n" do lineEnd = lineEnd + 1;
            lineEnd
        ) else (
            blockEnd := p + 2;
            while blockEnd < n and not starts(blockEnd, "*-") do blockEnd = blockEnd + 1;
            if blockEnd < n then blockEnd + 2 else n          -- include the closing *-
        );
        addComment substring(p, e - p, src);
        st#"pos" = e
    );

    -- advance over whitespace and comments; comments land in the pending list
    skipTrivia := () -> while st#"pos" < n do (
        p := st#"pos";
        if isWSat p then st#"pos" = p + 1
        else if starts(p, "--") or starts(p, "-*") then captureComment()
        else break
    );

    -- a string literal is consumed wholesale (its body may contain -- etc.); the
    -- regular form keeps its quotes in the token, the raw /// /// form does not, so
    -- both are matched off the SOURCE rather than the token text
    endOfString := p -> (
        i := p + 1;
        while i < n and at i =!= "\"" do i = if at i === "\\" then i + 2 else i + 1;
        if i < n then i + 1 else n
    );
    endOfRaw := p -> (
        i := p + 3;
        while i < n and not starts(i, "///") do i = i + 1;
        if i < n then i + 3 else n
    );
    synonymEnd := (p, tok) -> (
        if keywordSynonyms#?tok then
            for alt in keywordSynonyms#tok do if starts(p, alt) then return p + #alt;
        null
    );

    -- consume the next expected token from the source, skipping/collecting trivia
    consumeTok := tok -> (
        skipTrivia();
        p := st#"pos";
        if p >= n then error "attachComments: source ended before the token spine did";
        if at p === "\"" then st#"pos" = endOfString p
        else if starts(p, "///") then st#"pos" = endOfRaw p
        else if starts(p, tok) then st#"pos" = p + #tok
        else (
            alt := synonymEnd(p, tok);
            if alt =!= null then st#"pos" = alt
            else error("attachComments: desynced at offset " | toString p
                | "\n  expected token: " | tok
                | "\n  source here:    " | substring(p, min(24, n - p), src))
        )
    );

    -- consume the boundary after a top-level statement, returning whether it was a
    -- `;` (which SUPPRESSES the statement's print) rather than a newline / end. parse
    -- conflates the two and silently accepts `;;`; here we recover the `;` from the
    -- source and reject the illegal `;;` (an empty statement) that parse let through.
    consumeSep := () -> (
        skipTrivia();
        suppressed := starts(st#"pos", ";");
        if suppressed then (
            st#"pos" = st#"pos" + 1;
            skipTrivia();
            if starts(st#"pos", ";") then
                error "attachComments: ';;' (an empty statement) is not valid M2 -- parse accepts it, but it is a syntax error"
        );
        suppressed
    );

    takePending := () -> (cs := st#"pending"; st#"pending" = {}; cs);

    cells := contentOf root;
    spines := apply(cells, spineTokens);
    out := {};
    for ci to #cells - 1 do (
        skipTrivia();
        out = join(out, takePending());              -- comments leading this cell
        scan(spines#ci, consumeTok);                 -- consume the cell's tokens
        suppressed := consumeSep();                  -- the trailing `;`, if any
        -- a suppressed top-level statement is `stmt;` -- a postfix `;` -- restoring
        -- the print/suppress distinction parse flattened away
        out = append(out, if suppressed then postfix(cells#ci, ";") else cells#ci);
        out = join(out, takePending())               -- comments inside / after the cell body
    );
    skipTrivia();
    out = join(out, takePending());                  -- comments after the last cell
    setContent(root, out);
    root
)

-- parse source into a TokenTree with its comments re-attached
parseWithComments = method()
parseWithComments String := TokenTree => src -> attachComments(tokenTree cstParse src, src)
