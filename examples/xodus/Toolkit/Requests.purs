module Xodus.Toolkit.Requests where

import Prelude

import Data.List
import Data.Newtype (class Newtype, unwrap)
import Data.Either
import Data.Argonaut.Core (Json)
import Data.Argonaut.Core as J
import Data.Argonaut.Encode as J
import Data.Argonaut.Decode as J

import Effect.Aff (Milliseconds(..), Aff, launchAff_, delay)

import Affjax (get)
import Affjax.ResponseFormat (json)

import Xodus.Toolkit.Dto


rootApi :: String
rootApi = "http://localhost:18080/api"


getDatabases :: Aff (List Database)
getDatabases =
    get json (rootApi <> "/dbs")
        <#> either (const Nil)
            (_.body
                >>> decodeDatabases
                >>> map unwrap
                >>> map Database)


decodeDatabases :: Json -> List Database
decodeDatabases v =
    J.decodeJson v # either (const Nil) identity
