
module Rpd.API
    ( Rpd, RpdError, init
    , (</>), rpdBind
    --, RpdOp, RpdEffOp
        --, emptyNetwork
    --, network, patch, node, inlet, inlet', inletWithDefault, inletWithDefault', outlet, outlet'
    , connect, disconnectAll --, disconnectTop
    , addPatch, addPatch', addNode, addNode', addInlet, addInlet', addOutlet, addOutlet'
    , subscribeInlet, subscribeOutlet, subscribeAllInlets, subscribeAllOutlets
    , subscribeChannelsData, subscribeNode  -- subscribeAllData
    , subscribeInlet', subscribeOutlet', subscribeAllInlets', subscribeAllOutlets'
    , subscribeChannelsData', subscribeNode'  -- subscribeAllData'
    , sendToInlet, streamToInlet, sendToOutlet, streamToOutlet
    --, findPatch, findNode, findOutlet, findInlet
    ) where

import Prelude

import Data.Array ((!!), (:), snoc)
import Data.Array as Array
import Data.Bitraversable (bisequence)
import Data.Either (Either, note)
import Data.Foldable (foldr)
import Data.Lens (view, set, setJust)
import Data.Lens.At (at)
import Data.List (List)
import Data.List as List
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe, isJust)
import Data.Set (Set)
import Data.Set as Set
import Data.Traversable (for, sequence, traverse, traverse_)
import Data.TraversableWithIndex (forWithIndex)
import Data.Tuple (uncurry, fst)
import Data.Tuple.Nested ((/\), type (/\))

import Debug.Trace

import Control.MonadZero (empty)
import Control.Monad.Except.Trans (ExceptT, except)

import Effect (Effect, foreachE)
import Effect.Class (liftEffect)

import FRP.Event as E


import Rpd.Path
import Rpd.Def
import Rpd.Optics
import Rpd.Process
import Rpd.Network
import Rpd.Network (empty) as Network
import Rpd.Util (type (/->), PushableFlow(..), Subscriber, Canceler, Flow, never)
import Rpd.Util as RU

infixl 6 snoc as +>

--import Rpd.Flow as Flow

-- data RunningNetwork d e = RpdEff e (Network d e)

data RpdError = RpdError String


type RpdOp a = Either RpdError a
-- TODO: MonadEffect + MonadThrow
--       https://www.fpcomplete.com/blog/2016/11/exceptions-best-practices-haskell
type Rpd a = ExceptT RpdError Effect a
-- type Rpd d e = ContT (Either RpdError (Network d e)) (Eff (RpdEffE e)) (Network d e)
-- newtype ContT r m a = ContT ((a -> m r) -> m r)


infixl 1 rpdBind as </>
-- other options: └, ~>, ...


rpdBind :: forall a b. Rpd a -> (a -> Rpd b) -> Rpd b
rpdBind = (>>=)


someApiFunc :: forall d. Rpd (Network d)
someApiFunc =
    init "t"
        </> addPatch "foo"
        </> addNode (PatchId 0) "test1"
        </> addNode (PatchId 0) "test2"


-- instance functorRpdOp :: Functor (RpdOp d) where
-- instance applyRpdOp :: Apply (RpdOp d) where
-- instance applicativeRpdOp :: Applicative (RpdOp d) where

-- instance functorRpdEffOp :: Functor (RpdEffOp d) where
-- instance applyRpdEffOp :: Apply (RpdEffOp d) where
-- instance applicativeRpdEffOp :: Applicative (RpdEffOp d) where


init :: forall d. String -> Rpd (Network d)
init = pure <<< Network.empty


makePushableFlow :: forall d. Effect (PushableFlow d)
makePushableFlow = do
    { push, event } <- E.create
    pure $ PushableFlow push event


nextPatchId :: forall d. Network d -> PatchId
nextPatchId (Network _ { patches }) =
    PatchId (Map.size patches)


nextNodePath :: forall d. PatchId -> Network d -> Either RpdError NodePath
nextNodePath patchId (Network _ { patches }) = do
    (Patch _ _ { nodes }) <- Map.lookup patchId patches
                                # note (RpdError "")
    pure $ NodePath patchId $ Set.size nodes


nextInletPath :: forall d. NodePath -> Network d -> Either RpdError InletPath
nextInletPath nodePath (Network _ { nodes }) = do
    (Node _ _ { inlets }) <- Map.lookup nodePath nodes
                                # note (RpdError "")
    pure $ InletPath nodePath $ Set.size inlets


nextOutletPath :: forall d. NodePath -> Network d -> Either RpdError OutletPath
nextOutletPath nodePath (Network _ { nodes }) = do
    (Node _ _ { outlets }) <- Map.lookup nodePath nodes
                                # note (RpdError "")
    pure $ OutletPath nodePath $ Set.size outlets


nextLinkId :: forall d. Network d -> LinkId
nextLinkId (Network _ { links }) =
    LinkId (Map.size links)



exceptMaybe :: forall a. RpdError -> Maybe a -> ExceptT RpdError Effect a
exceptMaybe err maybe =
    except (maybe # note err)


addPatch :: forall d. String -> Network d -> Rpd (Network d)
addPatch name =
    addPatch'
        { name
        , nodeDefs : List.Nil
        }


addPatch'
    :: forall d
     . PatchDef d
    -> Network d
    -> Rpd (Network d)
addPatch' patchDef nw =
    pure $ setJust (_patch patchId) newPatch nw
    where
        patchId = nextPatchId nw
        newPatch =
            Patch
                patchId
                patchDef
                { nodes : Set.empty
                }

-- TODO: removePatch
    -- TODO: cancel all the cancelers related to the patch

addNode
    :: forall d
     . PatchId
    -> String
    -> Network d
    -> Rpd (Network d)
addNode patchId name =
    addNode'
        patchId
        { name
        , inletDefs : List.Nil
        , outletDefs : List.Nil
        , process : Withhold
        }


addNode'
    :: forall d
     . PatchId
    -> NodeDef d
    -> Network d
    -> Rpd (Network d)
addNode' patchId def nw = do
    nodePath <- except $ nextNodePath patchId nw
    processPFlow <- liftEffect makePushableFlow
    let
        newNode =
            Node
                nodePath
                def
                { inlets : Set.empty
                , outlets : Set.empty
                , flow : ProcessPFlow processPFlow
                }
    nw
         #  setJust (_node nodePath) newNode
         #  setJust (_patchNode patchId nodePath) unit
         #  addInlets nodePath def.inletDefs
        </> addOutlets nodePath def.outletDefs
        </> updateNodeProcessFlow nodePath


processWith
    :: forall d
     . NodePath
    -> ProcessF d
    -> Network d
    -> Rpd (Network d)
processWith nodePath processF nw = do
    (Node _ def state) :: Node d <-
        view (_node nodePath) nw
            # exceptMaybe (RpdError "")
    let
        newNode =
            Node
                nodePath
                (def { process = processF })
                state
    nw
        # setJust (_node nodePath) newNode
        # updateNodeProcessFlow nodePath


addInlet
    :: forall d
     . NodePath
    -> String
    -> Network d
    -> Rpd (Network d)
addInlet nodePath label =
    addInlet'
        nodePath
        { label
        , default : Nothing
        , accept : Nothing
        }


addInlet'
    :: forall d
     . NodePath
    -> InletDef d
    -> Network d
    -> Rpd (Network d)
addInlet' nodePath def nw = do
    inletPath <- except $ nextInletPath nodePath nw
    -- TODO: when there's already some inlet exists with the same path,
    -- cancel its subscription before
    pushableFlow@(PushableFlow pushData dataFlow) <- liftEffect makePushableFlow
    (Node _ _ { flow }) :: Node d
        <- view (_node nodePath) nw # exceptMaybe (RpdError "")
    let
        inletId = getInletId inletPath
        (ProcessPFlow (PushableFlow informNode _ )) = flow
        newInlet =
            Inlet
                inletPath
                def
                { flow : InletPFlow pushableFlow
                }
    canceler :: Canceler <-
        liftEffect $
            E.subscribe dataFlow (\d -> informNode (inletId /\ d))
    -- userCancelers :: Array Canceler <-
    --     liftEffect $ traverse (E.subscribe dataFlow) subs
    nw # setJust (_inlet inletPath) newInlet
       # setJust (_nodeInlet nodePath inletPath) unit
       # setJust (_inletCancelers inletPath) [ canceler ]
       # updateNodeProcessFlow nodePath


addInlets :: forall d. NodePath -> List (InletDef d) -> Network d -> Rpd (Network d)
addInlets nodePath inletDefs nw =
    -- FIXME: may appear not very optimal, since every `addInlet'`
    --        call looks for the node again and again
    foldr foldingF (pure nw) inletDefs
    where
        foldingF inletDef rpd =
            rpd </> addInlet' nodePath inletDef


-- TODO: removeInlet
    -- TODO: execute the corresponding process canceler
    -- TODO: cancel all the links going into this inlet
    -- TODO: updateNodeProcessFlow


addOutlet
    :: forall d
     . NodePath
    -> String
    -> Network d
    -> Rpd (Network d)
addOutlet nodePath label =
    addOutlet'
        nodePath
        { label
        , accept : empty
        }


addOutlet'
    :: forall d
     . NodePath
    -> OutletDef d
    -> Network d
    -> Rpd (Network d)
addOutlet' nodePath def nw = do
    outletPath <- except $ nextOutletPath nodePath nw
    pushableFlow <- liftEffect makePushableFlow
    let
        newOutlet =
            Outlet
                outletPath
                def
                { flow : OutletPFlow pushableFlow
                }
        outletId = getOutletId outletPath
    nw # setJust (_outlet outletPath) newOutlet
       # setJust (_nodeOutlet nodePath outletPath) unit
       # updateNodeProcessFlow nodePath


addOutlets :: forall d. NodePath -> List (OutletDef d) -> Network d -> Rpd (Network d)
addOutlets nodePath outletDefs nw =
    -- FIXME: may appear not very optimal, since every `addOutlet'`
    --        call looks for the node again and again
    foldr foldingF (pure nw) outletDefs
    where
        foldingF outletDef rpd =
            rpd </> addOutlet' nodePath outletDef


-- TODO: removeOutlet
    -- TODO: cancel all the links going from this outlet
    -- TODO: updateNodeProcessFlow


sendToInlet
    :: forall d
     . InletPath
    -> d
    -> Network d
    -> Rpd (Network d)
sendToInlet inletPath d nw = do
    (PushableFlow push _) <-
        view (_inletPFlow inletPath) nw # exceptMaybe (RpdError "")
    _ <- liftEffect $ push d
    pure nw


streamToInlet
    :: forall d
     . InletPath
    -> Flow d
    -> Network d
    -> Rpd Canceler
streamToInlet inletPath flow nw = do
    (PushableFlow push _) <-
        view (_inletPFlow inletPath) nw
            # exceptMaybe (RpdError "")
    canceler :: Canceler <-
        liftEffect $ E.subscribe flow push
    pure canceler


sendToOutlet
    :: forall d
     . OutletPath
    -> d
    -> Network d
    -> Rpd (Network d)
sendToOutlet outletPath d nw = do
    (PushableFlow push _) <-
        view (_outletPFlow outletPath) nw # exceptMaybe (RpdError "")
    _ <- liftEffect $ push d
    pure nw


streamToOutlet
    :: forall d
     . OutletPath
    -> Flow d
    -> Network d
    -> Rpd Canceler
streamToOutlet outletPath flow nw = do
    (PushableFlow push _) <-
        view (_outletPFlow outletPath) nw
            # exceptMaybe (RpdError "")
    canceler :: Canceler <-
        liftEffect $ E.subscribe flow push
    pure canceler


subscribeInlet
    :: forall d
     . InletPath
    -> InletHandler d
    -> Network d
    -> Rpd (Network d)
subscribeInlet inletPath (InletHandler handler) nw = do
    canceler <- subscribeInlet' inletPath (InletHandler handler) nw
    curCancelers <-
        view (_inletCancelers inletPath) nw
            # exceptMaybe (RpdError "")
    pure $
        nw # setJust (_inletCancelers inletPath) (curCancelers +> canceler)


subscribeInlet'
    :: forall d
     . InletPath
    -> InletHandler d
    -> Network d
    -> Rpd Canceler
subscribeInlet' inletPath (InletHandler handler) nw = do
    flow :: Flow d <-
        view (_inletFlow inletPath) nw
            # exceptMaybe (RpdError "")
    canceler :: Canceler <- liftEffect $ E.subscribe flow handler
    pure canceler


subscribeOutlet
    :: forall d
     . OutletPath
    -> OutletHandler d
    -> Network d
    -> Rpd (Network d)
subscribeOutlet outletPath handler nw = do
    _ <- subscribeOutlet' outletPath handler nw
    -- FIXME: implement
    pure nw


subscribeOutlet'
    :: forall d
     . OutletPath
    -> OutletHandler d
    -> Network d
    -> Rpd Canceler
subscribeOutlet' outletPath (OutletHandler handler) nw = do
    flow :: Flow d <-
        view (_outletFlow outletPath) nw
            # exceptMaybe (RpdError "")
    canceler :: Canceler <-
        liftEffect $ E.subscribe flow handler
    pure canceler


subscribeAllInlets
    :: forall d
     . (InletPath -> d -> Effect Unit)
    -> Network d
    -> Rpd (Network d)
subscribeAllInlets handler nw = do
    _ <- liftEffect $ subscribeAllInlets' handler nw
    -- FIXME: implement
    pure nw


subscribeAllInlets'
    :: forall d
     . (InletPath -> d -> Effect Unit)
    -> Network d
    -> Effect (InletPath /-> Canceler)
subscribeAllInlets' handler (Network _ { inlets }) =
    traverse sub inlets
    where
        sub :: Inlet d -> Subscriber
        sub (Inlet inletPath _ { flow }) =
            case flow of
                InletPFlow (PushableFlow _ fl) -> E.subscribe fl $ handler inletPath


subscribeAllOutlets
    :: forall d
     . (OutletPath -> d -> Effect Unit)
    -> Network d
    -> Rpd (Network d)
subscribeAllOutlets handler nw = do
    _ <- liftEffect $ subscribeAllOutlets' handler nw
    -- FIXME: implement
    pure nw


subscribeAllOutlets'
    :: forall d
     . (OutletPath -> d -> Effect Unit)
    -> Network d
    -> Effect (OutletPath /-> Canceler)
subscribeAllOutlets' handler (Network _ { outlets }) =
    traverse sub outlets
    where
        sub :: Outlet d -> Subscriber
        sub (Outlet outletPath _ { flow }) =
            case flow of
                OutletPFlow (PushableFlow _ fl) -> E.subscribe fl $ handler outletPath


subscribeChannelsData
    :: forall d
     . (OutletPath -> d -> Effect Unit)
    -> (InletPath -> d -> Effect Unit)
    -> Network d
    -> Rpd (Network d)
subscribeChannelsData oHandler iHandler nw = do
    _ <- liftEffect $ subscribeChannelsData' oHandler iHandler nw
    -- FIXME: implement
    pure nw


subscribeChannelsData'
    :: forall d
     . (OutletPath -> d -> Effect Unit)
    -> (InletPath -> d -> Effect Unit)
    -> Network d
    -> Effect ((OutletPath /-> Canceler) /\ (InletPath /-> Canceler))
subscribeChannelsData' oHandler iHandler nw =
    bisequence $ subscribeAllOutlets' oHandler nw /\ subscribeAllInlets' iHandler nw


subscribeNode
    :: forall d
     . NodePath
    -> (Int /\ d -> Effect Unit)
    -> Network d
    -> Rpd (Network d)
subscribeNode nodePath handler nw = do
    _ <- subscribeNode' nodePath handler nw
    -- FIXME: implement
    pure nw


subscribeNode'
    :: forall d
     . NodePath
    -> (Int /\ d -> Effect Unit)
    -> Network d
    -> Rpd Canceler
subscribeNode' nodePath handler nw = do
    flow :: Flow (Int /\ d) <-
        view (_nodeFlow nodePath) nw
            # exceptMaybe (RpdError "")
    canceler :: Canceler <-
        liftEffect $ E.subscribe flow handler
    pure canceler


connect
    :: forall d
     . OutletPath
    -> InletPath
    -> Network d
    -> Rpd (Network d)
-- FIXME: rewrite for the case of different patches
connect outletPath inletPath
    nw@(Network nwdef nwstate) = do
    let
        linkId = nextLinkId nw
        newLink = Link outletPath inletPath
        iNodePath = getNodeOfInlet inletPath
        oPatchId = getPatchOfOutlet outletPath
        iPatchId = getPatchOfInlet inletPath

    outletPFlow <- view (_outletPFlow outletPath) nw # exceptMaybe (RpdError "")
    inletPFlow <- view (_inletPFlow inletPath) nw # exceptMaybe (RpdError "")

    let
        (PushableFlow _ outletFlow) = outletPFlow
        (PushableFlow pushToInlet inletFlow) = inletPFlow

    linkCanceler :: Canceler <-
            liftEffect $
                E.subscribe outletFlow pushToInlet

    pure $ nw
            # setJust (_link linkId) newLink
            # setJust (_linkCancelers linkId) [ linkCanceler ]


disconnectAll
    :: forall d
     . OutletPath
    -> InletPath
    -> Network d
    -> Rpd (Network d)
disconnectAll outletPath inletPath
    nw@(Network nwdef nwstate@{ links }) = do
    let
        linkForDeletion (Link outletPath' inletPath') =
            (outletPath' == outletPath) && (inletPath' == inletPath)
        linksForDeletion = Map.keys $ links # Map.filter linkForDeletion

        oPatchId = getPatchOfOutlet outletPath
        iPatchId = getPatchOfInlet inletPath

    _ <- liftEffect $ traverse_
            (\linkId ->
                view (_linkCancelers linkId) nw
                    # fromMaybe []
                    # traverse_ liftEffect)
            linksForDeletion

    pure $ (
        foldr (\linkId nw ->
            nw # set (_link linkId) Nothing
               # set (_linkCancelers linkId) Nothing
        ) nw linksForDeletion
        -- # setJust (_inletConnections inletPath) newInletConnections
        -- # setJust (_outletConnections outletPath) newOutletConnections
    )

    -- TODO: un-subscribe `process`` function of the target node to update values including this connection

-- TODO: disconnectTop

-- TODO: disconnectTopOf (OutletPath /\ InletPath)

-- TODO: subscribeAllNodes

-- TODO: subscribeAllData


updateNodeProcessFlow
    :: forall d
     . NodePath
    -> Network d
    -> Rpd (Network d)
updateNodeProcessFlow nodePath nw = do
    -- cancel the previous subscription if it exists
    _ <- view (_nodeCancelers nodePath) nw
            # fromMaybe []
            # traverse_ liftEffect
    (Node _ nodeDef { flow, inlets, outlets }) <-
        except $ view (_node nodePath) nw # note (RpdError "")
    case nodeDef.process of
        Withhold -> pure nw
        processF ->
            if (Set.isEmpty inlets || Set.isEmpty outlets) then pure nw else do
                let
                    (ProcessPFlow (PushableFlow _ processFlow)) = flow
                    (outletFlows :: Array (PushableFlow d)) =
                        outlets
                            # (Set.toUnfoldable :: forall a. Set a -> Array a)
                            # map (\outletPath -> view (_outletPFlow outletPath) nw)
                            # E.filterMap identity -- FIXME: raise an error if outlet wasn't found
                    pushToOutletFlow :: Maybe (Int /\ d) -> Effect Unit
                    pushToOutletFlow maybeData =
                        case maybeData of
                            Just (outletIdx /\ d) ->
                                case outletFlows !! outletIdx of
                                    Just (PushableFlow pushF _) -> pushF d
                                    _ -> pure unit
                            _ -> pure unit
                OutletsFlow outletsFlow /\ maybeCancelBuild <-
                    buildOutletsFlow nodePath processF processFlow inlets outlets nw
                canceler :: Canceler
                    <- liftEffect $ E.subscribe outletsFlow pushToOutletFlow
                let
                    cancelers =
                        case maybeCancelBuild of
                            Just buildCanceler -> [ canceler, buildCanceler ]
                            Nothing -> [ canceler ]
                pure $ nw # setJust (_nodeCancelers nodePath) cancelers


buildOutletsFlow
    :: forall d
     . NodePath
    -> ProcessF d
    -> Flow (Int /\ d)
    -> Set InletPath
    -> Set OutletPath
    -> Network d
    -> Rpd (OutletsFlow d /\ Maybe Canceler) -- FIXME: for now, we only need Rpd to handle the
buildOutletsFlow _ Withhold processFlow _ _ _ =
    -- liftEffect never >>= pure <<< OutletsFlow
    liftEffect never >>= \flow ->
        pure $ OutletsFlow flow /\ Nothing
buildOutletsFlow _ PassThrough processFlow _ _ _ =
    pure $ (OutletsFlow $ Just <$> processFlow)
           /\ Nothing
buildOutletsFlow _ (ByIndex processF) processFlow inlets outlets _ =
    case processF $ InletsByIndexFlow processFlow of
        OutletsByIndexFlow outletsByIndex ->
            pure $ (OutletsFlow $ Just <$> outletsByIndex)
                   /\ Nothing
buildOutletsFlow _ (ByLabel processF) processFlow inlets outlets nw =
    let
        inletLabels = extractInletLabels inlets nw
        outletLabels = extractOutletLabels outlets nw
        mapInletFlow (inletIdx /\ d) =
            case inletLabels !! inletIdx of
                Just label -> (Just label /\ d)
                _ -> Nothing /\ d
        mapOutletFlow maybeData =
            maybeData
                >>= \(label /\ d) -> outletLabels # Array.elemIndex label
                <#> \idx -> idx /\ d
        labeledInletsFlow = mapInletFlow <$> processFlow
        OutletsByLabelFlow labeledOutletsFlow =
            processF $ InletsByLabelFlow labeledInletsFlow
    in pure $ (OutletsFlow $ mapOutletFlow <$> labeledOutletsFlow)
              /\ Nothing
buildOutletsFlow nodePath (ByPath processF) processFlow inlets outlets _ =
    let
        mapInletFlow (inletIdx /\ d) =
            Just (InletPath nodePath inletIdx) /\ d
        inletsWithPathFlow = mapInletFlow <$> processFlow
        outletsWithPathFlow = processF inletsWithPathFlow
        mapOutletFlow maybeData =
            maybeData
                <#> \((OutletPath _ outletIdx) /\ d) ->
                    outletIdx /\ d
    in pure $ (OutletsFlow $ mapOutletFlow <$> outletsWithPathFlow)
              /\ Nothing
buildOutletsFlow _ (FoldedByIndex processF) processFlow inlets _ _ = do
    -- TODO: generalize to Foldable
    { event, push } <- liftEffect E.create
    let
        foldingF (curInletIdx /\ curD) inletVals =
            Array.updateAt curInletIdx (Just curD) inletVals
                # fromMaybe inletVals
        inletsFlow = E.fold foldingF processFlow
            $ Array.replicate (Set.size inlets) Nothing
    cancel <- liftEffect $ E.subscribe inletsFlow $ \inletsVals ->
        let (OutletsData outletVals) = processF $ InletsData inletsVals
        in forWithIndex outletVals \idx val ->
            push $ Just $ idx /\ val
    pure $ OutletsFlow event
           /\ Just cancel
buildOutletsFlow _ (FoldedByLabel processF) processFlow inlets outlets nw = do
    -- TODO: generalize to Foldable
    { event, push } <- liftEffect E.create
    let
        inletLabels = extractInletLabels inlets nw
        outletLabels = extractOutletLabels outlets nw
        foldingF (curInletIdx /\ curD) inletVals =
            case inletLabels !! curInletIdx of
                Just label -> inletVals # Map.insert label curD
                _ -> inletVals
        inletsFlow = E.fold foldingF processFlow Map.empty
        adaptOutletVals :: (String /-> d) -> Array (Maybe (Int /\ d))
        adaptOutletVals ouletVals =
            Map.toUnfoldable ouletVals
                <#> \(label /\ d) ->
                    outletLabels # Array.elemIndex label
                <#> flip (/\) d
    cancel <- liftEffect $ E.subscribe inletsFlow $ \inletsVals ->
        let (OutletsMapData outletVals) = processF $ InletsMapData inletsVals
        in traverse push $ adaptOutletVals outletVals
    pure $ OutletsFlow event
           /\ Just cancel

    -- TODO: may be, request these functions from user:
    --   for given inlet (path?), get its map key
    --   for given outlet (path?), get its map key
    --   for given key, get the corresponding inlet path
    --   for given key, get the corresponding outlet path


joinCancelers :: Canceler -> Canceler -> Canceler
joinCancelers = (<>)


extractInletLabels :: forall d. Set InletPath → Network d → Array String
extractInletLabels inlets nw =
    inlets
        # (Set.toUnfoldable :: forall a. Set a -> Array a)
        # map (\inletPath -> view (_inletLabel inletPath) nw)
        # E.filterMap identity -- FIXME: raise an error if outlet wasn't found


extractOutletLabels :: forall d. Set OutletPath → Network d → Array String
extractOutletLabels outlets nw =
    outlets
        # (Set.toUnfoldable :: forall a. Set a -> Array a)
        # map (\outletPath -> view (_outletLabel outletPath) nw)
        # E.filterMap identity -- FIXME: raise an error if outlet wasn't found


-- TODO: rollback :: RpdError -> Network -> Network


instance showRpdError :: Show RpdError where
    -- show (RpdError text) = "(RpdError)" <> text
    show (RpdError text) = text



-- instance eqDataSource :: Eq (DataSource d) where
--     eq (OutletSource oa a) (OutletSource ob b) = oa == ob
--     eq _ _ = false


-- instance ordDataSource :: Ord (DataSource d) where
--     compare (OutletSource oa a) (OutletSource ob b) = compare oa ob
--     compare _ _ = LT

