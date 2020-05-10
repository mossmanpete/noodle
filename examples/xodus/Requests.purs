module Xodus.Requests where

import Prelude

import Data.List
import Data.List (take, drop, filter, union, sortBy, intersect) as List
import Data.Newtype (class Newtype, unwrap)
import Data.Either
import Data.Argonaut.Core (Json)
import Data.Argonaut.Core as J
import Data.Argonaut.Encode as J
import Data.Argonaut.Decode as J

import Effect.Aff (Milliseconds(..), Aff, launchAff_, delay)

import Affjax (get)
import Affjax.ResponseFormat (json)

import Xodus.Dto
import Xodus.Query


newtype Method = Method String


rootApi :: String
rootApi = "http://localhost:18080/api"


requestValue :: forall a. J.DecodeJson a => Method -> a -> Aff a
requestValue (Method method) default =
    get json (rootApi <> method)
        <#> either (const default)
            (_.body >>> decodeValue)
    where
        decodeValue :: Json -> a
        decodeValue = J.decodeJson >>> either (const default) identity


requestList :: forall a. J.DecodeJson a => Method -> Aff (List a)
requestList method =
    requestValue method Nil


getDatabases :: Aff (List Database)
getDatabases =
    requestList $ Method "/dbs"


getEntities :: Database -> EntityType -> Aff (List Entity)
getEntities (Database database) (EntityType entityType) =
    requestValue
        (Method $ "/dbs/" <> database.uuid <> "/entities"
                          <> "?id=" <> show entityType.id
                          <> "&offset=" <> show 0
                          <> "&pageSize=" <> show 50)
        { items : (Nil :: List Entity) }
        <#> _.items


getEntityTypes :: Database -> Aff (List EntityType)
getEntityTypes (Database database) =
    requestList $ Method $ "/dbs/" <> database.uuid <> "/types"



perform :: Query -> Aff (List Entity)
perform (Query' database entityTypes selector) = foldSelector selector
    where
    foldSelector All = fold $ getEntities database <$> entityTypes
    foldSelector (AllOf entityType) = getEntities database entityType
    foldSelector (Take amount selector') = List.take amount <$> foldSelector selector'
    foldSelector (Drop amount selector') = List.drop amount <$> foldSelector selector'
    foldSelector (Filter (Condition condition) selector')
            = List.filter condition <$> foldSelector selector'
    foldSelector (Union selectorA selectorB)
            = List.union <$> foldSelector selectorA <*> foldSelector selectorB
    foldSelector (Intersect selectorA selectorB)
            = List.intersect <$> foldSelector selectorA <*> foldSelector selectorB
    foldSelector (Sort (Comparison order) selector')
            = List.sortBy order <$> foldSelector selector'