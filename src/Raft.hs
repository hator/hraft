{-# LANGUAGE RecordWildCards, ScopedTypeVariables, DuplicateRecordFields #-}
module Raft where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (atomically, newTVar)
import Control.Concurrent.STM.TQueue
import Control.Monad (forever, forM)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Strict (StateT(..), evalStateT, put, get)
import Data.List (genericTake)
import qualified Data.Map as M

import Raft.Types
import Util (when, index)


raftFSM :: State -> Event a -> NodeId -> ClientData a -> (Reply a, State, ClientData a)
raftFSM Leader ElectionTimeout _ _ = error "ElectionTimeout in Leader state"
raftFSM _ ElectionTimeout _ dat@ClientData{..} = ((0, undefined), Candidate, dat { currentTerm = currentTerm+1 }) -- TODO initialize new election

raftFSM Follower  Heartbeat _ _ = error "Heartbeat in Follower state"
raftFSM Candidate Heartbeat _ _ = error "Heartbeat in Candidate state"
raftFSM Leader    Heartbeat _ dat = undefined

raftFSM state (AppendLog rpc) from dat = appendLog state rpc from dat
raftFSM state (RequestVote rpc) from dat = vote state rpc from dat


appendLog :: State -> AppendLogRPC a -> NodeId -> ClientData a -> (Reply a, State, ClientData a)
appendLog state AppendLogRPC{..} from dat@ClientData{..} =
    maybe failure id $
        when (term >= currentTerm) $ do
            checkPrevLog prevLogTerm prevLogIndex log
            let log' = addEntriesToLog prevLogIndex entries log
                reply = AppendLogRPCReply currentTerm True
                commitIndex' = if leaderCommit > commitIndex
                                then min leaderCommit $ fromIntegral $ length log'
                                else commitIndex
                dat' = dat { Raft.Types.log = log', commitIndex = commitIndex' }
            return ((from, reply), state', dat')

    where
        actualTerm = max term currentTerm
        state' = if term >= currentTerm then Follower else state
        failure = ((from, AppendLogRPCReply actualTerm False), state', dat {currentTerm = actualTerm})

        checkPrevLog :: Term -> Index -> Log a -> Maybe ()
        checkPrevLog prevLogTerm prevLogIndex log = do
            (term, _) <- index log prevLogIndex
            if term == prevLogTerm then Just () else Nothing

        addEntriesToLog :: Index -> Log a -> Log a -> Log a
        addEntriesToLog startIndex entries log = genericTake startIndex log ++ entries


vote :: State -> RequestVoteRPC -> NodeId -> ClientData a -> (Reply a, State, ClientData a)
vote state RequestVoteRPC{..} from dat@ClientData{..} = maybe failure id $ do
    when (term >= currentTerm) $ do
        case votedFor of
            Nothing -> do
                checkNotALeaderForThisTerm state currentTerm term
                checkCandidateLog lastLogIndex lastLogTerm log
                return $ result grant $ dat{votedFor = Just candidateId}
            Just someId -> return $ if someId == candidateId
                                    then result grant dat
                                    else failure
    where
        actualTerm = max term currentTerm
        state' = if actualTerm == currentTerm then state else Follower
        grant = RequestVoteRPCReply actualTerm True
        reject = RequestVoteRPCReply actualTerm False
        result reply dat = ((from, reply), state', dat { currentTerm = actualTerm })
        failure = result reject dat

        checkNotALeaderForThisTerm state currentTerm term =
            when (term == currentTerm && not (state == Leader)) $ Just ()

        checkCandidateLog :: Index -> Term -> Log a -> Maybe ()
        checkCandidateLog lastLogIndex lastLogTerm log =
            let myLastLogTerm = index log myLastIndex
                myLastIndex = fromIntegral $ length log
            in case myLastLogTerm of
                Nothing -> Just ()
                Just (myLastLogTerm, _) ->
                    when (  lastLogTerm > myLastLogTerm
                         || lastLogTerm == myLastLogTerm && lastLogIndex >= myLastIndex)
                        $ Just ()


transition :: State -> State -> IO ()
transition Follower Candidate = undefined -- TODO restart election timer
transition Candidate Leader = undefined -- TODO cancel election timer, start heartbeat timer, send first heartbeat
transition Candidate Follower = undefined -- TODO cancel heartbeat timer, start election timer
transition Leader Follower = undefined -- TODO cancel heartbeat timer, start election timer
transition Leader Candidate = error "Invalid transition: Leader -> Candidate"
transition _ _ = return () -- do nothing


type EventQueue a = TQueue (NodeId, Event a)
type CommQueue a = TQueue (Reply a)
type NodeInfo = (Int, Int)--SockAddr, PortNumber)
type Node = (NodeId, NodeInfo)

initialStateRaftFSM :: (State, ClientData a)
initialStateRaftFSM = (Follower, ClientData 0 Nothing [] 0 0 [] [])

runRaftFSM :: EventQueue a -> CommQueue a -> IO ()
runRaftFSM queue commQueue = flip evalStateT initialStateRaftFSM $ forever $ do
    (fromNode, event) <- liftIO $ atomically $ readTQueue queue
    (state, dat) <- get
    let (replyTuple, state', dat') = raftFSM state event fromNode dat
    liftIO $ transition state state'
    liftIO $ atomically $ writeTQueue commQueue replyTuple
    put (state', dat')

runCommProcess :: EventQueue a -> CommQueue a -> Node -> [Node] -> IO ()
runCommProcess myNode = undefined

runRaftNode :: Node -> [Node] -> IO ()
runRaftNode myNode nodes = do
    eventQueue <- atomically $ newTQueue
    commQueue <- atomically $ newTQueue
    commThread <- forkIO $ runCommProcess eventQueue commQueue myNode nodes
    runRaftFSM eventQueue commQueue

