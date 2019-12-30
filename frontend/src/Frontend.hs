{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE TypeApplications #-}

module Frontend where

import Control.Lens (Prism', ix, prism', re)
import qualified Data.IntervalMap.Generic.Strict as IntervalMap
import Data.IntervalMap.Generic.Strict (IntervalMap)
import Data.IntervalMap.Interval (Interval (..))
import Data.List (sort, foldl')
import qualified Data.Map as Map
import qualified Data.Map.Monoidal as MMap
import Data.Semigroup (First (..))
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import qualified Data.Set as Set
import qualified Data.Text as T
import Data.These (These (This, That, These))
import Control.Monad.Fix (MonadFix)
import Obelisk.Configs (HasConfigs)
import Obelisk.Frontend (Frontend (..))
import Obelisk.Route.Frontend
import Reflex.Dom.Core
import Rhyolite.Api (ApiRequest, public)
import Rhyolite.Frontend.App (RhyoliteWidget, functorToWire, runObeliskRhyoliteWidget, watchViewSelector)
import Text.Read (readMaybe)

import Obelisk.Generated.Static

import Common.App
import Common.Route
import Common.Prelude
import Common.Schema
import Data.Bible

import Frontend.Selection (selectionStart)


frontend :: Frontend (R FrontendRoute)
frontend = Frontend
  { _frontend_head = headSection
  , _frontend_body = runAppWidget $ skeleton $ subRoute_ $ \case
      FrontendRoute_Main -> appWidget (pure (Canon_Old Genesis, Nothing))
      FrontendRoute_Reference -> appWidget =<< askRoute
  }

headSection :: DomBuilder t m => m ()
headSection = do
  elAttr "meta" ("charset"=:"utf-8") blank
  elAttr "meta" ("name"=:"viewport" <> "content"=:"width=device-width, initial-scale=1") blank
  elAttr "link" ("rel"=:"stylesheet" <> "type"=:"text/css" <> "href"=:static @"css/bulma.css") blank
  el "title" $ text "Something"
  elAttr "script" ("defer"=:"defer" <> "src"=:"https://use.fontawesome.com/releases/v5.3.1/js/all.js") blank

runAppWidget ::
  ( HasConfigs m
  , TriggerEvent t m
  , PerformEvent t m
  , MonadHold t m
  , PostBuild t m
  , MonadFix m
  , Prerender x t m
  )
  => RoutedT t (R FrontendRoute) (RhyoliteWidget (ViewSelector SelectedCount) (ApiRequest () PublicRequest PrivateRequest) t m) a
  -> RoutedT t (R FrontendRoute) m a
runAppWidget = runObeliskRhyoliteWidget
  functorToWire
  "common/route"
  checkedFullRouteEncoder
  (BackendRoute_Listen :/ ())


skeleton
  :: (DomBuilder t m, MonadHold t m, PostBuild t m, MonadFix m, SetRoute t (R FrontendRoute) m)
  => m a -> m a
skeleton body = do
  navBar
  a <- elClass "section" "section" body
  footer
  pure a


navBar
  :: (DomBuilder t m, MonadHold t m, PostBuild t m, MonadFix m, SetRoute t (R FrontendRoute) m)
  => m ()
navBar =
  elAttr "nav" ("class"=:"navbar" <> "role"=:"navigation" <> "aria-label"=:"main navigation") $ do
    divClass "navbar-brand" $
      elAttr "a" ("class"=:"navbar-item" <> "href"=:"https://bulma.io") $ text "Tree of Life"
        -- elAttr "img" ("src"=:"https://bulma.io/images/bulma-logo.png" <> "width"=:"112" <> "height"=:"28") blank

    (burgerEl, ()) <- elAttr' "a" ("role"=:"button" <> "class"=:"navbar-burger burger" <> "aria-label"=:"menu") $ do
      let ln = elAttr "span" ("aria-hidden"=:"true") blank
      ln *> ln *> ln

    menuIsActive <- toggle False $ domEvent Click burgerEl

    elDynAttr "div" (ffor menuIsActive $ \active -> "class"=:("navbar-menu" <> if active then " is-active" else "")) $ do
      divClass "navbar-start" $ do
        elClass "a" "navbar-item" $ text "Home"
        elClass "a" "navbar-item" $ text "Documentation"
        divClass "navbar-item has-dropdown is-hoverable" $ do
          elClass "a" "navbar-link" $ text "More"

          divClass "navbar-dropdown" $ do
            elClass "a" "navbar-item" $ text "About"
            elClass "a" "navbar-item" $ text "Jobs"
            elClass "a" "navbar-item" $ text "Contact"

            elClass "hr" "navbar-divider" blank
            elClass "a" "navbar-item" $ text "Report an issue"
        divClass "navbar-item" $
          divClass "field has-addons" $ do
            (refValue, enterPressed) <- elClass "p" "control" $ do
              inputEl <- inputElement $ def & initialAttributes .~ ("class"=:"input" <> "type"=:"text" <> "placeholder"=:"Go to reference")
              pure (value inputEl, keypress Enter $ _inputElement_element inputEl)

            goClicked <- elClass "p" "control" $ do
              (buttonEl, ()) <- elAttr' "button" ("class"=:"button" <> "type"=:"button") $
                text "Go"
              pure $ domEvent Click buttonEl

            let goToValidRef =
                  mapMaybe (either (const Nothing) Just . parseBibleReference) $ current refValue
                  <@ leftmost [goClicked, enterPressed]
            setRoute $ (FrontendRoute_Reference :/) <$> goToValidRef

      divClass "navbar-end" $
        divClass "navbar-item" $
          divClass "buttons" $ do
            elClass "a" "button is-primary" $
              el "strong" $ text "Sign up"
            elClass "a" "button is-light" $ text "Log in"

footer :: DomBuilder t m => m ()
footer =
  elClass "footer" "footer" $
    divClass "content has-text-centered" $
      el "p" $ do
        el "strong" (text "Tree of Life") *> text " by Roy Almasy and Elliot Cameron. The source code is licensed "
        elAttr "a" ("href"=:"http://opensource.org/licenses/mit-license.php") (text "MIT")
        text ". The website content is licensed " *> elAttr "a" ("href"=:"http://creativecommons.org/licenses/by-nc-sa/4.0/") (text "CC BY NC SA 4.0")

type HasApp t m =
  ( MonadQuery t (ViewSelector SelectedCount) m
  , Requester t m
  , Request m ~ ApiRequest () PublicRequest PrivateRequest
  , Response m ~ Identity
  )

defaultTranslation :: TranslationId
defaultTranslation = TranslationId 1

data IntervalEndpointType = Closed | Open deriving (Bounded, Enum, Eq, Generic, Ord, Show)

data IntervalEndpointPosition = Starting | Ending deriving (Bounded, Enum, Eq, Generic, Ord, Show)

data IntervalEndpoint a = IntervalEndpoint
  { _intervalEndpoint_value :: !a
  , _intervalEndpoint_type :: !IntervalEndpointType
  , _intervalEndpoint_position :: !IntervalEndpointPosition
  }
  deriving (Eq, Generic, Show)
instance Ord a => Ord (IntervalEndpoint a) where
  compare (IntervalEndpoint a' aType _) (IntervalEndpoint b' bType _) = case ((a', aType), (b', bType)) of
    ((a, Closed), (b, Open)) | a == b -> LT
    ((a, Open), (b, Closed)) | a == b -> GT
    ((a, _), (b, _)) -> compare a b

intervalToEndpoints :: Interval a -> (IntervalEndpoint a, IntervalEndpoint a)
intervalToEndpoints = \case
  IntervalCO a b -> (IntervalEndpoint a Closed Starting, IntervalEndpoint b Open Ending)
  IntervalOC a b -> (IntervalEndpoint a Open Starting, IntervalEndpoint b Closed Ending)
  ClosedInterval a b -> (IntervalEndpoint a Closed Starting, IntervalEndpoint b Closed Ending)
  OpenInterval a b -> (IntervalEndpoint a Open Starting, IntervalEndpoint b Open Ending)

endpointsToInterval :: (IntervalEndpoint a, IntervalEndpoint a) -> Interval a
endpointsToInterval = \case
  (IntervalEndpoint a Closed _, IntervalEndpoint b Open _) -> IntervalCO a b
  (IntervalEndpoint a Open _, IntervalEndpoint b Closed _) -> IntervalOC a b
  (IntervalEndpoint a Closed _, IntervalEndpoint b Closed _) -> ClosedInterval a b
  (IntervalEndpoint a Open _, IntervalEndpoint b Open _) -> OpenInterval a b

newtype Ascending a = Ascending { unAscending :: [a] } deriving (Eq, Functor, Monoid, Ord, Semigroup)

filterAscending :: forall a. (a -> Bool) -> Ascending a -> Ascending a
filterAscending = coerce (filter :: (a -> Bool) -> [a] -> [a])

nonOverlapping
  :: forall k v. (Ord k)
  => IntervalMap (Interval k) v
  -> Ascending (Interval k)
nonOverlapping xs | null xs = mempty
nonOverlapping xs = Ascending $ toList $ foldl'
  (\intervals (this, next) ->
    let
      open x = x{_intervalEndpoint_type = Open}
      interval = case (_intervalEndpoint_position this, _intervalEndpoint_position next) of
        (Starting, Ending) -> (this, next)
        (Starting, Starting) -> (this, open next)
        (Ending, Ending) -> (open this, next)
        (Ending, Starting) -> (open this, open next)
    in intervals Seq.:|> endpointsToInterval interval
  )
  mempty
  (zip endpoints (tail endpoints))
  where
    endpoints :: [IntervalEndpoint k] = sort $ fold $ do
      interval <- IntervalMap.keys xs
      let (left, right) = intervalToEndpoints interval
      pure [left, right]

verseWords :: Text -> Seq Text
verseWords = Seq.fromList . filter (not . T.null) . T.split (' '==)

type WordInterval = Interval (VerseReference, Int)

versesToRanges :: MonoidalMap VerseReference Text -> IntervalMap WordInterval ()
versesToRanges
  =   fmap verseWords
  >>> MMap.mapWithKey verseWordsToInterval
  >>> MMap.elems
  >>> map (, ())
  >>> IntervalMap.fromList -- TODO: Can we use fromAscList?
  where
    verseWordsToInterval :: VerseReference -> Seq Text -> Interval (VerseReference, Int)
    verseWordsToInterval vref ws = ClosedInterval (vref, 0) (vref, length ws - 1)

tagsToRanges :: MonoidalMap Text (Set (VerseReference, Int, VerseReference, Int)) -> IntervalMap WordInterval (Set Text)
tagsToRanges tagMap = IntervalMap.fromListWith (<>)
  [ (ClosedInterval (vref1, w1) (vref2, w2), Set.singleton t)
  | (t, ranges) <- MMap.toList tagMap
  , (vref1, w1, vref2, w2) <- toList ranges
  ]

verseWordMap :: MonoidalMap VerseReference Text -> IntervalMap WordInterval Text
verseWordMap
  =   fmap verseWords -- TODO: Factor this out as it's done in multiple places
  >>> MMap.mapWithKey (\vref ws -> [(ClosedInterval (vref, idx) (vref, idx), w) | (idx, w) <- zip [0..] (toList ws)])
  >>> MMap.elems
  >>> concat
  >>> IntervalMap.fromList -- TODO: Can this be fromAscList?


wordCharacterRanges :: Text -> Seq (Int, Int)
wordCharacterRanges t =
  let
    (lastIndex, lastPrevBreak, lastRanges) = T.foldl
      (\(!index, !prevBreak, ranges) c -> if isWordSeparator c
          then (index + 1, index + 1, ranges Seq.|> (prevBreak, index))
          else (index + 1, prevBreak, ranges)
      )
      (0, 0, mempty)
      t
  in if lastPrevBreak < lastIndex
    then lastRanges Seq.|> (lastPrevBreak, lastIndex)
    else lastRanges

isWordSeparator :: Char -> Bool
isWordSeparator = (`elem` [' ', '\n', '\r', '\t', '—', '–', '-'])

combineTagsAndVerses
  :: IntervalMap WordInterval ()
  -> IntervalMap WordInterval (Set Text)
  -> IntervalMap WordInterval (These (Set Text) ())
combineTagsAndVerses verses tagRanges = IntervalMap.unionWith merge_ (This <$> tagRanges) (That <$> verses)
  where
    merge_ (This a) (That b) = These a b
    merge_ _ _ = error "Impossible"

mkNonOverlappingDomSegments
  :: MonoidalMap VerseReference Text
  -> IntervalMap WordInterval (Set Text)
  -> Ascending WordInterval
mkNonOverlappingDomSegments verses tagRanges = filterAscending filt $ nonOverlapping $ combineTagsAndVerses (versesToRanges verses) tagRanges
  where
    -- We can drop any interval that ends with an open endpoint on a 0th word. That interval
    -- corresponds to the spans between verses and those will never contain any text.
    filt (IntervalCO _ (_, 0)) = False
    filt (OpenInterval _ (_, 0)) = False
    filt _ = True

newtype CharacterIndex a = CharacterIndex a deriving (Enum, Eq, Ord, Show)

appWidget
  :: forall m js t. (HasApp t m, DomBuilder t m, PostBuild t m, MonadHold t m, MonadFix m, Prerender js t m)
  => Dynamic t (Canon, Maybe (Int, Maybe Int))
  -> m ()
appWidget referenceDyn = do
  now <- getPostBuild

  wordClickedRaw :: Event t (IntervalEndpoint (VerseReference, Int), CharacterIndex Int) <-
    mapMaybe
      (\(startRef, startWord, endRef, endWord) ->
          let
            start = (startRef, startWord)
            end = (endRef, endWord)
          in if start == end -- Start and end points must be the same for it to count as a "click"
              then (, CharacterIndex $ start ^. _2) <$> start ^? _1 . wordStartingEndpointEncoding
              else Nothing
      )
    <$> selectionStart

  rec
    (verses, tags) <- watchVerses $ (defaultTranslation, ) <$> range

    let wordClicked = attachWithMaybe
          (\vs (IntervalEndpoint (vref, rangeStartWordIndex) _ _, CharacterIndex charIndex) -> do
            verseText <- MMap.lookup vref vs
            let indexedWordCharacterRanges = wordCharacterRanges verseText
            (rangeStartCharacterIndex :: Int, _) <- Seq.lookup rangeStartWordIndex indexedWordCharacterRanges
            -- TODO: Do we really need to go through 'IntervalMap' to get this? Could we just search the 'Sequence' directly? A binary search would work.
            -- Need benchmarks to really know for sure.
            let charRanges :: IntervalMap (Interval Int) Int = IntervalMap.fromAscList $ map (\(wordIndex :: Int, (startChar :: Int, endChar)) -> (ClosedInterval startChar (endChar - 1), wordIndex)) $ zip [0..] $ toList indexedWordCharacterRanges
            (_, clickedWordIndex) <- listToMaybe $ IntervalMap.toAscList $ IntervalMap.containing charRanges (rangeStartCharacterIndex + charIndex)
            Just (vref, clickedWordIndex)
          )
          (fromMaybe mempty <$> current verses)
          wordClickedRaw

    highlightState <- foldDyn toggleMaybe Nothing wordClicked
    let
      captureRange :: Maybe (VerseReference, Int) -> (VerseReference, Int) -> Maybe ((VerseReference, Int), (VerseReference, Int))
      captureRange firstWord lastWord = firstWord <&> \fstWord -> if lastWord >= fstWord
        then (fstWord, lastWord)
        else (lastWord, fstWord)

      highlightFinished :: Event t ((VerseReference, Int), (VerseReference, Int)) =
        fmapMaybe id $ captureRange <$> current highlightState <@> wordClicked

    _ <- requestingIdentity $ ffor highlightFinished $ \(start, end) ->
      public $ PublicRequest_AddTag $ TagOccurrence "test" defaultTranslation start end

    text "Range:"
    widgetHold_ (text "") $ ffor highlightFinished $ \w -> text (tshow w)
    versesWidget verses tags

    routeRangeDyn <- holdUniqDyn $ referenceToInterval . referenceToVerseReference <$> referenceDyn
    range <- foldDyn ($) (IntervalCO (VerseReferenceT (BookId 1) 1 1) (VerseReferenceT (BookId 1) 3 9999)) $ leftmost
      [ const <$> current routeRangeDyn <@ now
      , const <$> updated routeRangeDyn
      ]

  pure ()

  where
    referenceToVerseReference :: (Canon, Maybe (Int, Maybe Int)) -> VerseReference
    referenceToVerseReference (b, verseChap) = VerseReferenceT (BookId $ fromEnum b + 1) chap verse
      where
        chap = maybe 1 fst verseChap
        verse = fromMaybe 1 $ snd =<< verseChap

    referenceToInterval :: VerseReference -> Interval VerseReference
    referenceToInterval (VerseReferenceT (BookId b) c _) = IntervalCO
      (VerseReferenceT (BookId b) (max 1 $ c - 1) 1)
      (VerseReferenceT (BookId b) (c + 1) 9999)

    versesWidget
      :: Dynamic t (Maybe (MonoidalMap VerseReference Text))
      -> Dynamic t (MonoidalMap Text (Set (VerseReference, Int, VerseReference, Int)))
      -> m ()
    versesWidget verses' tags' = mdo
      domSegments' <- maybeDyn $ (liftA2 . liftA2) (,) verses' (Just <$> tags')

      dyn_ $ ffor domSegments' $ \case
        Nothing -> text "Loading..."
        Just versesTags -> divClass "passage" $ do
          let
            (verses, tags) = splitDynPure versesTags
            tagRanges = tagsToRanges <$> tags
            wordMap = verseWordMap <$> verses
            domSegments = Map.fromDistinctAscList . map (,()) . unAscending <$> liftA2 mkNonOverlappingDomSegments verses tagRanges
          void $ listWithKey domSegments $ \k _ -> do
            let startingEndpoint = fst (intervalToEndpoints k)
            case startingEndpoint of
              IntervalEndpoint (VerseReferenceT book chapter verse, 0) Closed _
                | chapter == 1 && verse == 1 -> el "br" blank *> text " " *> el "strong" (text $ tshow ((\(BookId n) -> n) book) <> ":1")
                | verse == 1 -> el "br" blank *> text " " *> el "strong" (text $ tshow chapter)
                | otherwise -> el "br" blank *> text " " *> el "sup" (text $ tshow verse)
              _ -> blank
            let
              wordsDyn = T.intercalate " " . map snd . IntervalMap.toAscList . (`IntervalMap.intersecting` k) <$> wordMap
              isHighlighted = not . null . (`IntervalMap.intersecting` k) <$> tagRanges
              styleDyn = ffor isHighlighted $ \hl ->
                "data-start" =: startingEndpoint ^. re wordStartingEndpointEncoding <>
                if hl then "style" =: "background-color:yellow;" else mempty
            text " "
            elDynAttr "span" styleDyn $ dynTextStrict wordsDyn

wordStartingEndpointEncoding :: Prism' Text (IntervalEndpoint (VerseReference, Int))
wordStartingEndpointEncoding = prism'
  (\(IntervalEndpoint (VerseReferenceT book chapter verse, word) t _) ->
    T.intercalate ":" $ map (T.pack . show) [(\(BookId n) -> n) book, chapter, verse, case t of Closed -> word; Open -> word + 1]
  )
  (\txt -> case T.splitOn ":" txt of
    [book', chapter', verse', word']
      | Just book <- read' book'
      , Just chapter <- read' chapter'
      , Just verse <- read' verse'
      , Just word <- read' word'
      -> Just $ IntervalEndpoint (VerseReferenceT (BookId book) chapter verse, word) Closed Starting
      where read' = readMaybe . T.unpack
    _ -> Nothing
  )

-- | A more efficient version of 'dynText' but with the added requirement that the input 'Dynamic' be strict.
-- That is, it must have a value at DOM-building time because it's initial value is immediately sampled.
dynTextStrict :: (DomBuilder t m, MonadSample t m) => Dynamic t Text -> m ()
dynTextStrict d = do
  d0 <- sample (current d)
  void $ textNode $ def & textNodeConfig_initialContents .~ d0 & textNodeConfig_setContents .~ updated d

toggleMaybe :: a -> Maybe a -> Maybe a
toggleMaybe a = \case
  Nothing -> Just a
  Just _ -> Nothing

watchTranslations
  :: (HasApp t m, MonadHold t m, MonadFix m)
  => m (Dynamic t (Maybe (MonoidalMap TranslationId Translation)))
watchTranslations =
  (fmap . fmap) (fmap (fmap getFirst . snd) . getOption . _view_translations) $
    watchViewSelector $ pure $ mempty { _viewSelector_translations = Option $ Just 1 }

watchVerses
  :: (HasApp t m, MonadHold t m, MonadFix m)
  => Dynamic t (TranslationId, Interval VerseReference)
  -> m ( Dynamic t (Maybe (MonoidalMap VerseReference Text))
       , Dynamic t (MonoidalMap Text (Set (VerseReference, Int, VerseReference, Int))))
watchVerses rng = do
  result <- watchViewSelector $ ffor rng $ \(translationId, interval) -> mempty
    { _viewSelector_verseRanges = MMap.singleton translationId $ MMap.singleton interval 1 }
  pure $ splitDynPure $ ffor2 rng result $ \(translationId, _interval) result' -> -- TODO: Filter out verses that fit interval?
    ( (fmap.fmap) (getFirst . snd) $ result' ^? view_verses . ix translationId
    , maybe mempty (fmap MMap.keysSet) $ result' ^? view_tags . ix translationId
    )
