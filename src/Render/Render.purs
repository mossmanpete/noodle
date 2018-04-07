module Render
    ( UI(..)
    , UIState(..)
    , Event(..), Selection(..), getSelection
    , isPatchSelected, isNodeSelected, isInletSelected, isOutletSelected
    , UIChannel
    , init, update
    ) where

import Prelude

import Data.Map (Map(..))
import Data.Map as Map
import Data.Maybe (Maybe(..), maybe, fromMaybe)
import Rpd as R
import Signal as S
import Signal.Channel as SC


newtype UIState d =
    UIState
        { selection :: Selection
        , dragging :: Maybe R.NodePath
        , connecting :: Maybe R.OutletPath
        , curDataMsg :: Maybe (R.DataMsg d)
        , lastInletData :: Map R.InletPath d
        , lastOutletData :: Map R.OutletPath d
        }


data Event d
    = Start
    | Skip
    | ConnectFrom R.OutletPath
    | ConnectTo R.InletPath
    | Drag Int Int
    | Data (R.DataMsg d)
    | Select Selection


data Selection
    = SNone
    | SNetwork -- a.k.a. None ?
    | SPatch R.PatchId
    | SNode R.NodePath
    | SInlet R.InletPath
    | SOutlet R.OutletPath
    | SLink R.LinkId


data UI d = UI (UIState d) (R.Network d)


type UIChannel d = SC.Channel (Event d)


init :: forall d. UIState d
init =
    UIState
        { selection : SNone
        , dragging : Nothing
        , connecting : Nothing
        , curDataMsg : Nothing
        , lastInletData : Map.empty
        , lastOutletData : Map.empty
        }


update :: forall d e. Event d -> UI d -> UI d
update (Data dataMsg) (UI (UIState state) network) =
    let
        curDataMsg = Just dataMsg
    in
        UI
            (UIState $
                state { curDataMsg = Just dataMsg
                      , lastInletData =
                            case dataMsg of
                                R.FromInlet inletPath d ->
                                    Map.insert inletPath d state.lastInletData
                                _ -> state.lastInletData
                      , lastOutletData =
                            case dataMsg of
                                R.FromOutlet outletPath d ->
                                    Map.insert outletPath d state.lastOutletData
                                _ -> state.lastOutletData
                      })
            network
update (Select selection) ui =
    case select selection $ getSelection ui of
        Just newSelection -> setSelection newSelection ui
        Nothing -> ui
update _ ui = ui


-- updateAndLog :: forall d e. Event d -> UI d -> String /\ UI d


select :: forall d. Selection -> Selection -> Maybe Selection
select newSelection SNone = Just newSelection
select (SPatch newPatch) prevSelection   | isPatchSelected prevSelection newPatch = Just SNone
                                         | otherwise = Just (SPatch newPatch)
select (SNode newNode) prevSelection     | isNodeSelected prevSelection newNode = Just SNone
                                         | otherwise = Just (SNode newNode)
select (SInlet newInlet) prevSelection   | isInletSelected prevSelection newInlet = Just SNone
                                         | otherwise = Just (SInlet newInlet)
select (SOutlet newOutlet) prevSelection | isOutletSelected prevSelection newOutlet = Just SNone
                                         | otherwise = Just (SOutlet newOutlet)
select SNone _ = Just SNone
select _ _ = Nothing


getSelection :: forall d. UI d -> Selection
getSelection (UI (UIState s) _) = s.selection


setSelection :: forall d. Selection -> UI d -> UI d
setSelection newSelection (UI (UIState s) network) =
    UI (UIState $ s { selection = newSelection }) network


isPatchSelected :: Selection -> R.PatchId -> Boolean
isPatchSelected (SPatch selectedPatchId) patchId = selectedPatchId == patchId
isPatchSelected (SNode nodePath) patchId = R.isNodeInPatch nodePath patchId
isPatchSelected (SInlet inletPath) patchId = R.isInletInPatch inletPath patchId
isPatchSelected (SOutlet outletPath) patchId = R.isOutletInPatch outletPath patchId
isPatchSelected _ _ = false


isNodeSelected :: Selection -> R.NodePath -> Boolean
isNodeSelected (SNode selectedNodePath) nodePath = selectedNodePath == nodePath
isNodeSelected (SInlet inletPath) nodePath = R.isInletInNode inletPath nodePath
isNodeSelected (SOutlet outletPath) nodePath = R.isOutletInNode outletPath nodePath
isNodeSelected _ _ = false


isInletSelected :: forall d. Selection -> R.InletPath -> Boolean
isInletSelected (SInlet selectedInletPath) inletPath = selectedInletPath == inletPath
isInletSelected _ _ = false


isOutletSelected :: forall d. Selection -> R.OutletPath -> Boolean
isOutletSelected (SOutlet selectedOutletPath) outletPath = selectedOutletPath == outletPath
isOutletSelected _ _ = false


instance showSelection :: Show Selection where
    show SNone = "Nothing selected"
    show SNetwork = "Network selected"
    show (SPatch patchId) = show patchId <> " selected"
    show (SNode nodePath) = show nodePath <> " selected"
    show (SInlet inletPath) = show inletPath <> " selected"
    show (SOutlet outletPath) = show outletPath <> " selected"
    show (SLink linkId) = show linkId <> " selected"


instance showUIState :: (Show d) => Show (UIState d) where
    show (UIState { selection, dragging, connecting })
        = "Selection: " <> show selection <>
        ", Dragging: " <> show dragging <>
        ", Connecting " <> show connecting


instance showUI :: (Show d) => Show (UI d) where
    show (UI state _ ) = show state


instance showEvent :: (Show d) => Show (Event d) where
    show Start = "Start"
    show Skip = "Skip"
    show (ConnectFrom outletPath) = "Start connecting from " <> show outletPath
    show (ConnectTo inletPath) = "Finish connecting at " <> show inletPath
    -- | Drag Int Int
    -- | Data (R.DataMsg d)
    show (Select selection) = "Select " <> show selection
    show _ = ""
