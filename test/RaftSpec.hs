{-# LANGUAGE DuplicateRecordFields #-}
module RaftSpec (spec) where

import Test.Hspec
import Raft
import Raft.Types
import Raft.Types (Reply(..))

spec :: Spec
spec = do
    let defaultData = ClientData 0 Nothing [] 0 0 [] [] :: ClientData Int

    describe "appendLog" $ do
        let defaultRpc = AppendLogRPC 0 0 0 0 [] 0

        it "ignores rpc with lower term" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 2, prevLogTerm = 2, prevLogIndex = 2}

            let (AppendLogRPCReply 3 False, Follower, dat') = appendLog Follower rpc dat
            dat' `shouldBe` dat

            let (AppendLogRPCReply 3 False, Candidate, dat') = appendLog Candidate rpc dat
            dat' `shouldBe` dat

            let (AppendLogRPCReply 3 False, Leader, dat') = appendLog Leader rpc dat
            dat' `shouldBe` dat

        it "ignores rpc with invalid prevLog" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (1, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 1}

            let (AppendLogRPCReply 3 False, Follower, dat') = appendLog Follower rpc dat
            dat' `shouldBe` dat

            let (AppendLogRPCReply 3 False, Follower, dat') = appendLog Candidate rpc dat
            dat' `shouldBe` dat

            let rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 1, prevLogIndex = 3}

            let (AppendLogRPCReply 3 False, Follower, dat') = appendLog Follower rpc dat
            dat' `shouldBe` dat

            let (AppendLogRPCReply 3 False, Follower, dat') = appendLog Candidate rpc dat
            dat' `shouldBe` dat

        it "appends new entries" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)]}

            let (AppendLogRPCReply 3 True, Follower, dat') = appendLog Follower rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]

            let (AppendLogRPCReply 3 True, state', dat') = appendLog Candidate rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower

        it "overwrites conflicting entries" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2), (3, 0)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)]}

            let (AppendLogRPCReply 3 True, Follower, dat') = appendLog Follower rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]

            let (AppendLogRPCReply 3 True, state', dat') = appendLog Candidate rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower

        it "sets commitIndex" $ do
            let dat = defaultData {currentTerm = 3, Raft.Types.log = [(1, 1), (2, 2)]}
                rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)], leaderCommit = 2}

            let (AppendLogRPCReply 3 True, Follower, dat') = appendLog Follower rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            commitIndex dat' `shouldBe` 2

            let (AppendLogRPCReply 3 True, state', dat') = appendLog Candidate rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower
            commitIndex dat' `shouldBe` 2

            let rpc = (defaultRpc :: AppendLogRPC Int) {term = 3, prevLogTerm = 2, prevLogIndex = 2, entries = [(3, 3)], leaderCommit = 7}
            let (AppendLogRPCReply 3 True, Follower, dat') = appendLog Follower rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            commitIndex dat' `shouldBe` 3

            let (AppendLogRPCReply 3 True, state', dat') = appendLog Candidate rpc dat
            Raft.Types.log dat' `shouldBe` [(1,1), (2,2), (3,3)]
            state' `shouldBe` Follower
            commitIndex dat' `shouldBe` 3

    describe "vote" $ do
        let defaultRpc = RequestVoteRPC 0 0 0 0

        it "rejects lower term" $ do
            let dat = defaultData {currentTerm = 2}
                rpc = defaultRpc {term = 1} :: RequestVoteRPC

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Follower rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Candidate rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Candidate
            dat' `shouldBe` dat

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Leader rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat

        it "rejects if already voted in this term" $ do
            let dat = defaultData {currentTerm = 2, votedFor = Just 1}
                rpc = defaultRpc {term = 2, candidateId = 2} :: RequestVoteRPC

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Follower rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Candidate rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Candidate
            dat' `shouldBe` dat

        it "grants if already voted for this candidate in this term" $ do
            let dat = defaultData {currentTerm = 2, votedFor = Just 1}
                rpc = defaultRpc {term = 2, candidateId = 1} :: RequestVoteRPC

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Follower rpc dat
            granted' `shouldBe` True
            state' `shouldBe` Follower
            dat' `shouldBe` dat

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Candidate rpc dat
            granted' `shouldBe` True
            state' `shouldBe` Candidate
            dat' `shouldBe` dat

        it "grants if haven't voted yet and candidate's log is up-to-date" $ do
            let dat = defaultData { currentTerm = 2, votedFor = Nothing
                                  , Raft.Types.log = [(1, 1), (2, 2)] }
                rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 3
                                 , lastLogIndex = 1} :: RequestVoteRPC

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Follower rpc dat
            granted' `shouldBe` True
            state' `shouldBe` Follower
            dat' `shouldBe` dat { votedFor = Just 1 }

            -- NOTE: Candidate will always have voted (for itself) in current term

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Leader rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat

            let rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 3
                                 , lastLogIndex = 2} :: RequestVoteRPC

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Follower rpc dat
            granted' `shouldBe` True
            state' `shouldBe` Follower
            dat' `shouldBe` dat { votedFor = Just 1 }

            -- NOTE: Candidate will always have voted (for itself) in current term

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Leader rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat

        it "rejects if haven't voted yet but candidate's log is not up-to-date" $ do
            let dat = defaultData { currentTerm = 2, votedFor = Nothing
                                  , Raft.Types.log = [(1, 1), (2, 2)] }
                rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 1
                                 , lastLogIndex = 3} :: RequestVoteRPC

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Follower rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat

            -- NOTE: Candidate will always have voted (for itself) in current term

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Leader rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat

            let rpc = defaultRpc { term = 2, candidateId = 1, lastLogTerm = 2
                                 , lastLogIndex = 1} :: RequestVoteRPC

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Follower rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Follower
            dat' `shouldBe` dat

            -- NOTE: Candidate will always have voted (for itself) in current term

            let (RequestVoteRPCReply 2 granted', state', dat') = vote Leader rpc dat
            granted' `shouldBe` False
            state' `shouldBe` Leader
            dat' `shouldBe` dat
