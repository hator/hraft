module Util where

import Control.Applicative (Alternative, empty)

when :: (Alternative f) => Bool -> f a -> f a
when True x = x
when False _ = empty

-- Safe list indexing
-- NOTE: 1-based indices
index :: Integral n => [a] -> n -> Maybe a
index [] _ = Nothing
index (x:_) 1 = Just x
index (_:xs) i = index xs (i-1)
