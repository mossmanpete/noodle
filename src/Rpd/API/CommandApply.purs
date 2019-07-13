module Rpd.API.CommandApply where

import Prelude
import Effect (Effect)

import Data.Maybe
import Data.Either
import Data.Tuple.Nested ((/\), type (/\))
import Data.Sequence (empty) as Seq
import Data.Lens (view, setJust)
import Data.Array ((:))

import FRP.Event as E

import Rpd.Util (PushableFlow(..), Canceler)
import Rpd.API
import Rpd.API.Command
    ( Command(..)
    , InnerCommand(..)
    , RequestCommand(..)
    , BuildCommand(..)
    , DataCommand(..)
    , RpdEffect(..)
    )
import Rpd.Network
import Rpd.Process
import Rpd.Optics
import Rpd.Path as Path
import Rpd.Toolkit
import Rpd.UUID as UUID


type Step d c n = Either RpdError (Network d c n /\ Array (RpdEffect d c n))


apply
    :: forall d c n
     . Toolkit d c n
    -> Command d c n
    -> Network d c n
    -> Step d c n
apply _ NoOp nw =
    pure $ nw /\ []
apply toolkit (Inner innerCmd) nw = applyInnerCommand toolkit innerCmd nw
apply toolkit (Request requestCmd) nw = applyRequestCommand toolkit requestCmd nw
apply toolkit (Build buildCmd) nw = applyBuildCommand toolkit buildCmd nw
apply toolkit (Data dataCmd) nw = applyDataCommand toolkit dataCmd nw


applyDataCommand
    :: forall d c n
     . Toolkit d c n
    -> DataCommand d c
    -> Network d c n
    -> Step d c n
applyDataCommand _ Bang nw =
    pure $ nw /\ []
applyDataCommand _ (GotInletData _ _) nw =
    pure $ nw /\ []
applyDataCommand _ (GotOutletData _ _) nw =
    pure $ nw /\ []
applyDataCommand _ (SendToInlet _ _) nw =
    pure $ nw /\ []
applyDataCommand _ (SendToOutlet _ _) nw =
    pure $ nw /\ []


applyRequestCommand
    :: forall d c n
     . Toolkit d c n
    -> RequestCommand d c n
    -> Network d c n
    -> Step d c n
applyRequestCommand _ (ToAddPatch alias) nw =
    pure $ nw /\ [ AddPatchE alias ]
applyRequestCommand _ (ToAddNode patchPath alias n) nw =
    pure $ nw /\ [ AddNodeE patchPath alias n ]
applyRequestCommand _ (ToAddInlet nodePath alias c) nw =
    pure $ nw /\ [ AddInletE nodePath alias c ]
applyRequestCommand _ (ToAddOutlet nodePath alias c) nw =
    pure $ nw /\ [ AddOutletE nodePath alias c ]
applyRequestCommand _ (ToConnect outletPath inletPath) nw = do
    outletUuid <- uuidByPath UUID.toOutlet outletPath nw
    outlet <- view (_outlet outletUuid) nw # note (RpdError "")
    inletUuid <- uuidByPath UUID.toInlet inletPath nw
    inlet <- view (_inlet inletUuid) nw # note (RpdError "")
    pure $ nw /\ [ AddLinkE outlet inlet ]


applyBuildCommand
    :: forall d c n
     . Toolkit d c n
    -> BuildCommand d c n
    -> Network d c n
    -> Step d c n
applyBuildCommand _ (AddPatch p) nw = do
    pure $ addPatch p nw /\ [ ]
applyBuildCommand _ (AddNode node) nw = do
    nw' <- addNode node nw
    pure $ nw' /\ [ ]
applyBuildCommand _ (ProcessWith node@(Node uuid _ _ _ _) processF) nw = do
    let newNode = processWith processF node
        nw' = nw # setJust (_node uuid) newNode
    pure $ nw' /\ [ SubscribeNodeProcess newNode ]
applyBuildCommand _ (AddOutlet outlet@(Outlet uuid path _ _)) nw = do
    nodePath <- (Path.getNodePath $ Path.lift path) # note (RpdError "")
    nodeUuid <- uuidByPath UUID.toNode nodePath nw
    node <- view (_node nodeUuid) nw # note (RpdError "")
    nw' <- addOutlet outlet nw
    pure $ nw' /\
        [ CancelNodeSubscriptions node
        , SubscribeNodeProcess node
        , InformNodeOnOutletUpdates outlet node
        , SubscribeNodeUpdates node
        ]
applyBuildCommand _ (AddInlet inlet@(Inlet uuid path _ _)) nw = do
    nodePath <- (Path.getNodePath $ Path.lift path) # note (RpdError "")
    nodeUuid <- uuidByPath UUID.toNode nodePath nw
    node <- view (_node nodeUuid) nw # note (RpdError "")
    nw' <- addInlet inlet nw
    pure $ nw' /\
        [ CancelNodeSubscriptions node
        , SubscribeNodeProcess node
        , InformNodeOnInletUpdates inlet node
        , SubscribeNodeUpdates node
        ]
applyBuildCommand _ (AddLink link) nw = do
    nw' <- addLink link nw
    pure $ nw' /\ []


applyInnerCommand
    :: forall d c n
     . Toolkit d c n
    -> InnerCommand d c n
    -> Network d c n
    -> Step d c n
applyInnerCommand _ (StoreNodeCanceler (Node uuid _ _ _ _) canceler) nw =
    let
        curNodeCancelers = getNodeCancelers uuid nw
        newNodeCancelers = canceler : curNodeCancelers
    in
        pure $ storeNodeCancelers uuid newNodeCancelers nw /\ []
applyInnerCommand _ (ClearNodeCancelers (Node uuid _ _ _ _)) nw =
    pure $ clearNodeCancelers uuid nw /\ []
applyInnerCommand _ (StoreOutletCanceler (Outlet uuid _ _ _) canceler) nw =
    let
        curOutletCancelers = getOutletCancelers uuid nw
        newOutletCancelers = canceler : curOutletCancelers
    in
        pure $ storeOutletCancelers uuid newOutletCancelers nw /\ []
applyInnerCommand _ (StoreInletCanceler (Inlet uuid _ _ _) canceler) nw =
    let
        curInletCancelers = getInletCancelers uuid nw
        newInletCancelers = canceler : curInletCancelers
    in
        pure $ storeInletCancelers uuid newInletCancelers nw /\ []
applyInnerCommand _ (StoreLinkCanceler (Link uuid _) canceler) nw =
    let
        curLinkCancelers = getLinkCancelers uuid nw
        newLinkCancelers = canceler : curLinkCancelers
    in
        pure $ storeLinkCancelers uuid newLinkCancelers nw /\ []


performEffect
    :: forall d c n
     . Toolkit d c n
    -> (Command d c n -> Effect Unit)
    -> RpdEffect d c n
    -> Network d c n
    -> Effect Unit
performEffect _ pushСmd (AddPatchE alias) _ = do
    uuid <- UUID.new
    let path = Path.toPatch alias
    pushСmd $ Build $ AddPatch $
        Patch
            (UUID.ToPatch uuid)
            path
            { nodes : Seq.empty
            , links : Seq.empty
            }
performEffect _ pushСmd (AddNodeE patchPath nodeAlias n) _ = do
    uuid <- UUID.new
    flows <- makeInletOutletsFlows
    let
        path = Path.nodeInPatch patchPath nodeAlias
        PushableFlow pushToInlets inletsFlow = flows.inlets
        PushableFlow pushToOutlets outletsFlow = flows.outlets
        newNode =
            Node
                (UUID.ToNode uuid)
                path
                n
                Withhold
                { inlets : Seq.empty
                , outlets : Seq.empty
                , inletsFlow : InletsFlow inletsFlow
                , outletsFlow : OutletsFlow outletsFlow
                , pushToInlets : PushToInlets pushToInlets
                , pushToOutlets : PushToOutlets pushToOutlets
                }
    pushСmd $ Build $ AddNode newNode
performEffect _ pushСmd (AddLinkE outlet inlet) nw = do
    uuid <- UUID.new
    let
        (Outlet ouuid _ _ { flow : outletFlow' }) = outlet
        (Inlet iuuid _ _ { push : pushToInlet' }) = inlet
        (OutletFlow outletFlow) = outletFlow'
        (PushToInlet pushToInlet) = pushToInlet'
        newLink = Link (UUID.ToLink uuid) { outlet : ouuid, inlet : iuuid }
    canceler :: Canceler <- E.subscribe outletFlow pushToInlet
    pushСmd $ Build $ AddLink newLink
    pushСmd $ Inner $ StoreLinkCanceler newLink canceler
performEffect _ pushСmd (SubscribeNodeProcess node) nw = do
    canceler <- setupNodeProcessFlow node nw
    pushСmd $ Inner $ StoreNodeCanceler node canceler
performEffect _ pushСmd (CancelNodeSubscriptions node@(Node uuid _ _ _ _)) nw = do
    _ <- cancelNodeSubscriptions uuid nw
    pushСmd $ Inner $ ClearNodeCancelers node
performEffect _ pushСmd (AddInletE nodePath inletAlias c) _ = do
    uuid <- UUID.new
    flow <- makePushableFlow
    let
        path = Path.inletInNode nodePath inletAlias
        PushableFlow pushToInlet inletFlow = flow
        newInlet =
            Inlet
                (UUID.ToInlet uuid)
                path
                c
                { flow : InletFlow inletFlow
                , push : PushToInlet pushToInlet
                }
    pushСmd $ Build $ AddInlet newInlet
    -- FIXME: pushСmd $ CancelNodeSubscriptions
performEffect _ pushСmd (InformNodeOnInletUpdates inlet node) _ = do
    canceler <- informNodeOnInletUpdates inlet node
    pushСmd $ Inner $ StoreInletCanceler inlet canceler
performEffect _ pushСmd (AddOutletE nodePath outletAlias c) _ = do
    uuid <- UUID.new
    flow <- makePushableFlow
    let
        path = Path.outletInNode nodePath outletAlias
        PushableFlow pushToOutlet outletFlow = flow
        newOutlet =
            Outlet
                (UUID.ToOutlet uuid)
                path
                c
                { flow : OutletFlow outletFlow
                , push : PushToOutlet pushToOutlet
                }
    pushСmd $ Build $ AddOutlet newOutlet
    -- FIXME: pushСmd $ CancelNodeSubscriptions
performEffect _ pushСmd (InformNodeOnOutletUpdates outlet node) _ = do
    canceler <- informNodeOnOutletUpdates outlet node
    pushСmd $ Inner $ StoreOutletCanceler outlet canceler
performEffect _ pushСmd (SubscribeNodeUpdates node) _ = do
    canceler <- subscribeNode node (const $ pure unit) (const $ pure unit)
    pushСmd $ Inner $ StoreNodeCanceler node canceler


-- apply'
--     :: forall d c n
--      . Command d c n
--     -> (Command d c n -> Effect Unit)
--     -> Toolkit d c n
--     -> R.Network d c n
--     -> R.Rpd (R.Network d c n)
-- apply' Bang pushCmd _ nw =
--     Rpd.subscribeAllInlets onInletData nw
--         </> Rpd.subscribeAllOutlets onOutletData
--     where
--         onInletData inletPath d =
--             pushCmd $ GotInletData inletPath d
--         onOutletData outletPath d =
--             pushCmd $ GotOutletData outletPath d
-- apply' (AddPatch alias) pushCmd _ nw =
--     R.addPatch alias nw
--         -- FIXME: subscribe the nodes in the patch
-- apply' (AddNode patchPath alias n) pushCmd _ nw =
--     Rpd.addNode patchPath alias n nw
--         -- FIXME: `onInletData`/`onOutletData` do not receive the proper state
--         --        of the network this way (do they need it?), but they should
--         --        (pass the current network state in the Process function?)
--         </> Rpd.subscribeNode nodePath
--                 (onNodeInletData nodePath)
--                 (onNodeOutletData nodePath)
--     where
--         nodePath = P.nodeInPatch patchPath alias
--         (patchAlias /\ nodeAlias) = P.explodeNodePath nodePath
--         -- addModel = pure <<< ((/\) model)
--         onNodeInletData nodePath (inletAlias /\ _ /\ d) =
--             pushCmd $ GotInletData (P.toInlet patchAlias nodeAlias inletAlias) d
--         onNodeOutletData nodePath (outletAlias /\ _ /\ d) =
--             pushCmd $ GotOutletData (P.toOutlet patchAlias nodeAlias outletAlias) d
-- apply' (AddInlet nodePath alias c) pushCmd _ nw =
--     let
--         inletPath = P.inletInNode nodePath alias
--         onInletData d =
--             pushCmd $ GotInletData inletPath d
--     in
--         Rpd.addInlet nodePath alias c nw
--             </> Rpd.subscribeInlet inletPath (R.InletHandler onInletData)
-- apply' (AddOutlet nodePath alias c) pushCmd _ nw =
--     let
--         outletPath = P.outletInNode nodePath alias
--         onOutletData d =
--             pushCmd $ GotOutletData outletPath d
--     in
--         Rpd.addOutlet nodePath alias c nw
--             </> Rpd.subscribeOutlet outletPath (R.OutletHandler onOutletData)
-- apply' (Connect { inlet : inletPath, outlet : outletPath }) _ _ nw =
--     Rpd.connect outletPath inletPath nw
-- apply' (Disconnect { inlet : inletPath, outlet : outletPath }) _ _ nw =
--     Rpd.disconnectTop outletPath inletPath nw
-- apply' _ _ _ nw = pure nw
