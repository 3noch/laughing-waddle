{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
module Backend where

import Control.Exception.Safe (finally)
import Obelisk.Backend (Backend (..))
import Obelisk.Route
import Data.Witherable (Filterable)
import qualified Rhyolite.Backend.App as RhyoliteApp
import Reflex.Query.Class (QueryMorphism (..), SelectedCount)
import qualified Snap.Core as Snap

import Backend.NotifyHandler (notifyHandler)
import Backend.RequestHandler (requestHandler)
import Backend.Schema (withDb)
import Backend.Transaction (Transaction, runTransaction)
import Backend.ViewSelectorHandler (viewSelectorHandler)
import Common.Prelude
import Common.Route (BackendRoute (..), FrontendRoute, fullRouteEncoder)
import Unsafe.Coerce (unsafeCoerce)

backend :: Backend BackendRoute FrontendRoute
backend = Backend
  { _backend_run = backendRun
  , _backend_routeEncoder = fullRouteEncoder
  }

backendRun :: (MonadIO m) => ((R BackendRoute -> Snap.Snap ()) -> IO a) -> m a
backendRun serve = withDb $ \dbPool -> do
  let
    runTransaction' :: Transaction a -> IO a
    runTransaction' = runTransaction dbPool
  (handleListen, wsFinalizer) <- RhyoliteApp.serveDbOverWebsockets (unsafeCoerce dbPool {- To avoid importing groundhog -})
    (requestHandler runTransaction')
    (notifyHandler runTransaction')
    (RhyoliteApp.QueryHandler $ viewSelectorHandler runTransaction')
    signumQueryMorphism
    RhyoliteApp.standardPipeline

  flip finally wsFinalizer $ serve $ \case
    BackendRoute_Missing :/ _ -> Snap.writeText "404 Page not found"
    BackendRoute_Listen :/ _ -> handleListen

signumQueryMorphism :: Filterable q => QueryMorphism (q SelectedCount) (q SelectedCount)
signumQueryMorphism = QueryMorphism (mapMaybe $ \n -> if n > 0 then Just (signum n) else Nothing) id
