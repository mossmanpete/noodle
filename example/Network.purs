module Example.Network
    ( network
    ) where

import Prelude

import Rpd.Network (empty) as Network
import Rpd.Network as R
import Rpd.Path as R
import Rpd.Toolkit as R

import Rpd.API (Rpd) as R
import Rpd.API as Rpd
import Rpd.API ((</>))

import Example.Toolkit (toolkit, Value(..))

network :: R.Rpd (R.Network Value)
network =
    Rpd.init "foo"
        </> Rpd.addPatch (R.toPatch "test")
        </> Rpd.addToolkitNode (R.toNode "test" "random") (R.NodeDefAlias "random") toolkit
        </> Rpd.sendToInlet (R.toInlet "test" "random" "min") (Number' 10.0)
        </> Rpd.sendToInlet (R.toInlet "test" "random" "max") (Number' 20.0)
        </> Rpd.sendToInlet (R.toInlet "test" "random" "bang") Bang
