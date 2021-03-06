module Xodus.Toolkit.Node where

import Prelude

import Data.Tuple.Nested ((/\))
import Data.Maybe (Maybe(..))

import Noodle.Process (ProcessF(..)) as R
import Noodle.Toolkit (NodeDef(..), noInlets, noOutlets, withInlets, withOutlets, defineNode) as T
import Noodle.Toolkit ((~<), (>~))
import Noodle.Render.Atom (class Atom) as R

import Xodus.Toolkit.Value (Value(..), Aggregate(..))
import Xodus.Toolkit.Channel (Channel(..))
import Xodus.Requests
import Xodus.Query as Q


type NodeDef = T.NodeDef Value Channel


data Node
    = ConnectNode
    | NodeListNode
    | SourceNode
    | AllOfNode
    | TakeNode
    | DropNode
    | UnionNode
    | IntersectNode
    | FilterNode
    | SortNode
    | SelectOneNode
    | SelectNode


nodesForTheList :: Array Node
nodesForTheList =
    [ ConnectNode
    , SourceNode
    , AllOfNode
    , TakeNode
    , DropNode
    , UnionNode
    , IntersectNode
    , FilterNode
    , SortNode
    , SelectOneNode
    , SelectNode
    ]


{- CONNECT -}

connectNode :: NodeDef
connectNode =
    T.defineNode
        (T.withInlets
            ~< "bang" /\ Channel)
        (T.withOutlets
            >~ "databases" /\ Channel)
        $ R.ProcessAff
            $ \receive -> do
                databases <- getDatabases
                let
                    send "databases" = Just $ Databases databases
                    send _ = Nothing
                pure send


{- SOURCE -}

sourceNode :: NodeDef
sourceNode =
    T.defineNode
        (T.withInlets
            ~< "databases" /\ Channel
            ~< "only" /\ Channel)
        (T.withOutlets
            >~ "source" /\ Channel)
        $ R.ProcessAff
            $ \receive -> do
                case receive "only" of
                    Just (SelectDatabase database) -> do
                        entityTypes <- getEntityTypes database
                        let
                            send "source" = Just $ Source database entityTypes
                            send _ = Nothing
                        pure send
                    _ -> pure $ const Nothing


{- ALL OF -}

allOfNode :: NodeDef
allOfNode =
    T.defineNode
        (T.withInlets
            ~< "source" /\ Channel
            ~< "only" /\ Channel)
        (T.withOutlets
            >~ "query" /\ Channel)
        $ R.Process
            $ \receive ->
                case receive "source" of
                    Just (Source database entityTypes) -> do
                        let
                            send "query" = Just $ Query $ Q.make database entityTypes $
                                case receive "only" of
                                    Just (SelectType entityType) ->
                                        Q.AllOf entityType
                                    _ -> Q.All
                            send _ = Nothing
                        pure send
                    _ -> pure $ const Nothing



{- TAKE -}

takeNode :: NodeDef
takeNode =
    T.defineNode
        (T.withInlets
            ~< "query" /\ Channel
            ~< "amount" /\ Channel)
        (T.withOutlets
            >~ "query" /\ Channel)
        $ R.Process
            $ \receive ->
                let
                    send "query" =
                        case receive "query" /\ receive "amount" of
                            Just (Query query)
                            /\ Just (Amount (Exactly amount))
                                -> Just $ Query $ Q.Take amount <$> query
                            Just query /\ _ -> Just query
                            _ -> Nothing
                    send _ = Nothing
                in pure send


{- DROP -}

dropNode :: NodeDef
dropNode =
    T.defineNode
        (T.withInlets
            ~< "query" /\ Channel
            ~< "amount" /\ Channel)
        (T.withOutlets
            >~ "query" /\ Channel)
        $ R.Process
            $ \receive ->
                let
                    send "query" =
                        case receive "query" /\ receive "amount" of
                            Just (Query query)
                            /\ Just (Amount (Exactly amount))
                                -> Just $ Query $ Q.Drop amount <$> query
                            Just query /\ _ -> Just query
                            _ -> Nothing
                    send _ = Nothing
                in pure send


{- UNION -}

unionNode :: NodeDef
unionNode =
    T.defineNode
        (T.withInlets
            ~< "queryA" /\ Channel
            ~< "queryB" /\ Channel)
        (T.withOutlets
            >~ "query" /\ Channel)
        $ R.Process
            $ \receive ->
                let
                    send "query" =
                        case receive "queryA" /\ receive "queryB" of
                            Just (Query queryA)
                            /\ Just (Query queryB)
                                -> Just $ Query $ Q.Union <$> queryA <*> queryB
                            Just queryA /\ Nothing -> Just queryA
                            Nothing /\ Just queryB -> Just queryB
                            _ -> Nothing
                    send _ = Nothing
                in pure send


{- INTERSECT -}

intersectNode :: NodeDef
intersectNode =
    T.defineNode
        (T.withInlets
            ~< "queryA" /\ Channel
            ~< "queryB" /\ Channel)
        (T.withOutlets
            >~ "query" /\ Channel)
        $ R.Process
            $ \receive ->
                let
                    send "query" =
                        case receive "queryA" /\ receive "queryB" of
                            Just (Query queryA)
                            /\ Just (Query queryB)
                                -> Just $ Query $ Q.Intersect <$> queryA <*> queryB
                            Just queryA /\ Nothing -> Just queryA
                            Nothing /\ Just queryB -> Just queryB
                            _ -> Nothing
                    send _ = Nothing
                in pure send


{- FILTER -}

filterNode :: NodeDef
filterNode =
    T.defineNode
        (T.withInlets
            ~< "query" /\ Channel
            ~< "filter" /\ Channel)
        (T.withOutlets
            >~ "query" /\ Channel)
        $ R.Process
            $ \receive ->
                let
                    send "query" =
                        case receive "query" /\ receive "filter" of
                            Just (Query query)
                            /\ Just (ToFilter condition _)
                                -> Just $ Query $ Q.Filter condition <$> query
                            Just query /\ _ -> Just query
                            _ -> Nothing
                    send _ = Nothing
                in pure send


{- SORT -}

sortNode :: NodeDef
sortNode =
    T.defineNode
        (T.withInlets
            ~< "query" /\ Channel
            ~< "sort" /\ Channel)
        (T.withOutlets
            >~ "query" /\ Channel)
        $ R.Process
            $ \receive ->
                let
                    send "query" =
                        case receive "query" /\ receive "sort" of
                            Just (Query query)
                            /\ Just (ToSort comparison _)
                                -> Just $ Query $ Q.Sort comparison <$> query
                            Just query /\ _ -> Just query
                            _ -> Nothing
                    send _ = Nothing
                in pure send


{- SELECT -}

selectNode :: NodeDef
selectNode =
    T.defineNode
        (T.withInlets
            ~< "query" /\ Channel
            ~< "group" /\ Channel)
        (T.withOutlets
            >~ "result" /\ Channel
            >~ "one" /\ Channel)
        $ R.ProcessAff
            $ \receive ->
                case receive "query" of
                    Just (Query query) -> do
                        entities <- perform query
                        let
                            send "result" = Just $ Result entities
                            send _ = Nothing
                        pure send
                    _ -> pure $ const Nothing


{- SELECT ONE -}

selectOneNode :: NodeDef
selectOneNode =
    T.defineNode
        (T.withInlets
            ~< "one" /\ Channel)
        (T.noOutlets)
        $ R.Withhold


instance nodeAtom :: R.Atom Node where
    labelOf = show
    uniqueIdOf = show
    debugInfoOf = show


instance showNode :: Show Node where
    show NodeListNode = "node list"
    show ConnectNode = "connect"
    show SourceNode = "source"
    show AllOfNode = "all of"
    show TakeNode = "take"
    show DropNode = "drop"
    show FilterNode = "filter"
    show UnionNode = "union"
    show IntersectNode = "intersect"
    show SortNode = "sort"
    show SelectOneNode = "select one"
    show SelectNode = "select"
