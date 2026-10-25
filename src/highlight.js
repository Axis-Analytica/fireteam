.pragma library

// A small, forgiving syntax highlighter for the intel diff. It reads one line
// at a time and carries a little state between lines (an open block comment,
// a triple-quoted or template string), so multi-line constructs come out
// right when the hunk shows their start and approximately when it doesn't.
// It never throws and never loops: every step consumes at least one
// character, and lines past `limit` characters are left plain.
//
// tokenize() gives a flat list [type, text, type, text, …]; render() turns it
// into escaped StyledText with the caller's colours, so the colours can follow
// the theme (and the line's kind) without re-tokenizing.

var PLAIN = 0, KEYWORD = 1, STRING = 2, COMMENT = 3, NUMBER = 4
var limit = 2000

function words(s) {
    var out = {}
    s.split(/\s+/).forEach(function (w) { if (w) out[w] = true })
    return out
}

var cKeywords = words("auto break case catch char class const constexpr consteval constinit continue co_await co_return "
    + "co_yield decltype default delete do double else enum explicit export extern false final float for friend goto if "
    + "inline int long mutable namespace new noexcept nullptr operator override private protected public register "
    + "reinterpret_cast static_cast dynamic_cast const_cast return short signed sizeof static static_assert struct switch "
    + "template this thread_local throw true try typedef typeid typename union unsigned using virtual void volatile "
    + "wchar_t while bool emit signals slots Q_OBJECT Q_GADGET Q_PROPERTY Q_INVOKABLE Q_SIGNALS Q_SLOTS Q_EMIT Q_ENUM")
var jsKeywords = words("break case catch class const continue debugger default delete do else export extends false "
    + "finally for function if import in instanceof let new null return super switch this throw true try typeof "
    + "undefined var void while with yield async await of static get set as from interface type enum implements "
    + "private protected public readonly declare namespace abstract keyof satisfies "
    + "property signal required alias pragma component")
var pyKeywords = words("False None True and as assert async await break class continue def del elif else except "
    + "finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self")
var goKeywords = words("break case chan const continue default defer else fallthrough for func go goto if import "
    + "interface map package range return select struct switch type var nil true false iota")
var rustKeywords = words("as async await break const continue crate dyn else enum extern false fn for if impl in let "
    + "loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while")
var shKeywords = words("if then else elif fi case esac for while until do done in function return local export "
    + "readonly declare set unset shift exit source")
var jsonKeywords = words("true false null")

// What each language looks like to the tokenizer.
var langs = {
    c:    { kw: cKeywords, line: "//", block: true, quotes: "\"'", pre: true },
    js:   { kw: jsKeywords, line: "//", block: true, quotes: "\"'`", multi: "`" },
    py:   { kw: pyKeywords, hash: true, quotes: "\"'", triple: true },
    go:   { kw: goKeywords, line: "//", block: true, quotes: "\"'`", multi: "`" },
    rust: { kw: rustKeywords, line: "//", block: true, quotes: "\"", chars: true },
    sh:   { kw: shKeywords, hash: true, quotes: "\"'", spaceHash: true },
    json: { kw: jsonKeywords, quotes: "\"" },
    conf: { kw: jsonKeywords, hash: true, quotes: "\"'", spaceHash: true },
    css:  { kw: {}, block: true, quotes: "\"'", at: true, hex: true },
    md:   {},
    html: {}
}

var byExtension = {
    c: "c", cc: "c", cpp: "c", cxx: "c", h: "c", hh: "c", hpp: "c", hxx: "c", m: "c", mm: "c",
    qml: "js", js: "js", ts: "js", tsx: "js", jsx: "js", mjs: "js", cjs: "js", mts: "js",
    py: "py", pyi: "py", go: "go", rs: "rust",
    sh: "sh", bash: "sh", zsh: "sh", fish: "sh",
    json: "json", jsonc: "js", json5: "js",
    md: "md", markdown: "md",
    css: "css", scss: "css", less: "css", qss: "css",
    html: "html", htm: "html", xml: "html", svg: "html", ui: "html", qrc: "html",
    yaml: "conf", yml: "conf", toml: "conf", ini: "conf", cfg: "conf", conf: "conf", pro: "conf", pri: "conf",
    cmake: "conf", mk: "conf"
}
var byName = { makefile: "conf", dockerfile: "conf", "cmakelists.txt": "conf", pkgbuild: "sh", ".bashrc": "sh", ".zshrc": "sh" }

// The language for a path, or "" for plain text.
function language(path) {
    if (!path) return ""
    var name = String(path).split("/").pop().toLowerCase()
    if (byName[name]) return byName[name]
    var dot = name.lastIndexOf(".")
    if (dot < 0) return ""
    return byExtension[name.substring(dot + 1)] || ""
}

function isIdentStart(ch) { return /[A-Za-z_$]/.test(ch) }
function isIdent(ch) { return /[\w$]/.test(ch) }
function isDigit(ch) { return ch >= "0" && ch <= "9" }

function push(out, type, text) {
    if (text.length === 0) return
    var n = out.length
    if (n >= 2 && out[n - 2] === type) out[n - 1] += text
    else out.push(type, text)
}

// Scans a string body from i up to `close` (honouring backslashes unless
// raw), returning the index just past it, or -1 if the line ends first.
function scanTo(text, i, close, raw) {
    var n = text.length
    while (i < n) {
        if (!raw && text.charAt(i) === "\\") { i += 2; continue }
        if (text.substr(i, close.length) === close) return i + close.length
        ++i
    }
    return -1
}

// Tokenizes one line. `state` is what the previous line left open (null for
// none); returns { tokens, state }.
function tokenize(text, lang, state) {
    text = text === undefined || text === null ? "" : String(text)
    var out = []
    try {
        if (!lang || text.length > limit) {
            push(out, PLAIN, text)
            return { tokens: out, state: null }
        }
        if (lang === "md") return markdown(text)
        if (lang === "html") return html(text, state)
        return code(text, langs[lang] || {}, state)
    } catch (e) {
        return { tokens: [PLAIN, text], state: null }
    }
}

function code(text, L, state) {
    var out = []
    var n = text.length
    var i = 0
    // Something left open by an earlier line.
    if (state && state.close) {
        var end = scanTo(text, 0, state.close, state.type === COMMENT)
        if (end < 0) { push(out, state.type, text); return { tokens: out, state: state } }
        push(out, state.type, text.substring(0, end))
        i = end
    } else if (L.block && !state && /^\s*\*(\s|\/|$)/.test(text)) {
        // A hunk that starts inside a block comment: " * …" lines read as one.
        var close = text.indexOf("*/")
        if (close < 0) { push(out, COMMENT, text); return { tokens: out, state: null } }
        push(out, COMMENT, text.substring(0, close + 2))
        i = close + 2
    }
    // Preprocessor directives read as keywords.
    if (L.pre && i === 0) {
        var m = /^(\s*#\s*[A-Za-z_]+)/.exec(text)
        if (m) { push(out, KEYWORD, m[1]); i = m[1].length }
    }
    var plainFrom = i
    function flush(to) { if (to > plainFrom) push(out, PLAIN, text.substring(plainFrom, to)) }
    while (i < n) {
        var ch = text.charAt(i)
        var next = text.charAt(i + 1)
        // Line comments.
        if ((L.line && text.substr(i, L.line.length) === L.line)
                || (L.hash && ch === "#" && (!L.spaceHash || i === 0 || /\s/.test(text.charAt(i - 1))))) {
            flush(i)
            push(out, COMMENT, text.substring(i))
            return { tokens: out, state: null }
        }
        // Block comments.
        if (L.block && ch === "/" && next === "*") {
            flush(i)
            var e = scanTo(text, i + 2, "*/", true)
            if (e < 0) { push(out, COMMENT, text.substring(i)); return { tokens: out, state: { close: "*/", type: COMMENT } } }
            push(out, COMMENT, text.substring(i, e))
            i = plainFrom = e
            continue
        }
        // Rust lifetimes and chars: 'a' is a char, 'a alone is a lifetime.
        if (L.chars && ch === "'") {
            var cm = /^'(\\.[^']{0,8}|[^'\\])'/.exec(text.substring(i, i + 12))
            if (cm) { flush(i); push(out, STRING, cm[0]); i = plainFrom = i + cm[0].length; continue }
            ++i
            continue
        }
        // Strings.
        if (L.quotes && L.quotes.indexOf(ch) >= 0) {
            flush(i)
            if (L.triple && text.substr(i, 3) === ch + ch + ch) {
                var q3 = ch + ch + ch
                var e3 = scanTo(text, i + 3, q3, false)
                if (e3 < 0) { push(out, STRING, text.substring(i)); return { tokens: out, state: { close: q3, type: STRING } } }
                push(out, STRING, text.substring(i, e3))
                i = plainFrom = e3
                continue
            }
            var es = scanTo(text, i + 1, ch, false)
            if (es < 0) {
                push(out, STRING, text.substring(i))
                // Template and raw strings run on; the others end with the line.
                return { tokens: out, state: L.multi && L.multi.indexOf(ch) >= 0 ? { close: ch, type: STRING } : null }
            }
            push(out, STRING, text.substring(i, es))
            i = plainFrom = es
            continue
        }
        // Numbers, not inside identifiers.
        if ((isDigit(ch) || (ch === "." && isDigit(next))) && (i === 0 || !isIdent(text.charAt(i - 1)))) {
            var nm = /^(0[xX][0-9a-fA-F_']+|0[bB][01_']+|\d[\d_']*\.?\d*([eE][+-]?\d+)?|\.\d+([eE][+-]?\d+)?)[A-Za-z%]*/.exec(text.substring(i, i + 64))
            if (nm && nm[0].length > 0) { flush(i); push(out, NUMBER, nm[0]); i = plainFrom = i + nm[0].length; continue }
        }
        // CSS: hex colours and at-rules.
        if (L.hex && ch === "#" && /[0-9a-fA-F]/.test(next)) {
            var hm = /^#[0-9a-fA-F]{3,8}\b/.exec(text.substring(i, i + 10))
            if (hm) { flush(i); push(out, NUMBER, hm[0]); i = plainFrom = i + hm[0].length; continue }
        }
        if (L.at && ch === "@" && isIdentStart(next)) {
            var am = /^@[\w-]+/.exec(text.substring(i, i + 64))
            flush(i); push(out, KEYWORD, am[0]); i = plainFrom = i + am[0].length
            continue
        }
        // Words: keywords stand out, the rest stays plain.
        if (isIdentStart(ch)) {
            var j = i + 1
            while (j < n && isIdent(text.charAt(j))) ++j
            var word = text.substring(i, j)
            if (L.kw && L.kw.hasOwnProperty(word) && text.charAt(i - 1) !== "." && text.charAt(i - 1) !== "$") {
                flush(i); push(out, KEYWORD, word); plainFrom = j
            }
            i = j
            continue
        }
        ++i
    }
    flush(n)
    return { tokens: out, state: null }
}

function markdown(text) {
    var out = []
    if (/^\s{0,3}#{1,6}(\s|$)/.test(text)) { push(out, KEYWORD, text); return { tokens: out, state: null } }
    if (/^\s*(```|~~~)/.test(text)) { push(out, COMMENT, text); return { tokens: out, state: null } }
    // Inline code reads as a string.
    var i = 0, from = 0, n = text.length
    while (i < n) {
        if (text.charAt(i) === "`") {
            var e = text.indexOf("`", i + 1)
            if (e < 0) break
            if (i > from) push(out, PLAIN, text.substring(from, i))
            push(out, STRING, text.substring(i, e + 1))
            i = from = e + 1
            continue
        }
        ++i
    }
    if (from < n) push(out, PLAIN, text.substring(from))
    return { tokens: out, state: null }
}

function html(text, state) {
    var out = []
    var n = text.length
    var i = 0
    if (state && state.close) {
        var e0 = text.indexOf(state.close)
        if (e0 < 0) { push(out, COMMENT, text); return { tokens: out, state: state } }
        push(out, COMMENT, text.substring(0, e0 + state.close.length))
        i = e0 + state.close.length
    }
    var from = i
    var inTag = false
    while (i < n) {
        var ch = text.charAt(i)
        if (!inTag && text.substr(i, 4) === "<!--") {
            if (i > from) push(out, PLAIN, text.substring(from, i))
            var e = text.indexOf("-->", i + 4)
            if (e < 0) { push(out, COMMENT, text.substring(i)); return { tokens: out, state: { close: "-->", type: COMMENT } } }
            push(out, COMMENT, text.substring(i, e + 3))
            i = from = e + 3
            continue
        }
        if (!inTag && ch === "<") {
            var m = /^<\/?[A-Za-z][\w:.-]*/.exec(text.substring(i, i + 64))
            if (m) {
                if (i > from) push(out, PLAIN, text.substring(from, i))
                push(out, PLAIN, m[0].charAt(1) === "/" ? "</" : "<")
                push(out, KEYWORD, m[0].substring(m[0].charAt(1) === "/" ? 2 : 1))
                i = from = i + m[0].length
                inTag = true
                continue
            }
        }
        if (inTag && (ch === "\"" || ch === "'")) {
            if (i > from) push(out, PLAIN, text.substring(from, i))
            var es = text.indexOf(ch, i + 1)
            var stop = es < 0 ? n : es + 1
            push(out, STRING, text.substring(i, stop))
            i = from = stop
            continue
        }
        if (inTag && ch === ">") inTag = false
        ++i
    }
    if (from < n) push(out, PLAIN, text.substring(from))
    return { tokens: out, state: null }
}

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/\t/g, "    ").replace(/ /g, "&nbsp;")
}

// StyledText for tokens. palette: { keyword, string, comment, number } colour
// strings ("" leaves that kind in the line's own colour). Rich text can't
// set Martian Mono's weight axis, so keywords get their weight from a second
// layer drawn over the first in the medium cut: layer 1 is the line with its
// keywords left out, layer 2 only the keywords. The face is monospaced at
// every weight, so the two lay out and wrap alike. Layer 0 draws it all.
var clear = "#00000000"
function render(tokens, palette, layer) {
    if (!tokens || tokens.length === 0) return "&nbsp;"
    layer = layer || 0
    var s = ""
    for (var k = 0; k + 1 < tokens.length; k += 2) {
        var type = tokens[k]
        var t = escape(tokens[k + 1])
        var colour = type === KEYWORD ? palette.keyword
                   : type === STRING ? palette.string
                   : type === COMMENT ? palette.comment
                   : type === NUMBER ? palette.number : ""
        if (layer === 1 && type === KEYWORD) colour = clear
        else if (layer === 2) colour = type === KEYWORD ? (colour || palette.ink || "") : clear
        if (colour) t = "<font color=\"" + colour + "\">" + t + "</font>"
        if (type === COMMENT) t = "<i>" + t + "</i>"
        s += t
    }
    return s.length > 0 ? s : "&nbsp;"
}

// Whether a line has any keywords, so needs the second layer.
function hasKeywords(tokens) {
    if (!tokens) return false
    for (var k = 0; k < tokens.length; k += 2)
        if (tokens[k] === KEYWORD) return true
    return false
}

// Plain text as StyledText, for lines left unhighlighted.
function plain(text) {
    var t = escape(text === undefined || text === null ? "" : String(text))
    return t.length > 0 ? t : "&nbsp;"
}
