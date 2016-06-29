{-# LANGUAGE RecordWildCards, ScopedTypeVariables #-}
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


raftFSM :: State -> Event a -> ClientData a -> (Reply, State, ClientData a)
raftFSM Leader ElectionTimeout _ = error "ElectionTimeout in Leader state"
raftFSM _ ElectionTimeout dat = undefined -- TODO

raftFSM Follower  Heartbeat _ = error "Heartbeat in Follower state"
raftFSM Candidate Heartbeat _ = error "Heartbeat in Candidate state"
raftFSM Leader    Heartbeat dat = undefined

raftFSM state (AppendLog rpc) dat = appendLog state rpc dat
raftFSM state (RequestVote rpc) dat = vote state rpc dat


appendLog :: State -> AppendLogRPC a -> ClientData a -> (Reply, State, ClientData a)
appendLog state AppendLogRPC{..} dat@ClientData{..} =
    maybe failure id $
        when (term >= currentTerm) $ do
            checkPrevLog prevLogTerm prevLogIndex log
            let log' = addEntriesToLog prevLogIndex entries log
                reply = AppendLogRPCReply currentTerm True
                commitIndex' = if leaderCommit > commitIndex
                                then min leaderCommit $ fromIntegral $ length log'
                                else commitIndex
                dat' = dat { Raft.Types.log = log', commitIndex = commitIndex' }
            return (reply, state', dat')

    where
        actualTerm = max term currentTerm
        state' = if term >= currentTerm then Follower else state
        failure = (AppendLogRPCReply actualTerm False, state', dat {currentTerm = actualTerm})

        checkPrevLog :: Term -> Index -> Log a -> Maybe ()
        checkPrevLog prevLogTerm prevLogIndex log = do
            (term, _) <- index log prevLogIndex
            if term == prevLogTerm then Just () else Nothing

        addEntriesToLog :: Index -> Log a -> Log a -> Log a
        addEntriesToLog startIndex entries log = genericTake startIndex log ++ entries


vote :: State -> RequestVoteRPC -> ClientData a -> (Reply, State, ClientData a)
vote state RequestVoteRPC{..} dat@ClientData{..} = maybe failure id $ do
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
        result reply dat = (reply, state', dat { currentTerm = actualTerm })
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
type CommQueue = TQueue (NodeId, Reply)
type NodeInfo = (Int, Int)--SockAddr, PortNumber)
type Node = (NodeId, NodeInfo)

initialStateRaftFSM :: (State, ClientData a)
initialStateRaftFSM = (Follower, ClientData 0 Nothing [] 0 0 [] [])

runRaftFSM :: EventQueue a -> CommQueue -> IO ()
runRaftFSM queue commQueue = flip evalStateT initialStateRaftFSM $ forever $ do
    (fromNode, event) <- liftIO $ atomically $ readTQueue queue
    (state, dat) <- get
    let (reply, state', dat') = raftFSM state event dat
    liftIO $ transition state state'
    liftIO $ atomically $ writeTQueue commQueue (fromNode, reply)
    put (state', dat')

runCommProcess :: EventQueue a -> CommQueue -> Node -> [Node] -> IO ()
runCommProcess myNode = undefined

runRaftNode :: Node -> [Node] -> IO ()
runRaftNode myNode nodes = do
    eventQueue <- atomically $ newTQueue
    commQueue <- atomically $ newTQueue
    commThread <- forkIO $ runCommProcess eventQueue commQueue myNode nodes
    runRaftFSM eventQueue commQueue

