module Main where

import Game.PlayGame
import System.Environment

-- ~ Parses the input file and generates all the required data to start the game.
main :: IO ()
main = do
  input <- getArgs
  case input of
    [inFile] -> do
      inContent <- readFile inFile
      case setupGame inContent of
        Left errorMsg -> putStrLn ("ERROR: " ++ errorMsg)
        Right (board, units) -> playGame board units
    _ -> putStrLn "ERROR: Input file required."
