module Xodus.Toolkit.Render.Html where


import Prelude

import Data.Maybe (Maybe(..), maybe)
import Data.List (toUnfoldable)

import Noodle.Network (Node(..)) as R
import Noodle.API.Action (Action(..), RequestAction(..), DataAction(..)) as A
import Noodle.Render.Html (View, ToolkitRenderer, core, my) as R
import Noodle.Render.Html.NodeList (render) as NodeList
import Noodle.Path as P
import Noodle.Process (Receive, Send) as R

import Noodle.Render.Atom as R

import Spork.Html (Html)
import Spork.Html as H

import Xodus.Toolkit.Node (Node(..), nodesForTheList)
import Xodus.Toolkit.Value (Value(..))
import Xodus.Toolkit.Channel (Channel(..))
import Xodus.Toolkit.Dto


renderer :: R.ToolkitRenderer Value Channel Node
renderer =
    { renderNode : renderNode
    , renderInlet : \c _ d ->
        H.div
            [ H.classes [ "tk-inlet", classFor c ] ]
            [ H.text $ maybe "?" show d ]
    , renderOutlet : \c _ d ->
        H.div
            [ H.classes [ "tk-outlet", classFor c ] ]
            [ H.text $ maybe "?" show d ]
    }
    where
        classFor Channel = "tk-channel"


renderNode
    :: Node
    -> R.Node Value Node
    -> R.Receive Value
    -> R.Send Value
    -> R.View Value Channel Node

renderNode NodeListNode (R.Node _ (P.ToNode { patch }) _ _ _) _ _ =
    NodeList.render (P.ToPatch patch) nodesForTheList

renderNode ConnectNode (R.Node _ path _ _ _) _ _ =
    H.div
        [ H.classes [ "tk-node" ] ]
        [ H.div
            [ H.onClick
                $ H.always_ $ R.core
                $ A.Request
                $ A.ToSendToInlet (P.inletInNode path "bang")
                $ Bang
            ]
            [ H.span [ H.classes [ "xodus-connect-button" ] ] [ H.text "◌" ] ]
        ]

renderNode DatabasesNode (R.Node _ path _ _ _) receive _ =
    H.div
        [ H.classes [ "tk-node" ] ]
        [ case receive "databases" of
               Just (Databases databases) -> H.ul [] $ renderDatabase <$> toUnfoldable databases
               _ -> H.text "no databases"
        ]
    where
        renderDatabase :: Database -> R.View Value Channel Node
        renderDatabase (Database database) =
            H.li
                [ H.classes [ "xodus-database" ]
                , H.onClick
                    $ H.always_ $ R.core
                    $ A.Request
                    $ A.ToSendToOutlet (P.outletInNode path "database")
                    $ Source $ Database database
                ]
                [ H.text database.location ]

renderNode QueryNode (R.Node _ path _ _ _) receive _ =
    H.div
        [ H.classes [ "tk-node" ] ]
        [ H.div [] [] ]
