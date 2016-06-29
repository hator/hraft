{-# LANGUAGE DuplicateRecordFields #-}
module Raft.Types where

import Data.Word (Word64)

data State = Follower | Candidate | Leader deriving (Eq, Show)

type Term = Word64
type Index = Word64
type NodeId = Word64
type LogEntry a = (Term, a)
type Log a = [LogEntry a]

data ClientData a = ClientData
    { currentTerm :: Term
    , votedFor :: Maybe NodeId
    , log :: Log a
    , commitIndex :: Index
    , lastApplied :: Index
    , nextIndex :: [Index]
    , matchIndex :: [Index]
    } deriving (Eq, Show)

data AppendLogRPC a = AppendLogRPC
    { term :: Term
    , leaderId :: NodeId
    , prevLogIndex :: Index
    , prevLogTerm :: Term
    , entries :: Log a
    , leaderCommit :: Index
    } deriving (Eq, Show)

data RequestVoteRPC = RequestVoteRPC
    { term :: Term
    , candidateId :: NodeId
    , lastLogIndex :: Index
    , lastLogTerm :: Term
    } deriving (Eq, Show)

data Event a
    = AppendLog (AppendLogRPC a)
    | RequestVote RequestVoteRPC
    | ElectionTimeout
    | Heartbeat
    deriving (Eq, Show)

data Message a
    = AppendLogRPCReply
        { term :: Term
        , success :: Bool
        }
    | RequestVoteRPCReply
        { term :: Term
        , voteGranted :: Bool
        }
    | RequestVoteMsg RequestVoteRPC
    | AppendLogMsg (AppendLogRPC a)
    deriving (Eq, Show)

type Reply a = (NodeId, Message a)
