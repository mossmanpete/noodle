module Rpd.Render.Terminal
    ( TerminalRenderer
    , terminalRenderer
    , Ui
    , view -- TODO: do not expose maybe?
    ) where

import Prelude

import Data.Map as Map
import Data.List as List
import Data.Set as Set
import Data.Tuple.Nested (type (/\), (/\))
import Data.Either (Either(..))
import Data.String (joinWith)

import Rpd.Network (Network(..), Patch(..)) as R
import Rpd.API (RpdError) as R
import Rpd.Render (PushMsg, Message) as R
import Rpd.RenderS (Renderer(..))


type Ui = {}

type TerminalRenderer d = Renderer d Ui String


terminalRenderer :: forall d. TerminalRenderer d
terminalRenderer =
    Renderer
        { from : ""
        , init : {}
        , update : update
        , view : view
        }

update :: forall d. R.Message d -> Ui -> R.Network d -> Ui
update msg ui nw = ui


view :: forall d. R.PushMsg d -> Either R.RpdError (Ui /\ R.Network d) -> String
view pushMsg (Right (ui /\ R.Network _ { patches })) =
    "SUCC" <> patchesInfo
    where
        patchesInfo = joinWith "," $ (getNodesCount <$> Map.values patches) # List.toUnfoldable
        getNodesCount (R.Patch _ _ { nodes }) =
            show $ Set.size nodes
view pushMsg (Left err) =
    "ERR: " <> show err
