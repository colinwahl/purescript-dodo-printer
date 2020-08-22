module Dodo
  ( module Exports
  , indent
  , align
  , alignCurrentColumn
  , annotate
  , withPosition
  , text
  , break
  , spaceBreak
  , softBreak
  , space
  , lines
  , words
  , (<%>)
  , (<+>)
  , (</>)
  , appendBreak
  , appendSpace
  , appendSpaceBreak
  , flexAlt
  , flexGroup
  , paragraph
  , textParagraph
  , enclose
  , encloseEmptyAlt
  , encloseWithSeparator
  , foldWithSeparator
  , foldWith
  , print
  , Printer(..)
  , plainText
  , PrintOptions
  , twoSpaces
  , fourSpaces
  , tabs
  ) where

import Prelude

import Data.Foldable (class Foldable, foldl, foldr)
import Data.Int as Int
import Data.List (List, (:))
import Data.List as List
import Data.Maybe (Maybe(..), isJust)
import Data.Monoid (power)
import Data.String as String
import Data.String.Regex as Regex
import Data.String.Regex.Flags (global)
import Data.String.Regex.Unsafe (unsafeRegex)
import Dodo.Internal (Doc(..), Position, bothNotEmpty, isEmpty, notEmpty)
import Dodo.Internal (Doc, Position, bothNotEmpty, isEmpty, notEmpty) as Exports
import Dodo.Internal.Buffer (Buffer)
import Dodo.Internal.Buffer as Buffer

-- | Increases the indentation level by one indent.
indent :: forall a. Doc a -> Doc a
indent = notEmpty Indent

-- | Increases the indentation level by the number of spaces (for alignment purposes).
align :: forall a. Int -> Doc a -> Doc a
align n doc
  | n > 0 = notEmpty (Align n) doc
  | otherwise = doc

-- | Increases the indentation level so that it aligns to the current column.
alignCurrentColumn :: forall a. Doc a -> Doc a
alignCurrentColumn doc = withPosition \pos -> align (pos.column - pos.indent) doc

-- | Adds an annotation to a document. Printers can interpret annotations to style
-- | their output, eg. ANSI colors.
annotate :: forall a. a -> Doc a -> Doc a
annotate = notEmpty <<< Annotate

-- | Attempts to layout the document with flex alternatives, falling back
-- | to defaults if they don't fit the page width.
flexGroup :: forall a. Doc a -> Doc a
flexGroup = notEmpty case _ of
  doc@(FlexGroup _) -> doc
  doc -> FlexGroup doc

-- | Attempts to layout the first document when in a flex group, falling back
-- | to the second as a default.
flexAlt :: forall a. Doc a -> Doc a -> Doc a
flexAlt = FlexAlt

-- | Build a document based on the current layout position.
withPosition :: forall a. (Position -> Doc a) -> Doc a
withPosition = WithPosition

-- | The most basic document leaf. This should not contain newlines. If it does
-- | your document will look very funny.
text :: forall a. String -> Doc a
text = case _ of
  "" -> Empty
  str -> Text (String.length str) str

-- | Inserts a hard line break.
break :: forall a. Doc a
break = Break

-- | Inserts a space when in a flex group, otherwise inserts a break.
spaceBreak :: forall a. Doc a
spaceBreak = flexAlt space break

-- | Inserts nothing when in a flex group, otherwise inserts a break.
softBreak :: forall a. Doc a
softBreak = flexAlt mempty break

-- | A singe space character.
space :: forall a. Doc a
space = text " "

-- | Appends documents with a break in between them.
lines :: forall f a. Foldable f => f (Doc a) -> Doc a
lines = foldr appendBreak Empty

-- | Appends documents with a space in between them.
words :: forall f a. Foldable f => f (Doc a) -> Doc a
words = foldr appendSpace Empty

-- | Appends documents with a space-break in between them.
paragraph :: forall f a. Foldable f => f (Doc a) -> Doc a
paragraph = foldl appendSpaceBreak Empty

-- | Constructs a wrapping paragraph from a blob of text. Ignores newlines and
-- | multiple spaces.
textParagraph :: forall a. String -> Doc a
textParagraph = paragraph <<< map text <<< Regex.split spaceRegex <<< String.trim
  where
  spaceRegex = unsafeRegex """[\s\n]+""" global

-- | Appends two documents with a break between them.
appendBreak :: forall a. Doc a -> Doc a -> Doc a
appendBreak = bothNotEmpty \a b -> a <> (break <> b)

infixr 1 appendBreak as <%>

-- | Appends two documents with a space between them.
appendSpace :: forall a. Doc a -> Doc a -> Doc a
appendSpace = bothNotEmpty \a b -> a <> (space <> b)

infixr 2 appendSpace as <+>

-- | Appends two documents with a space between them, falling back to a
-- | break if that does not fit.
appendSpaceBreak :: forall a. Doc a -> Doc a -> Doc a
appendSpaceBreak = bothNotEmpty \a b -> a <> flexGroup (spaceBreak <> b)

infixl 2 appendSpaceBreak as </>

-- | Uses an opening and closing document to wrap another document.
-- | ```purescript
-- | example = enclose (text "(") (text ")") (text "inner")
-- | ```
enclose :: forall a. Doc a -> Doc a -> Doc a -> Doc a
enclose open close inner = open <> (inner <> close)

-- | Uses an opening and closing document to wrap another document, falling
-- | back when the inner document is empty.
-- | ```purescript
-- | example = encloseEmptyAlt (text "[ ") (text " ]") (text "[]") mempty
-- | ```
encloseEmptyAlt :: forall a. Doc a -> Doc a -> Doc a -> Doc a -> Doc a
encloseEmptyAlt open close default inner
  | isEmpty inner = default
  | otherwise = open <> (inner <> close)

-- | Uses an opening and closing document, as a well as a separator, to render
-- | a series of documents.
-- | ```purescript`
-- | example = encloseWithSeparator (text "[") (text "]") (",") [ text "one", text "two" ]
encloseWithSeparator :: forall f a. Foldable f => Doc a -> Doc a -> Doc a -> f (Doc a) -> Doc a
encloseWithSeparator open close separator inner =
  open <> (foldWithSeparator separator inner <> close)

-- | Appends a series of documents together with a separator in between them.
foldWithSeparator :: forall f a. Foldable f => Doc a -> f (Doc a) -> Doc a
foldWithSeparator separator = foldWith (\a b -> a <> (separator <> b))

-- | Appends a series of documents together with a given append function. This
-- | is notable because it ignores empty documents.
foldWith :: forall f a. Foldable f => (Doc a -> Doc a -> Doc a) -> f (Doc a) -> Doc a
foldWith f = foldr (bothNotEmpty f) mempty

-- | Custom printers can be used to render richer documents than just plain
-- | text.
-- | * `emptyBuffer` - The initial buffer.
-- | * `writeText` - Should write a string with the given width to the buffer.
-- | * `writeIndent` - Should write indentation with the given width to the buffer.
-- | * `writeBreak` - Should write a line break to the buffer.
-- | * `enterAnnotation` - Called when entering a new annotated region. Provides the full annotation stack.
-- | * `leaveAnnotation` - Called when leaving an annotated region. Provides the full annotation stack.
-- | * `flushBuffer` - Called at the end of the document to get the final result.
newtype Printer buff ann res = Printer
  { emptyBuffer :: buff
  , writeText :: Int -> String -> buff -> buff
  , writeIndent :: Int -> String -> buff -> buff
  , writeBreak :: buff -> buff
  , enterAnnotation :: ann -> List ann -> buff -> buff
  , leaveAnnotation :: ann -> List ann -> buff -> buff
  , flushBuffer :: buff -> res
  }

-- | A plain text printer. Can be used with any document.
plainText :: forall a. Printer String a String
plainText = Printer
  { emptyBuffer: ""
  , writeText: \_ str buff -> buff <> str
  , writeIndent: \_ str buff -> buff <> str
  , writeBreak: \buff -> buff <> "\n"
  , enterAnnotation: \_ _ buff -> buff
  , leaveAnnotation: \_ _ buff -> buff
  , flushBuffer: \buff -> buff
  }

-- | Configuration options for the printer.
-- | * `pageWidth` - The printer will try not to exceed this width on any given line.
-- | * `ribbonRatio` - Ratio between 0.0 and 1.0, defaults to 1.0. The printer will
-- |   use this ratio to calculate the printable area between the current indentation
-- |   level and the `pageWidth`.
-- | * `indentUnit` - The string used for a single indent.
-- | * `indentWidth` - The assumed character width of a single `indentUnit`.
type PrintOptions =
  { pageWidth :: Int
  , ribbonRatio :: Number
  , indentUnit :: String
  , indentWidth :: Int
  }

-- | Prints 2-space indents, with a default 80-column page width.
twoSpaces :: PrintOptions
twoSpaces = { pageWidth: 80, ribbonRatio: 1.0, indentUnit: "  ", indentWidth: 2 }

-- | Prints 4-space indents, with a default 120-column page width.
fourSpaces :: PrintOptions
fourSpaces = { pageWidth: 120, ribbonRatio: 1.0, indentUnit: "    ", indentWidth: 4 }

-- | Prints tab indents (4-wide), with a default 120-column page width.
tabs :: PrintOptions
tabs = { pageWidth: 120, ribbonRatio: 1.0, indentUnit: "\t", indentWidth: 4 }

data DocCmd a
  = Doc (Doc a)
  | Dedent String Int
  | LeaveAnnotation a (List a)
  | LeaveFlexGroup

type FlexGroupState b a =
  { position :: Position
  , buffer :: Buffer b
  , annotations :: List a
  , indent :: Int
  , indentSpaces :: String
  , stack :: List (DocCmd a)
  }

type DocState b a =
  { position :: Position
  , buffer :: Buffer b
  , annotations :: List a
  , indent :: Int
  , indentSpaces :: String
  , flexGroup :: Maybe (FlexGroupState b a)
  }

resetState :: forall a b. FlexGroupState b a -> DocState b a
resetState { position, buffer, annotations, indent: indent', indentSpaces } =
  { position, buffer, annotations, indent: indent', indentSpaces, flexGroup: Nothing }

storeState :: forall a b. List (DocCmd a) -> DocState b a -> FlexGroupState b a
storeState stack { position, buffer, annotations, indent: indent', indentSpaces } =
  { position, buffer, annotations, indent: indent', indentSpaces, stack }

-- | Prints a documents given a printer and print options.
-- |
-- | ```purescript
-- | print plainText twoSpaces myDoc
-- | ```
-- |
-- | This will use full line-lookahead from the start of a flex group. If it
-- | encounters a break or content overflows the page-width, it will layout
-- | the group using flex alternative defaults instead.
print :: forall b a r. Printer b a r -> PrintOptions -> Doc a -> r
print (Printer printer) opts = flip go initState <<< pure <<< Doc
  where
  ribbonRatio :: Number
  ribbonRatio = max 0.0 (min 1.0 opts.ribbonRatio)

  calcRibbonWidth :: Int -> Int
  calcRibbonWidth = max 0 <<< Int.ceil <<< mul ribbonRatio <<< Int.toNumber

  initState :: DocState b a
  initState =
    { position:
        { line: 0
        , column: 0
        , indent: 0
        , pageWidth: opts.pageWidth
        , ribbonWidth: calcRibbonWidth opts.pageWidth
        }
    , buffer: Buffer.new printer.emptyBuffer
    , annotations: List.Nil
    , indent: 0
    , indentSpaces: ""
    , flexGroup: Nothing
    }

  go :: List (DocCmd a) -> DocState b a -> r
  go stack state = case stack of
    List.Nil ->
      printer.flushBuffer $ Buffer.get state.buffer
    cmd : stk -> case cmd of
      Doc doc -> case doc of
        Append doc1 doc2 ->
          go (Doc doc1 : Doc doc2 : stk) state
        Text len str
          | state.position.column == 0 && state.indent > 0 ->
              go stack state
                { position
                    { column = state.indent
                    , indent = state.indent
                    , ribbonWidth = calcRibbonWidth (opts.pageWidth - state.indent)
                    }
                , buffer = Buffer.modify (printer.writeIndent state.indent state.indentSpaces) state.buffer
                }
          | otherwise -> do
              let nextColumn = state.position.column + len
              case state.flexGroup of
                Just frame | nextColumn > state.position.indent + state.position.ribbonWidth ->
                  go frame.stack $ resetState frame
                _ ->
                  go stk state
                    { position { column = nextColumn }
                    , buffer = Buffer.modify (printer.writeText len str) state.buffer
                    }
        Break -> case state.flexGroup of
          Just frame ->
            go frame.stack $ resetState frame
          _ ->
            go stk state
              { position
                  { line = state.position.line + 1
                  , column = 0
                  , indent = state.indent
                  , ribbonWidth = calcRibbonWidth (opts.pageWidth - state.indent)
                  }
              , buffer = Buffer.modify printer.writeBreak state.buffer
              }
        Indent doc1
          | isJust state.flexGroup ->
              go (Doc doc1 : stk) state
          | otherwise ->
              go (Doc doc1 : Dedent state.indentSpaces state.indent : stk) state
                { indent = state.indent + opts.indentWidth
                , indentSpaces = state.indentSpaces <> opts.indentUnit
                }
        Align width doc1
          | isJust state.flexGroup ->
              go (Doc doc1 : stk) state
          | otherwise ->
              go (Doc doc1 : Dedent state.indentSpaces state.indent : stk) state
                { indent = state.indent + width
                , indentSpaces = state.indentSpaces <> power " " width
                }
        FlexGroup doc1
          -- We only track the first flex group. This is equivalent to
          -- end-of-line lookahead.
          | isJust state.flexGroup || state.position.ribbonWidth == 0 ->
              go (Doc doc1 : stk) state
          | otherwise ->
              go (Doc doc1 : LeaveFlexGroup : stk) state
                { flexGroup = Just $ storeState (Doc doc1 : stk) state
                , buffer = Buffer.branch state.buffer
                }
        FlexAlt flexDoc doc1
          | isJust state.flexGroup ->
              go (Doc flexDoc : stk) state
          | otherwise ->
              go (Doc doc1 : stk) state
        WithPosition k
          | state.position.column == 0 && state.indent > state.position.indent -> do
              let
                renderPosition = state.position
                  { column = state.indent
                  , indent = state.indent
                  , ribbonWidth = calcRibbonWidth (opts.pageWidth - state.indent)
                  }
              go (Doc (k renderPosition) : stk) state
          | otherwise ->
              go (Doc (k state.position) : stk) state
        Annotate ann doc1 ->
          go (Doc doc1 : LeaveAnnotation ann state.annotations : stk) state
            { annotations = ann : state.annotations
            , buffer = Buffer.modify (printer.enterAnnotation ann state.annotations) state.buffer
            }
        Empty ->
          go stk state
      LeaveFlexGroup ->
        go stk state
          { flexGroup = Nothing
          , buffer = Buffer.commit state.buffer
          }
      Dedent indSpaces ind ->
        go stk state
          { indent = ind
          , indentSpaces = indSpaces
          }
      LeaveAnnotation ann anns ->
        go stk state
          { annotations = anns
          , buffer = Buffer.modify (printer.leaveAnnotation ann anns) state.buffer
          }
