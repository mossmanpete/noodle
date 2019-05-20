module Rpd.Network
    ( Network(..)
    , Patch(..)
    , Node(..)
    , Inlet(..)
    , Outlet(..)
    , Link(..)
    , Entity(..)
    , InletFlow(..), OutletFlow(..)
    , InletsFlow(..), OutletsFlow(..)
    , PushToInlet(..), PushToOutlet(..)
    , PushToInlets(..), PushToOutlets(..)
    -- FIXME: do not expose constructors, provide all the optics as getters
    , empty
    ) where


import Prelude (class Eq, (==), (&&), class Show, show, (<>))

import Data.Maybe (Maybe(..))
import Data.List as List
import Data.List (List)
import Data.Map as Map
import Data.Set (Set)
import Data.Set (empty) as Set
import Data.Tuple.Nested ((/\), type (/\))

import Rpd.Channel (class Channel)
import Rpd.Channel as Channel
import Rpd.Path
import Rpd.UUID (UUID)
import Rpd.Util (type (/->), Canceler, Flow, PushableFlow, PushF)
import Rpd.Process (ProcessF(..))


-- FIXME: UUID is internal and so should not be passed, I suppose.
--        I'll leave it here temporarily just for the debug purpose.
data InletFlow d = InletFlow (Flow d)
data InletsFlow d = InletsFlow (Flow (Path /\ UUID /\ d))
data PushToInlet d = PushToInlet (PushF d)
data PushToInlets d = PushToInlets (PushF (Path /\ UUID /\ d))
data OutletFlow d = OutletFlow (Flow d)
data OutletsFlow d = OutletsFlow (Flow (Path /\ UUID /\ d))
        -- FIXME: Flow (Maybe OutletInNode /\ d)
data PushToOutlet d = PushToOutlet (PushF d)
data PushToOutlets d = PushToOutlets (PushF (Path /\ UUID /\ d))
        -- FIXME: PushF (Maybe OutletInNode /\ d)


data Entity d
    = PatchEntity (Patch d)
    | NodeEntity (Node d)
    | InletEntity (Inlet d)
    | OutletEntity (Outlet d)
    | LinkEntity Link


data Network d =
    Network
        { name :: String
        , patches :: Set UUID
        , registry :: UUID /-> Entity d
        -- , pathToId :: Path /-> Set UUID
        , pathToId :: Path /-> UUID
        , cancelers :: UUID /-> Array Canceler
            -- { nodes :: UUID.ToNode /-> Array Canceler
            -- , inlets :: UUID.ToInlet /-> Array Canceler
            -- , outlets :: UUID.ToOutlet /-> Array Canceler
            -- , links :: UUID.ToLink /-> Array Canceler
            -- }
        }
data Patch d =
    Patch
        UUID
        Path
        (Set UUID) -- nodes
data Node d =
    Node
        UUID
        Path
        (ProcessF d)
        { inlets :: Set UUID
        , outlets :: Set UUID
        , inletsFlow :: InletsFlow d
        , outletsFlow :: OutletsFlow d
        , pushToInlets :: PushToInlets d
        , pushToOutlets :: PushToOutlets d
        }
data Inlet d =
    Inlet
        UUID
        Path
        -- (forall c. Channel c d => c)
        { flow :: InletFlow d
        , push :: PushToInlet d
        }
data Outlet d =
    Outlet
        UUID
        Path
        -- (forall c. Channel c d => c)
        { flow :: OutletFlow d
        , push :: PushToOutlet d
        }
data Link =
    Link
        UUID
        { outlet :: UUID
        , inlet :: UUID
        }


empty :: forall d. Network d
empty  =
    Network
        { name : "My Network"
        , patches : Set.empty
        , registry : Map.empty
        , pathToId : Map.empty
        , cancelers : Map.empty
            -- { nodes : Map.empty
            -- , inlets : Map.empty
            -- , outlets : Map.empty
            -- , links : Map.empty
            -- }
        }


instance eqPatch :: Eq (Patch d) where
    eq (Patch pidA _ _) (Patch pidB _ _) = (pidA == pidB)

instance eqNode :: Eq (Node d) where
    eq (Node nidA _ _ _) (Node nidB _ _ _) = (nidA == nidB)

instance eqInlet :: Eq (Inlet d) where
    eq (Inlet iidA _ _) (Inlet iidB _ _) = (iidA == iidB)

instance eqOutlet :: Eq (Outlet d) where
    eq (Outlet oidA _ _) (Outlet oidB _ _) = (oidA == oidB)

instance eqLink :: Eq Link where
    eq (Link lidA _) (Link lidB _) = (lidA == lidB)

instance showLink :: Show Link where
    show (Link outletPath inletPath) = "Link " <> show outletPath <> " -> " <> show inletPath
