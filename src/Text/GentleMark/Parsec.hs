{-# LANGUAGE DataKinds, FlexibleContexts #-}

module Text.GentleMark.Parsec
       ( text
       , bold, italic, underlined, striked, spoiler
       , latex, monospace
       , quote, reference, hyperlink
       , ulist, olist
       , tag
       , paragraph, style, textualTerm, toplevelTerm
       ) where

import Text.GentleMark.Term

import Control.Applicative hiding ( (<|>), many )
import Data.Function
import Data.List

import Text.Parsec hiding ( newline, parse )
import qualified Text.Parsec as P

(.:) :: (c -> d) -> (a -> b -> c) -> a -> b -> d
(f .: g) x y = f (g x y)

manyTill1 :: Stream s m Char => ParsecT s u m r -> ParsecT s u m e -> ParsecT s u m [r]
manyTill1 p end = (:) <$> p <*> p `manyTill` end

block :: Stream s m Char => ParsecT s u m r -> String -> ParsecT s u m [r]
block p sep = (string sep) *> p `manyTill` try (string sep)

eofOr :: Stream s m Char => ParsecT s u m a -> ParsecT s u m ()
eofOr p = () <$ p <|> eof

whitespaces :: Stream s m Char => ParsecT s u m [Char]
whitespaces = many (char ' ')

newline :: Stream s m Char => ParsecT s u m ()
newline = () <$ many1 P.newline <* whitespaces

hyperlinkPrefixes :: [String]
hyperlinkPrefixes = ["http:", "https:", "ftp:", "mailto:", "news:", "irc:"]

text, bold, italic, underlined, striked, spoiler, latex, monospace, reference, hyperlink, tag, style, textualTerm :: Stream s m Char => ParsecT s u m (Term Textual)

bold       = Bold       <$> block textualTerm "**"
italic     = Italic     <$> block textualTerm "~~"
underlined = Underlined <$> block textualTerm "__"
striked    = Striked    <$> block textualTerm "!!"
spoiler    = Spoiler    <$> block textualTerm "%%"

latex     = Latex     <$> block anyChar "$$"
monospace = Monospace <$> block anyChar "``"

reference = Reference <$> (string ">>" *> many1 digit)

hyperlink = Hyperlink .: (++)
              <$> choice (map string hyperlinkPrefixes)
              <*> anyChar `manyTill` lookAhead (eofOr space)

tag = do name <- char '[' *> many1 (noneOf "|]")
         Tag name
           <$> (many (char '|' *> many (noneOf "|]")) <* char ']')
           <*> (anyChar `manyTill` eofOr (string ("[/" ++ name ++ "]")))

text = Text .: (:)
         <$> (noneOf "\n " <|> (char ' ' <* whitespaces))
         <*> many ((char ' ' <* whitespaces) <|> noneOf (linkChars ++ styleChars ++ ">[\n") <|> nonLink <|> nonStyle)                   
  where
    linkChars = map head hyperlinkPrefixes
    nonLink   = choice nonLinkParsers
      where nonLinkParsers          = map tryNonLink (groupBy ((==) `on` head) hyperlinkPrefixes)
            tryNonLink ws@((c:_):_) = try $ char c <* notFollowedBy (choice $ map (string . tail) ws)
            tryNonLink _            = error "tryNonLink received unsuitable list!"
    
    styleChars = "*~_!%$`"
    nonStyle   = choice $ map (\c -> try $ char c <* notFollowedBy (char c)) styleChars

style        = choice $ map try [bold, italic, underlined, striked, spoiler, latex, monospace]
textualTerm  = choice [ try reference, try hyperlink, style, try tag, try text ]

quote, ulist, olist, paragraph, toplevelTerm :: Stream s m Char => ParsecT s u m (Term Toplevel)

quote = Quote <$> (char '>' *> anyChar `manyTill` newline)

ulist = UList <$> many1 (char '-' *> whitespaces *> textualTerm `manyTill` eofOr newline)

olist = OList <$> many1 ((,) <$> (read <$> (many1 digit <* char '.'))
                             <*> (whitespaces *> textualTerm `manyTill` eofOr newline))

paragraph = Paragraph <$> (textualTerm `manyTill1` eofOr newline)

toplevelTerm = choice $ map try [ ulist, olist, quote, paragraph ]