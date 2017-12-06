{-# LANGUAGE RecordWildCards, ScopedTypeVariables #-}

module Releases(run) where

import Control.Monad.Extra
import Control.Exception
import Control.DeepSeq
import Data.Char
import Text.HTML.TagSoup
import Data.Time.Format
import Data.Time.Clock
import Data.List.Extra hiding (list)
import System.Directory
import System.IO.Extra
import System.FilePath
import System.Time.Extra
import System.Process.Extra
import Arguments


run :: Arguments -> Maybe (IO ())
run Releases{..} = Just $ withCurrentDirectory "C:/neil/hexml" $ do
    dir <- getCurrentDirectory
    let project = takeFileName dir
    changes <- lines <$> readFile' "CHANGES.txt"
    changes <- forM changes $ \x -> do
        let isVersion x = x /= "" && all (isDigit ||^ (== '.')) x
        if not $ isVersion x then return x else do
            res <- wget wait $ "http://hackage.haskell.org/package/" ++ project ++ "-" ++ x
            let hackageFormat = "%a %b %e %k:%M:%S UTC %Y"
            let t :: UTCTime = parseTimeOrError True defaultTimeLocale hackageFormat $ fst $ breakOn " by " $ innerText $ drop 1 $ dropWhile (/= TagText "Uploaded") $ parseTags res
            let s = formatTime defaultTimeLocale (iso8601DateFormat Nothing) t
            return $ x ++ ", released " ++ s
    evaluate $ rnf changes
    writeFileBinary "CHANGES.txt" $ unlines changes


wget :: Double -> String -> IO String
wget wait x = withTempFile $ \t -> do
    putStr $ "wget " ++ x ++ " ... "
    system_ $ "wget " ++ x ++ " -O" ++ t ++ " --no-check-certificate --quiet"
    res <- readFile' t
    putStrLn "done"
    sleep wait
    return res