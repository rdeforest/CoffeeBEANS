// mode/coffeescript.js from @codemirror/legacy-modes 6.5.4 (unchanged in
// 6.5.5), Copyright (C) 2018-2021 by Marijn Haverbeke and others, MIT
// licence (node_modules/@codemirror/legacy-modes/LICENSE). Patched by Claude
// on 2026-10-08 to tell division from a regex: upstream took any `/` with
// another `/` later on the line for a regex, so `h2 / tan(fov / 2)` coloured
// `/ tan(fov /`. The package stays in package.json as the diff base: diff
// this file against its copy to see the patch, which is meant for upstream
// once this header is stripped.

var ERRORCLASS = "error";

function wordRegexp(words) {
  return new RegExp("^((" + words.join(")|(") + "))\\b");
}

var operators = /^(?:->|=>|\+[+=]?|-[\-=]?|\*[\*=]?|\/[\/=]?|[=!]=|<[><]?=?|>>?=?|%=?|&=?|\|=?|\^=?|\~|!|\?|(or|and|\|\||&&|\?)=)/;
var delimiters = /^(?:[()\[\]{},:`=;]|\.\.?\.?)/;
var identifiers = /^[_A-Za-z$][_A-Za-z$0-9]*/;
var atProp = /^@[_A-Za-z$][_A-Za-z$0-9]*/;

var wordOperators = wordRegexp(["and", "or", "not",
                                "is", "isnt", "in",
                                "instanceof", "typeof"]);
var indentKeywords = ["for", "while", "loop", "if", "unless", "else",
                      "switch", "try", "catch", "finally", "class"];
var commonKeywords = ["break", "by", "continue", "debugger", "delete",
                      "do", "in", "of", "new", "return", "then",
                      "this", "@", "throw", "when", "until", "extends"];

var keywords = wordRegexp(indentKeywords.concat(commonKeywords));

indentKeywords = wordRegexp(indentKeywords);


var stringPrefixes = /^('{3}|\"{3}|['\"])/;
var regexPrefixes = /^(\/{3}|\/)/;
var commonConstants = ["Infinity", "NaN", "undefined", "null", "true", "false", "on", "off", "yes", "no"];
var constants = wordRegexp(commonConstants);

// Tokenizers
function tokenBase(stream, state) {
  // Handle scope changes
  if (stream.sol()) {
    if (state.scope.align === null) state.scope.align = false;
    var scopeOffset = state.scope.offset;
    if (stream.eatSpace()) {
      var lineOffset = stream.indentation();
      if (lineOffset > scopeOffset && state.scope.type == "coffee") {
        return "indent";
      } else if (lineOffset < scopeOffset) {
        return "dedent";
      }
      return null;
    } else {
      if (scopeOffset > 0) {
        dedent(stream, state);
      }
    }
  }
  if (stream.eatSpace()) {
    return null;
  }

  var ch = stream.peek();

  // Handle docco title comment (single line)
  if (stream.match("####")) {
    stream.skipToEnd();
    return "comment";
  }

  // Handle multi line comments
  if (stream.match("###")) {
    state.tokenize = longComment;
    return state.tokenize(stream, state);
  }

  // Single line comment
  if (ch === "#") {
    stream.skipToEnd();
    return "comment";
  }

  // Handle number literals
  if (stream.match(/^-?[0-9\.]/, false)) {
    var floatLiteral = false;
    // Floats
    if (stream.match(/^-?\d*\.\d+(e[\+\-]?\d+)?/i)) {
      floatLiteral = true;
    }
    if (stream.match(/^-?\d+\.\d*/)) {
      floatLiteral = true;
    }
    if (stream.match(/^-?\.\d+/)) {
      floatLiteral = true;
    }

    if (floatLiteral) {
      // prevent from getting extra . on 1..
      if (stream.peek() == "."){
        stream.backUp(1);
      }
      return "number";
    }
    // Integers
    var intLiteral = false;
    // Hex
    if (stream.match(/^-?0x[0-9a-f]+/i)) {
      intLiteral = true;
    }
    // Decimal
    if (stream.match(/^-?[1-9]\d*(e[\+\-]?\d+)?/)) {
      intLiteral = true;
    }
    // Zero by itself with no other piece of number.
    if (stream.match(/^-?0(?![\dx])/i)) {
      intLiteral = true;
    }
    if (intLiteral) {
      return "number";
    }
  }

  // Handle strings
  if (stream.match(stringPrefixes)) {
    state.tokenize = tokenFactory(stream.current(), false, "string");
    return state.tokenize(stream, state);
  }
  // Handle regex literals
  if (stream.match(regexPrefixes)) {
    if (stream.current() != "/" || regexFollows(stream, state)) {
      state.tokenize = tokenFactory(stream.current(), true, "string.special");
      return state.tokenize(stream, state);
    } else {
      stream.backUp(1);
    }
  }



  // Handle operators and delimiters
  if (stream.match(operators) || stream.match(wordOperators)) {
    return "operator";
  }
  if (stream.match(delimiters)) {
    return "punctuation";
  }

  if (stream.match(constants)) {
    return "atom";
  }

  if (stream.match(atProp) || state.prop && stream.match(identifiers)) {
    return "property";
  }

  if (stream.match(keywords)) {
    return "keyword";
  }

  if (stream.match(identifiers)) {
    return "variable";
  }

  // Handle non-detected items
  stream.next();
  return ERRORCLASS;
}

// Called just past a lone `/`. Close to CoffeeScript's own lexer: a regex
// must close on this line and is never `//`; after a value the slash is
// division, except after a name, `)`, `]` or `this` with a space between,
// where `f /re/` is a call with a regex -- unless the would-be regex itself
// starts with a space, as in `f / 2`.
function regexFollows(stream, state) {
  if (!stream.match(/^[^\/].*\//, false)) return false;
  if (state.after == "value") return false;
  if (state.after == "callable")
    return /\s/.test(stream.string.charAt(stream.start - 1)) && !stream.match(/^=?\s/, false);
  return true;
}

// What a token leaves behind for a `/` after it: "callable" for what
// CoffeeScript may call implicitly, "value" for any other value, or null
// where a regex can start.
function valueKind(style, current) {
  if (style == "variable" || style == "property" || /^(?:[)\]?@]|this)$/.test(current))
    return "callable";
  if (style == "number" || style == "atom" || style == "string" || style == "string.special" ||
      /^(?:}|\+\+|--)$/.test(current))
    return "value";
  return null;
}

function tokenFactory(delimiter, singleline, outclass) {
  return function(stream, state) {
    while (!stream.eol()) {
      stream.eatWhile(/[^'"\/\\]/);
      if (stream.eat("\\")) {
        stream.next();
        if (singleline && stream.eol()) {
          return outclass;
        }
      } else if (stream.match(delimiter)) {
        state.tokenize = tokenBase;
        return outclass;
      } else {
        stream.eat(/['"\/]/);
      }
    }
    if (singleline) {
      state.tokenize = tokenBase;
    }
    return outclass;
  };
}

function longComment(stream, state) {
  while (!stream.eol()) {
    stream.eatWhile(/[^#]/);
    if (stream.match("###")) {
      state.tokenize = tokenBase;
      break;
    }
    stream.eatWhile("#");
  }
  return "comment";
}

function indent(stream, state, type = "coffee") {
  var offset = 0, align = false, alignOffset = null;
  for (var scope = state.scope; scope; scope = scope.prev) {
    if (scope.type === "coffee" || scope.type == "}") {
      offset = scope.offset + stream.indentUnit;
      break;
    }
  }
  if (type !== "coffee") {
    align = null;
    alignOffset = stream.column() + stream.current().length;
  } else if (state.scope.align) {
    state.scope.align = false;
  }
  state.scope = {
    offset: offset,
    type: type,
    prev: state.scope,
    align: align,
    alignOffset: alignOffset
  };
}

function dedent(stream, state) {
  if (!state.scope.prev) return;
  if (state.scope.type === "coffee") {
    var _indent = stream.indentation();
    var matched = false;
    for (var scope = state.scope; scope; scope = scope.prev) {
      if (_indent === scope.offset) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      return true;
    }
    while (state.scope.prev && state.scope.offset !== _indent) {
      state.scope = state.scope.prev;
    }
    return false;
  } else {
    state.scope = state.scope.prev;
    return false;
  }
}

function tokenLexer(stream, state) {
  var style = state.tokenize(stream, state);
  var current = stream.current();

  // Handle scope changes.
  if (current === "return") {
    state.dedent = true;
  }
  if (((current === "->" || current === "=>") && stream.eol())
      || style === "indent") {
    indent(stream, state);
  }
  var delimiter_index = "[({".indexOf(current);
  if (delimiter_index !== -1) {
    indent(stream, state, "])}".slice(delimiter_index, delimiter_index+1));
  }
  if (indentKeywords.exec(current)){
    indent(stream, state);
  }
  if (current == "then"){
    dedent(stream, state);
  }


  if (style === "dedent") {
    if (dedent(stream, state)) {
      return ERRORCLASS;
    }
  }
  delimiter_index = "])}".indexOf(current);
  if (delimiter_index !== -1) {
    while (state.scope.type == "coffee" && state.scope.prev)
      state.scope = state.scope.prev;
    if (state.scope.type == current)
      state.scope = state.scope.prev;
  }
  if (state.dedent && stream.eol()) {
    if (state.scope.type == "coffee" && state.scope.prev)
      state.scope = state.scope.prev;
    state.dedent = false;
  }

  return style == "indent" || style == "dedent" ? null : style;
}

export const coffeeScript = {
  name: "coffeescript",
  startState: function() {
    return {
      tokenize: tokenBase,
      scope: {offset: 0, type:"coffee", prev: null, align: false},
      prop: false,
      after: null,
      dedent: 0
    };
  },

  token: function(stream, state) {
    var fillAlign = state.scope.align === null && state.scope;
    if (fillAlign && stream.sol()) fillAlign.align = false;

    if (stream.sol()) state.after = null;
    var style = tokenLexer(stream, state);
    if (style && style != "comment") {
      if (fillAlign) fillAlign.align = true;
      state.prop = style == "punctuation" && stream.current() == "."
      state.after = valueKind(style, stream.current());
    }

    return style;
  },

  indent: function(state, text) {
    if (state.tokenize != tokenBase) return 0;
    var scope = state.scope;
    var closer = text && "])}".indexOf(text.charAt(0)) > -1;
    if (closer) while (scope.type == "coffee" && scope.prev) scope = scope.prev;
    var closes = closer && scope.type === text.charAt(0);
    if (scope.align)
      return scope.alignOffset - (closes ? 1 : 0);
    else
      return (closes ? scope.prev : scope).offset;
  },

  languageData: {
    commentTokens: {line: "#"}
  }
};
