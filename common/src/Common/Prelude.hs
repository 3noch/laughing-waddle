module Common.Prelude (module X) where

import Control.Lens as X (ifor, ifor_, itraverse, itraverse_, preview, set, view, (<&>), (^.), (.~))
import Control.Monad as X ((<=<), (>=>))
import Control.Monad.IO.Class as X (MonadIO (liftIO))
import Data.Aeson as X (FromJSON, ToJSON)
import Data.Bifunctor as X (first, second)
import Data.Coerce as X (Coercible, coerce)
import Data.Foldable as X (fold, for_)
import Data.Function as X ((&))
import Data.Functor as X (void, ($>))
import Data.Functor.Identity as X (Identity (..))
import Data.Functor.Compose as X (Compose (..))
import Data.Maybe as X (fromMaybe)
import Data.Map as X (Map)
import Data.Map.Monoidal as X (MonoidalMap)
import Data.Semigroup as X (Option (..))
import Data.Set as X (Set)
import Data.Text as X (Text)
import Data.Traversable as X (for)
import Data.Witherable as X (Filterable (mapMaybe))
import GHC.Generics as X (Generic)
