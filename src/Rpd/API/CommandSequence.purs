module Rpd.API.CommandSequence where

import Prelude

import Effect (Effect)
import Data.Array (snoc)
import Data.Either
import Data.Tuple (fst)
import Data.Tuple.Nested ((/\))
import Data.Traversable (traverse_)

import FRP.Event (Event)
import FRP.Event as Event

import Rpd.Network
import Rpd.API (RpdError)
import Rpd.API.Command
import Rpd.API.CommandApply (Step, apply, performEffect)
import Rpd.Path as Path
import Rpd.Toolkit (Toolkit)


data CmdList d c n = CmdList (Array (Command d c n))


infixl 1 andThen as </>


init :: forall d c n. CmdList d c n
init = CmdList []


addPatch :: forall d c n. Path.Alias -> Command d c n
addPatch = Request <<< ToAddPatch


run
    :: forall d c n
     . Toolkit d c n
    -> Network d c n
    -> CmdList d c n
    -> (Either RpdError (Network d c n) -> Effect Unit)
    -> Effect Unit
run toolkit initialNW (CmdList cmdList) sub = do
    { event : commands, push : pushCmd } <- Event.create
    let
        (updates :: Event (Step d c n)) =
            Event.fold
                (\cmd step ->
                    case step of
                        Left err -> Left err
                        Right ( model /\ _ ) -> apply toolkit cmd model)
                commands
                (pure $ initialNW /\ [])
        (models :: Event (Either RpdError (Network d c n)))
            = ((<$>) fst) <$> updates
    stopEffects <- Event.subscribe updates \step ->
        case step of
            Left err -> pure unit
            Right (model /\ effects) ->
                traverse_ (\eff -> performEffect toolkit pushCmd eff model) effects
    stopSubscriptions <- Event.subscribe models sub
    _ <- traverse_ pushCmd cmdList
    --pushCmd Start
    _ <- stopEffects <> stopSubscriptions
    pure unit


andThen :: forall d c n. CmdList d c n -> Command d c n -> CmdList d c n
andThen (CmdList arr) msg = CmdList (arr `snoc` msg)