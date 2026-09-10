// Bundled once into editor.js by `npm run build:vendor`. Nothing else in the
// project has a build step; this exists only because CodeMirror 6 ships as
// several dozen ES modules.
export { EditorState, EditorSelection, Compartment, StateField, StateEffect, Prec } from '@codemirror/state'
export { EditorView, Decoration, keymap, lineNumbers, highlightActiveLine,
         highlightActiveLineGutter, drawSelection, rectangularSelection,
         crosshairCursor, placeholder } from '@codemirror/view'
export { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands'
export { StreamLanguage, syntaxHighlighting, HighlightStyle,
         indentUnit, bracketMatching, foldGutter } from '@codemirror/language'
export { coffeeScript } from '@codemirror/legacy-modes/mode/coffeescript'
export { searchKeymap, highlightSelectionMatches } from '@codemirror/search'
export { vim, Vim, getCM } from '@replit/codemirror-vim'
export { tags } from '@lezer/highlight'
