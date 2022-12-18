// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.0 <0.9.0;

contract RockPaperScissors {
    enum Choice {
        Hided,
        Rock,
        Paper,
        Scissors
    }

    enum Stage {
        FirstCommit,
        SecondCommit,
        FirstReveal,
        SecondReveal,
        Distribute
    }

    struct CommitChoice {
        address playerAddress;
        bytes32 commitment;
        Choice choice;
    }

    event Commit(address player);
    event Reveal(address player, Choice choice);
    event Payout(address player, uint amount);

    uint public bet;
    uint public deposit;
    uint public revealSpan;

    mapping(Stage => CommitChoice) public players;
    uint public revealDeadline;
    Stage public stage = Stage.FirstCommit;

    constructor(uint _bet, uint _revealSpan) public {
        bet = _bet;
        revealSpan = _revealSpan;
    }

    modifier onlyCommitStage {
        require(stage == Stage.FirstCommit || stage == Stage.SecondCommit, "players have been played");
        _;
    }

    function commit(bytes32 commitment) public payable onlyCommitStage {
        uint commitAmount = bet + deposit;
        require(commitAmount >= bet, "overflow error");
        require(msg.value >= commitAmount, "value must be greater than commit amount");

        if(msg.value > commitAmount) {
            (bool success, ) = msg.sender.call{value: msg.value - commitAmount}("");
            require(success, "call failed");
        }

        players[stage] = CommitChoice(msg.sender, commitment, Choice.Hided);

        emit Commit(msg.sender);

        if(stage == Stage.FirstCommit) {
            stage = Stage.SecondCommit;
        } else {
            stage = Stage.FirstReveal;
        }
    }

    modifier onlyRevealStage {
        require(stage == Stage.FirstReveal || stage == Stage.SecondReveal, "not at reveal stage");
        _;
    }

    modifier onlySupportedChoice(Choice choice) {
        require(choice == Choice.Rock || choice == Choice.Paper || choice == Choice.Scissors, "invalid choice");
        _;
    }

    modifier onlyRegesteredPlayer(address a) {
        require(players[Stage.FirstCommit].playerAddress == a || players[Stage.SecondCommit].playerAddress == a, "unknown player");
        _;
    }

    function reveal(Choice choice, bytes32 blindingFactor) public onlyRevealStage onlySupportedChoice(choice) onlyRegesteredPlayer(msg.sender){
        Stage playerCommitStage;
        if (players[Stage.FirstCommit].playerAddress == msg.sender) {
            playerCommitStage = Stage.FirstCommit;
        } else { 
            playerCommitStage = Stage.SecondCommit; }

        CommitChoice storage commitChoice = players[playerCommitStage];

        require(keccak256(abi.encodePacked(msg.sender, choice, blindingFactor)) == commitChoice.commitment, "invalid hash");

        commitChoice.choice = choice;

        emit Reveal(msg.sender, commitChoice.choice);

        if(stage == Stage.FirstReveal) {
            revealDeadline = block.number + revealSpan;
            require(revealDeadline >= block.number, "overflow error");
            stage = Stage.SecondReveal;
        } else {
            stage = Stage.Distribute;
        }
    }

    modifier onlyDistributeOrDeadline {
        require(stage == Stage.Distribute || (stage == Stage.SecondReveal && revealDeadline <= block.number), "cannot yet distribute");
        _;
    }

    function distribute() public onlyDistributeOrDeadline {
        uint player0Payout;
        uint player1Payout;

        if(players[Stage.FirstCommit].choice == players[Stage.SecondCommit].choice) {
            player0Payout = bet;
            player1Payout = bet;
        }
        else if(players[Stage.FirstCommit].choice == Choice.Hided) {
            player1Payout = 2 * bet;
        }
        else if(players[Stage.SecondCommit].choice == Choice.Hided) {
            player0Payout = 2 * bet;
        }
        else if(players[Stage.FirstCommit].choice == Choice.Rock) {
            if(players[Stage.SecondCommit].choice == Choice.Paper) {
                player0Payout = 0;
                player1Payout = 2 * bet;
            }
            else if(players[Stage.SecondCommit].choice == Choice.Scissors) {
                player0Payout = 2 * bet;
                player1Payout = 0;
            }

        }
        else if(players[Stage.FirstCommit].choice == Choice.Paper) {
            if(players[Stage.SecondCommit].choice == Choice.Rock) {
                player0Payout = 2 * bet;
                player1Payout = 0;
            }
            else if(players[Stage.SecondCommit].choice == Choice.Scissors) {
                player0Payout = 0;
                player1Payout = 2 * bet;
            }
        }
        else if(players[Stage.FirstCommit].choice == Choice.Scissors) {
            if(players[Stage.SecondCommit].choice == Choice.Rock) {
                player0Payout = 0;
                player1Payout = 2 * bet;
            }
            else if(players[Stage.SecondCommit].choice == Choice.Paper) {
                player0Payout = 2 * bet;
                player1Payout = 0;
            }
        }

        if(player0Payout > 0) {
            (bool success, ) = players[Stage.FirstCommit].playerAddress.call{value: player0Payout}("");
            require(success, "call failed");
            emit Payout(players[Stage.FirstCommit].playerAddress, player0Payout);
        } else if (player1Payout > 0) {
            (bool success, ) = players[Stage.SecondCommit].playerAddress.call{value: player1Payout}("");
            require(success, "call failed");
            emit Payout(players[Stage.SecondCommit].playerAddress, player1Payout);
        }

        delete players[Stage.FirstCommit];
        delete players[Stage.SecondCommit];
        revealDeadline = 0;
        stage = Stage.FirstCommit;
    }
}