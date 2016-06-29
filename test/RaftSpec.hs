{-# LANGUAGE DuplicateRecordFields #-}
module RaftSpec (spec) where

import Prelude hiding (log)
import Test.Hspec
import Raft
import Raft.Types
import Raft.Types (Reply(..))

spec :: Spec
spec = do
    let defaultData = ClientData 0 Nothing [] 0 0 [] [] :: ClientData Int

    describe "becomeCandidate" $ do
        let myNodeId = 1
            allNodes = 0

        it "works" $ do
            let dat = defaultData { currentTerm = 3
                                  , votedFor = Just 2
                                  , log = [(1, 1), (3, 3)]
                                  , commitIndex = 1
                                  , lastApplied = 0
                                  }

            let ((toNode, reply), state, dat') = becomeCandidate myNodeId dat
            currentTerm dat' `shouldBe` 4
            votedFor dat' `shouldBe` Just myNodeId
            log dat' `shouldBe` log dat
            commitIndex dat' `shouldBe` commitIndex dat
            lastApplied dat' `shouldBe` lastApplied dat
            state `shouldBe` Candidate
            toNode `shouldBe` allNodes
            reply `shouldBe` RequestVoteMsg RequestVoteRPC
                                            { term = 4
                                            , candidateId = myNodeId
                                            , lastLogIndex = 2
                                            , lastLogTerm = 3
                                            }

    describe "appendLog" $ do
        let defaultRpc = AppendLogRPC 0 0 0 0 [] 0
            fromNode = 0

        it "ignores rpc with lower term" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 2, prevLogTerm = 2, prevLogIndex = 2}

            let ((toNode, AppendLogRPCReply 3 False), Follower, dat') = appendLog Follower rpc 0 dat
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 False), Candidate, dat') = appendLog Candidate rpc 0 dat
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 False), Leader, dat') = appendLog Leader rpc 0 dat
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

        it "ignores rpc with invalid prevLog" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (1, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 1}

            let ((toNode, AppendLogRPCReply 3 False), Follower, dat') = appendLog Follower rpc fromNode dat
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 False), Follower, dat') = appendLog Candidate rpc fromNode dat
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 1, prevLogIndex = 3}

            let ((toNode, AppendLogRPCReply 3 False), Follower, dat') = appendLog Follower rpc fromNode dat
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 False), Follower, dat') = appendLog Candidate rpc fromNode dat
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

        it "appends new entries" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)]}

            let ((toNode, AppendLogRPCReply 3 True), Follower, dat') = appendLog Follower rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 True), state', dat') = appendLog Candidate rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower
            toNode `shouldBe` fromNode

        it "overwrites conflicting entries" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2), (3, 0)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)]}

            let ((toNode, AppendLogRPCReply 3 True), Follower, dat') = appendLog Follower rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 True), state', dat') = appendLog Candidate rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower
            toNode `shouldBe` fromNode

        it "sets commitIndex" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)], leaderCommit = 2}

            let ((toNode, AppendLogRPCReply 3 True), Follower, dat') = appendLog Follower rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            commitIndex dat' `shouldBe` 2
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 True), state', dat') = appendLog Candidate rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower
            commitIndex dat' `shouldBe` 2
            toNode `shouldBe` fromNode

            let rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)], leaderCommit = 7}
            let ((toNode, AppendLogRPCReply 3 True), Follower, dat') = appendLog Follower rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            commitIndex dat' `shouldBe` 3
            toNode `shouldBe` fromNode

            let ((toNode, AppendLogRPCReply 3 True), state', dat') = appendLog Candidate rpc fromNode dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower
            commitIndex dat' `shouldBe` 3
            toNode `shouldBe` fromNode

    describe "vote" $ do
        let defaultRpc = RequestVoteRPC 0 0 0 0
            fromNode = 0

        it "rejects lower term" $ do
            let dat = defaultData {currentTerm = 2}
                rpc = defaultRpc {term = 1} :: RequestVoteRPC

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Follower rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Candidate rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Candidate
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Leader rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

        it "rejects if already voted in this term" $ do
            let dat = defaultData {currentTerm = 2, votedFor = Just 1}
                rpc = defaultRpc {term = 2, candidateId = 2} :: RequestVoteRPC

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Follower rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Candidate rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Candidate
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

        it "grants if already voted for this candidate in this term" $ do
            let dat = defaultData {currentTerm = 2, votedFor = Just 1}
                rpc = defaultRpc {term = 2, candidateId = 1} :: RequestVoteRPC

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Follower rpc fromNode dat
            granted' `shouldBe` True
            state' `shouldBe` Follower
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Candidate rpc fromNode dat
            granted' `shouldBe` True
            state' `shouldBe` Candidate
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

        it "grants if haven't voted yet and candidate's log is up-to-date" $ do
            let dat = defaultData { currentTerm = 2, votedFor = Nothing
                                  , Raft.Types.log = [(1, 1), (2, 2)] }
                rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 3
                                 , lastLogIndex = 1} :: RequestVoteRPC

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Follower rpc fromNode dat
            granted' `shouldBe` True
            state' `shouldBe` Follower
            dat' `shouldBe` dat { votedFor = Just 1 }
            toNode `shouldBe` fromNode

            -- NOTE: Candidate will always have voted (for itself) in current term

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Leader rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 3
                                 , lastLogIndex = 2} :: RequestVoteRPC

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Follower rpc fromNode dat
            granted' `shouldBe` True
            state' `shouldBe` Follower
            dat' `shouldBe` dat { votedFor = Just 1 }
            toNode `shouldBe` fromNode

            -- NOTE: Candidate will always have voted (for itself) in current term

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Leader rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

        it "rejects if haven't voted yet but candidate's log is not up-to-date" $ do
            let dat = defaultData { currentTerm = 2, votedFor = Nothing
                                  , Raft.Types.log = [(1, 1), (2, 2)] }
                rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 1
                                 , lastLogIndex = 3} :: RequestVoteRPC

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Follower rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            -- NOTE: Candidate will always have voted (for itself) in current term

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Leader rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            let rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 2
                                 , lastLogIndex = 1} :: RequestVoteRPC

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Follower rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode

            -- NOTE: Candidate will always have voted (for itself) in current term

            let ((toNode, RequestVoteRPCReply 2 granted'), state', dat') = vote Leader rpc fromNode dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat
            toNode `shouldBe` fromNode
