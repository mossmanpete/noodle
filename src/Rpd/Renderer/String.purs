module Rpd.Renderer.String
    ( StringRenderer
    , stringRenderer
    , view -- TODO: do not expose maybe?
    ) where

import Prelude

import Data.Map as Map
import Data.Array as Array
import Data.List as List
import Data.Sequence as Seq
import Data.Sequence (Seq)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Lens as L
import Data.Either (Either(..))
import Data.String (joinWith)
import Data.Tuple.Nested ((/\))

import Rpd.Network
    ( Network(..)
    , Patch(..)
    , Node(..)
    , Inlet(..)
    , Outlet(..)
    , Link(..)
    ) as R
import Rpd.API (RpdError) as R
import Rpd.Optics (_node, _inlet, _outlet, _link, _networkPatches, _networkLinks)
import Rpd.Render (PushCmd, Renderer(..))
import Rpd.Path as P


type StringRenderer d c n = Renderer d c n String

data MultipleOrNone = MultipleOrNone String
data Single = Single String
data Counter = Counter MultipleOrNone Single


lineBreak = "\n" :: String
vertLine = " " :: String
corner = "·" :: String
semicolon = ":" :: String


patchCounter = Counter (MultipleOrNone "Patches") (Single "Patch") :: Counter
nodeCounter = Counter (MultipleOrNone "Nodes") (Single "Node") :: Counter
inletCounter = Counter (MultipleOrNone "Inlets") (Single "Inlet") :: Counter
outletCounter = Counter (MultipleOrNone "Outlets") (Single "Outlet") :: Counter
linkCounter = Counter (MultipleOrNone "Links") (Single "Link") :: Counter


count :: Counter -> Int -> String
count (Counter (MultipleOrNone none) _ ) size    | size == 0 = "No " <> none
count (Counter _ (Single single)) size           | size == 1 = "One " <> single
count (Counter (MultipleOrNone multiple) _) size | size > 1  = show size <> " " <> multiple
count (Counter (MultipleOrNone multiple) _) _    | otherwise = "? " <> show multiple


stringRenderer :: forall d c n. StringRenderer d c n
stringRenderer =
    Renderer "" view


view :: forall d c n. PushCmd d c n -> Either R.RpdError (R.Network d c n) -> String
view _ (Right nw@(R.Network { name, patches })) =
    "Network " <> name <> semicolon
        <> lineBreak
        <> count patchCounter patchCount
        <> (if patchCount > 0 then
                lineBreak <> corner <> patchesInfo
            else "")
    where
        allPatches = L.view _networkPatches nw
        patchCount = List.length allPatches
        patchesInfo =
            joinWith (lineBreak <> corner)
                $ (viewPatch nw <$> allPatches)
                    # List.toUnfoldable
view _ (Left err) =
    "<" <> show err <> ">"


viewPatch :: forall d c n. R.Network d c n -> R.Patch d c n -> String
viewPatch nw (R.Patch id path@(P.ToPatch name) { nodes, links }) =
    "Patch " <> name <> " " <> show path <> semicolon
        <> lineBreak <> vertLine
        <> count nodeCounter nodeCount
        <> (if nodeCount > 0 then
               lineBreak <> vertLine <> corner <> nodesInfo
            else "")
        <> lineBreak <> vertLine
        <> count linkCounter linkCount
        <> (if linkCount > 0 then
               lineBreak <> vertLine <> corner <> linksInfo
            else "")
    where
        nodeCount = Seq.length nodes
        linkCount = Seq.length links
        allNodes =
            Seq.toUnfoldable nodes # map \path -> L.view (_node path) nw
        nodesInfo =
            joinWith (lineBreak <> vertLine <> corner)
                $ viewNode nw <$> Array.catMaybes allNodes
        allLinks =
            Seq.toUnfoldable links # map \path -> L.view (_link path) nw
        linksInfo =
            joinWith (lineBreak <> vertLine <> corner)
                $ viewLink nw <$> Array.catMaybes allLinks


viewNode :: forall d c n. R.Network d c n -> R.Node d n -> String
viewNode nw (R.Node _ path@(P.ToNode { node }) _ _ { inlets, outlets }) =
    "Node " <> node <> " " <> show path <> semicolon
        <> lineBreak <> vertLine <> vertLine
        <> count inletCounter inletCount
        <> (if inletCount > 0 then
                lineBreak <> vertLine <> vertLine <> corner <> inletsInfo
            else "")
        <> lineBreak <> vertLine <> vertLine
        <> count outletCounter outletCount
        <> (if outletCount > 0 then
                lineBreak <> vertLine <> vertLine <> corner <> outletsInfo
            else "")
    where
        inletCount = Seq.length inlets
        outletCount = Seq.length outlets
        allInlets =
            Seq.toUnfoldable inlets # map \path -> L.view (_inlet path) nw
        inletsInfo =
            joinWith (lineBreak <> vertLine <> vertLine <> corner)
                $ viewInlet nw <$> Array.catMaybes allInlets
        allOutlets =
            Seq.toUnfoldable outlets # map \path -> L.view (_outlet path) nw
        outletsInfo =
            joinWith (lineBreak <> vertLine <> vertLine <> corner)
                $ viewOutlet nw <$> Array.catMaybes allOutlets


viewInlet :: forall d c n. R.Network d c n -> R.Inlet d c -> String
viewInlet _ (R.Inlet _ path@(P.ToInlet { inlet }) _ _) =
    "Inlet " <> inlet <> " " <> show path


viewOutlet :: forall d c n. R.Network d c n -> R.Outlet d c -> String
viewOutlet _ (R.Outlet _ path@(P.ToOutlet { outlet }) _ _) =
    "Outlet " <> outlet <> " " <> show path


viewLink :: forall d c n. R.Network d c n -> R.Link -> String
viewLink nw (R.Link _ { outlet : outletUuid, inlet : inletUuid }) =
    case L.view (_outlet outletUuid) nw /\ L.view (_inlet inletUuid) nw of
        Just (R.Outlet _ outletPath _ _) /\ Just (R.Inlet _ inletPath _ _) ->
            "Link from " <> show (outletPath :: P.ToOutlet) <> " to " <> show inletPath
        _ ->
            "Link, which is detached or lost in space"



-- collectSetInfo nw viewItem lens source =
--     joinWith (lineBreak <> space)
--         $ viewItem nw <$> Array.catMaybes allItems
--     where
--         allItems = Set.toUnfoldable source # map \path -> L.view (lens path) nw
