module Game.UnitPlacement where

import qualified Data.Char as C
import qualified Data.List as L
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.Vector as V
import FileParser.Types
import Game.BoardGeneration
import Game.StatBlockGeneration

data MobUnit = MobUnit
  { name :: String,
    team :: String,
    identifier :: Int,
    position :: Coordinate,
    statBlock :: MobStatBlock,
    ai :: Action,
    targets :: [Int]
  }
  deriving (Show)

data PlayerUnit = PlayerUnit
  { playerName :: String,
    playerTeam :: String,
    playerIdentifier :: Int,
    playerPosition :: Coordinate,
    playerStatBlock :: PlayerStatBlock
  }
  deriving (Show)

data Unit
  = Mob MobUnit
  | Player PlayerUnit
  deriving (Show)

-- ~ Rough print of the units vector used for debugging purposes.
printUnits :: V.Vector Unit -> IO ()
printUnits units = do
  V.mapM_ (\unit -> putStrLn (show unit)) units
  putStrLn ""

-- ~ Determines if a unit is still alive.
unitIsAlive :: Unit -> Bool
unitIsAlive (Mob unit) = healthPoints (statBlock unit) >= 0
unitIsAlive (Player player) = alive (playerStatBlock player)

-- ~ Returns the name of a unit.
getName :: Unit -> String
getName (Mob unit) = name unit
getName (Player player) = playerName player

-- ~ Returns the team name of a unit.
getTeam :: Unit -> String
getTeam (Mob unit) = team unit
getTeam (Player player) = playerTeam player

-- ~ Returns the identifier of a unit.
getIdentifier :: Unit -> Int
getIdentifier (Mob unit) = identifier unit
getIdentifier (Player player) = playerIdentifier player

-- ~ Returns the position on the board of a unit.
getPosition :: Unit -> Coordinate
getPosition (Mob unit) = position unit
getPosition (Player player) = playerPosition player

-- ~ Returns the action sequence of a non-playable unit.
getAI :: Unit -> Action
getAI (Mob unit) = ai unit

-- ~ Returns the target history of a non-playable unit.
getTargets :: Unit -> [Int]
getTargets (Mob unit) = targets unit

-- ~ Returns the statblock of a non-playable unit.
getMobStatBlock :: Unit -> MobStatBlock
getMobStatBlock (Mob unit) = statBlock unit

-- ~ Returns the initiative modifier of a unit.
getInitiative :: Unit -> Int
getInitiative (Mob unit) = initiative (statBlock unit)
getInitiative (Player player) = playerInitiative (playerStatBlock player)

-- ~ Updates the position of a unit in the board.
updateUnitPosition :: Unit -> Coordinate -> Unit
updateUnitPosition (Mob unit) newPosition = Mob (unit {position = newPosition})
updateUnitPosition (Player player) newPosition = Player (player {playerPosition = newPosition})

-- ~ Sets a unit as dead.
updateUnitDead :: Unit -> Unit
updateUnitDead (Mob unit) = Mob (unit {statBlock = (statBlock unit) {healthPoints = -1}})
updateUnitDead (Player player) = Player (player {playerStatBlock = (playerStatBlock player) {alive = False}})

-- ~ Checks that there are no duplicate names in the AI actions list.
buildAImap :: [AIInput] -> (M.Map String Action) -> Either String (M.Map String Action)
buildAImap [] aiMap = Right aiMap
buildAImap ((name, ai) : ais) aiMap =
  if M.member name aiMap
    then Left ("Dupĺicate AI name " ++ name ++ ".")
    else buildAImap ais (M.insert name ai aiMap)

-- ~ Verifies the names of the listed AI actions.
checkAInames :: [AIInput] -> Either String (M.Map String Action)
checkAInames ais = buildAImap ais M.empty

-- ~ Checks that no team names are repeated.
duplicateTeamName :: [Team] -> S.Set String -> Maybe String
duplicateTeamName [] _ = Nothing
duplicateTeamName ((name, _) : ts) set =
  if S.member name set
    then Just ("Duplicate team name " ++ name ++ ".")
    else duplicateTeamName ts (S.insert name set)

-- ~ Adds an offset to the coordinates of all units in all teams.
shiftUnits :: [Team] -> Coordinate -> [Team]
shiftUnits teams offset =
  map
    ( \(teamName, units) ->
        ( teamName,
          map
            (\(name, ai, n, positions) -> (name, ai, n, map (\(col, row) -> (col + fst offset, row + snd offset)) positions))
            units
        )
    )
    teams

-- ~ Checks that all units in the team have a defined statblock.
invalidNameInTeam :: [(String, String, Int, [Coordinate])] -> (M.Map String StatBlock) -> Maybe String
invalidNameInTeam [] _ = Nothing
invalidNameInTeam ((name, _, _, _) : us) statMap =
  if M.member name statMap
    then invalidNameInTeam us statMap
    else Just ("Unknown unit name " ++ name ++ " in team ")

-- ~ Checks if all non-playable units in a team have an existing AI assigned.
invalidAIInTeam :: [(String, String, Int, [Coordinate])] -> (M.Map String StatBlock) -> (M.Map String Action) -> Maybe String
invalidAIInTeam [] _ _ = Nothing
invalidAIInTeam ((name, ai, _, _) : us) statMap aiMap =
  case statMap M.! name of
    MobStat _ ->
      if ai == ""
        then Just ("Missing AI name for unit " ++ name ++ " in team ")
        else
          if M.member ai aiMap
            then invalidAIInTeam us statMap aiMap
            else Just ("Unknown AI name " ++ ai ++ " in team ")
    PlayerStat _ ->
      if ai /= ""
        then Just ("Player controlled unit " ++ name ++ " does not use an AI in team ")
        else invalidAIInTeam us statMap aiMap

-- ~ Places a list of units in the board.
placeTeamUnits :: Board Tile -> [Coordinate] -> Int -> Either String (Board Tile)
placeTeamUnits board [] _ = Right board
placeTeamUnits board ((col, row) : cs) index =
  if not (validCoord board (col, row))
    then Left ("Coordinate " ++ (show (col, row)) ++ " out of bounds in unit ")
    else case (board V.! row) V.! col of
      Empty -> placeTeamUnits (updateBoard board (col, row) (Unit index)) cs (index + 1)
      _ -> Left ("Invalid unit placement " ++ (show (col, row)) ++ " in unit ")

-- ~ Place the units in the team on the board. Each unit is referenced by
-- ~ their index in the units vector.
placeTeam :: Board Tile -> [(String, String, Int, [Coordinate])] -> Int -> Either String (Board Tile)
placeTeam board [] _ = Right board
placeTeam board ((name, ai, amount, positions) : us) index =
  if amount /= length positions
    then Left ("Mismatched amount and coordinate amount in unit " ++ name ++ " in team ")
    else case placeTeamUnits board positions index of
      Left errorMsg -> Left (errorMsg ++ name ++ " in team ")
      Right newBoard -> placeTeam newBoard us (index + length positions)

-- ~ Builds a unit from all the necessary values.
buildUnit :: (M.Map String StatBlock) -> (M.Map String Action) -> String -> String -> String -> Int -> Coordinate -> Unit
buildUnit statMap aiMap name team ai idNum position =
  case statMap M.! name of
    MobStat statBlock -> Mob MobUnit {name = name, team = team, identifier = idNum, position = position, statBlock = statBlock, ai = aiMap M.! ai, targets = []}
    PlayerStat statBlock -> Player PlayerUnit {playerName = name, playerTeam = team, playerIdentifier = idNum, playerPosition = position, playerStatBlock = statBlock}

-- ~ Creates a list of all the described units in the team.
-- ~ Each unit gets an ID, which is a number that differentiates it from all the
-- ~ other units with the same name in their team. The maximum ID for each name
-- ~ is stored in the idMap.
buildTeamList :: (M.Map String StatBlock) -> (M.Map String Action) -> String -> [(String, String, Int, [Coordinate])] -> (M.Map String Int) -> [Unit]
buildTeamList _ _ _ [] _ = []
buildTeamList statMap aiMap team ((name, ai, amount, positions) : us) idMap =
  let baseID = if M.member name idMap then idMap M.! name else 1
      (newID, units) =
        L.mapAccumL
          (\idNum pos -> (idNum + 1, buildUnit statMap aiMap name team ai idNum pos))
          baseID
          positions
   in units ++ buildTeamList statMap aiMap team us (M.insert name newID idMap)

-- ~ Creates all the described units in the team.
buildTeam :: (M.Map String StatBlock) -> (M.Map String Action) -> String -> [(String, String, Int, [Coordinate])] -> V.Vector Unit
buildTeam statMap aiMap team units = V.fromList (buildTeamList statMap aiMap team units M.empty)

-- ~ Creates and places each team's units on the board, returning it
-- ~ as well as the vector of all placed units.
createUnits :: Board Tile -> (M.Map String StatBlock) -> (M.Map String Action) -> [Team] -> V.Vector Unit -> Either String (Board Tile, V.Vector Unit)
createUnits board _ _ [] units = Right (board, units)
createUnits board statMap aiMap ((teamName, teamUnits) : ts) units = case invalidNameInTeam teamUnits statMap of
  Just errorMsg -> Left (errorMsg ++ teamName ++ ".")
  Nothing -> case invalidAIInTeam teamUnits statMap aiMap of
    Just errorMsg -> Left (errorMsg ++ teamName ++ ".")
    Nothing -> case placeTeam board teamUnits (length units) of
      Left errorMsg -> Left (errorMsg ++ teamName ++ ".")
      Right newBoard -> createUnits newBoard statMap aiMap ts (units V.++ buildTeam statMap aiMap teamName teamUnits)

-- ~ Creates the units given the descriptions of each team's units and AIs. Then, places them on the board.
placeUnits :: Board Tile -> Coordinate -> (M.Map String StatBlock) -> (M.Map String Action) -> [Team] -> Either String (Board Tile, V.Vector Unit)
placeUnits board offset units ais teams = case duplicateTeamName teams S.empty of
  Just errorMsg -> Left errorMsg
  Nothing -> createUnits board units ais (shiftUnits teams offset) V.empty
