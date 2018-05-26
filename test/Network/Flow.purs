module RpdTest.Network.Flow
    ( spec ) where

import Prelude

import Test.Spec (Spec, describe, it)
import Test.Util (TestAffE, runWith)

import Control.Monad.Eff (Eff, foreachE)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (newRef, readRef, writeRef)
import Control.Monad.Eff.Console (log)

import Rpd as R
import Rpd.Flow (flow, subscribeAll, Subscribers) as R

import Data.Map as Map
import Data.Maybe (fromMaybe)
import Data.Tuple.Nested ((/\))
import Data.Array (fromFoldable)

import FRP (FRP)
import FRP.Event as Event
import FRP.Event.Time (interval)

data MyData
  = Bang
  | Str' String String
  | Num' String Int

node :: String -> R.LazyNode MyData
node nodeId =
  R.node "f"
    [ R.inlet "a" -- WithDefault "a" (Str' (nodeId <> "a") "i")
    , R.inletWithDefault "b" $ Str' (nodeId <> "b") "test"
    , R.inlet' "f" $ R.flow $ map (Num' (nodeId <> "f")) $ interval 5000
    , R.inlet "d" -- (ST.every ST.second S.~> Num' (nodeId <> "d"))
    , R.inlet "e" -- WithDefault "e" (Num' (nodeId <> "e") 3.0)
    ]
    [ R.outlet "c"
    , R.outlet' "x" $ R.flow
        $ map (Num' (nodeId <> "x"))
        $ Event.fold (\_ n -> n + 1) (interval 5000) 0
    , R.outlet' "y" $ R.flow
        $ map (Num' (nodeId <> "y"))
        $ Event.fold (\_ n -> n + 1) (interval 2000) 0
    ]
    -- (\_ -> [ "c" /\ Int' 10 ] )

network :: R.Network MyData
network =
  R.network
    [ R.patch "Patch One"
      [ node "1"
      , R.processWith processF $ node "2"
      ] -- >>> connect (patch.getNode 0) "a" (patch.getNode 1) "b"
    ]
  where
    processF inputs | Map.isEmpty inputs = Map.empty
    processF inputs | Map.member "d" inputs =
      Map.singleton "c" $ fromMaybe Bang $ Map.lookup "d" inputs
    processF inputs = Map.empty

spec :: forall e. Spec (TestAffE e) Unit
spec = do
  describe "subscribing to the data flow" do
      it "receives the data from events" do
        -- TODO: move tests for a network in the module with this network, export as a suite
        runWith network
          \nw ->
            do
              collectedData <- liftEff $ do
                collectedData <- newRef []
                let
                  onInletData path source d = do
                    log $ show path -- <> show d
                    pure unit
                  onOutletData path d = do
                    log $ show path -- <> show d
                    pure unit
                  subscribers = R.subscribeAll onInletData onOutletData nw
                _ <- performSubs subscribers
                readRef collectedData
              -- collectedData `shouldEqual` []
              pure unit
  describe "connecting channels after creation" do
    pure unit
  describe "disconnecting channels after creation" do
    pure unit
  describe "manually sending data to the channels after creation" do
    pure unit
  describe "manually sending delayed data to the channels after creation" do
    --   delay (Milliseconds 100.0)
    pure unit
  describe "adding nodes after creation" do
    pure unit
  describe "deleting nodes after creation" do
    pure unit


performSubs :: forall e. R.Subscribers e -> Eff (frp :: FRP | e) Unit
performSubs ( outletSubscribers /\ inletSubscribers ) =
  foreachE (fromFoldable $ Map.values outletSubscribers) $
    \sub -> do
      _ <- sub
      pure unit
