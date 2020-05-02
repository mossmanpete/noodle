module Noodle.Test.Spec.Flow.Network
    ( spec
    ) where

import Prelude

import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))

import Effect.Class (liftEffect)

import Test.Spec (Spec, it, pending)
import Test.Spec.Assertions (shouldEqual)

import Noodle.Network as Network
import Noodle.API.Action.Sequence as Actions

import Noodle.Test.Util.Trace (channelsAfter)
import Noodle.Test.Spec.Flow.Base (mySequencer)


{- ======================================= -}
{- =============== NETWORK =============== -}
{- ======================================= -}


spec :: Spec Unit
spec = do
  it "we receive no data from the network when it's empty" $ do
    _ /\ collectedData <-
      channelsAfter
          (Milliseconds 100.0)
          mySequencer
          (Network.empty "no-data")
          Actions.init

    collectedData `shouldEqual` []

  pending "all the cancelers are called after running the system"

