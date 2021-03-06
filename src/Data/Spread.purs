module Data.Spread where

import Prelude

import Math (abs)
import Data.Lerp (class Lerp, lerp)
import Data.Int (toNumber, floor)
import Data.Maybe (Maybe(..))
import Data.Array (range, catMaybes)
import Data.Tuple.Nested ((/\), type (/\))


data Spread a = Spread Int (Int -> Maybe a)


instance functorSpread :: Functor Spread where
    map f (Spread count sf) =
        Spread count \idx -> f <$> sf idx


-- FIXME: expensive to run
instance showSpread :: Show a => Show (Spread a) where
    -- show = show <<< catMaybes <<< run
    show (Spread n _) = "Spread (" <> show n <> ")"


-- FIXME: expensive to run
instance eqSpread :: Eq a => Eq (Spread a) where
    eq a b = eq (run a) (run b)


infixl 8 get as !!


get :: forall a. Spread a -> Int -> Maybe a
get (Spread _ f) idx = f idx


nil :: forall a. Spread a
nil = Spread 0 $ const Nothing


singleton :: forall a. a -> Spread a
singleton v = Spread 1 $ const $ Just v


repeat :: forall a. Int -> a -> Spread a
repeat times v = Spread times $ const $ Just v


concat :: forall a. Spread a -> Spread a -> Spread a
concat (Spread countA fA) (Spread countB fB) =
    Spread (countA + countB) \idx ->
        case alignIndex (countA + countB) idx of
            alignedIndex ->
                if alignedIndex < countA then
                    fA alignedIndex
                else
                    fB $ alignedIndex - countA


make :: forall x. Lerp x => x /\ x -> Int -> Spread x
make (from /\ to) count | count < 0 =
    make (to /\ from) $ floor $ abs $ toNumber count
make range count | count > 1 =
    Spread count \idx ->
        lerp range $ toNumber (alignIndex count idx) / toNumber (count - 1)
make (from /\ _) count | count == 1 =
    Spread count $ const $ Just from
make _ count | otherwise = -- 0, for example
    Spread count $ const Nothing


run :: forall x. Spread x -> Array (Maybe x)
run (Spread count f) = f <$> range 0 (count - 1)


join :: forall a b. Spread a -> Spread b -> Spread (a /\ b)
join (Spread countA fA) (Spread countB fB) =
    Spread (max countA countB) \idx -> (/\) <$> fA idx <*> fB idx


-- do not not expose
alignIndex :: Int -> Int -> Int
alignIndex count index | index < 0 =
    alignIndex count $ count + index
alignIndex count index | index >= count =
    index `mod` count
alignIndex _ index | otherwise =
    index
