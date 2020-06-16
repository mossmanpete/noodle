module Data.Seq.Extra where


import Prelude

import Data.Sequence as Seq
import Data.Sequence (Seq)
import Data.Maybe (Maybe(..))
import Data.Foldable (foldr)

import Data.List (nubBy) as List


-- TODO: place in Data.Seq
member :: forall a. Eq a => a -> Seq a -> Boolean
member v seq =
    Seq.length (Seq.filter ((==) v) seq) > 0


member' :: forall a. Eq a => a -> Seq a -> Maybe Unit
member' v seq =
    if member v seq then Just unit else Nothing


delete :: forall a. Eq a => a -> Seq a -> Seq a
delete v seq =
    Seq.filter ((/=) v) seq


catMaybes :: forall a. Seq (Maybe a) -> Seq a
catMaybes seq =
    foldr eliminateMaybe Seq.empty seq
    where
        eliminateMaybe (Just val) seq' = Seq.cons val seq'
        eliminateMaybe Nothing seq' = seq'


nub :: forall a. Eq a => Seq a -> Seq a
nub = nubBy (==)


nubBy :: forall a. (a -> a -> Boolean) -> Seq a -> Seq a
nubBy eq =
    Seq.toUnfoldable >>> List.nubBy eq >>> Seq.fromFoldable


-- TODO: place in Data.Seq
infixr 6 Seq.cons as :
infixl 6 Seq.snoc as +>


_on :: forall a. Eq a => a -> Lens' (Seq a) (Maybe Unit)
_on v =
    lens getter setter
    where
        getter = Util.seqMember' v
        setter seq maybeVal =
            case maybeVal of
                Just val -> v # Seq.snoc seq
                Nothing -> seq # Util.seqDelete v
