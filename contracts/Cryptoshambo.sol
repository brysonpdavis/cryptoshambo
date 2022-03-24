//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Cryptoshambo is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    event WagerCreated(address indexed _poster, uint indexed _id, uint _amount);

    event WagerCancelled(address indexed _poster, uint indexed _id);

    event Completed(address indexed _poster, address indexed _challenger, uint indexed _id, address winner, uint _amount);

    enum RockPaperOrScissors{
        ROCK, 
        PAPER, 
        SCISSORS,
        NULL
    }

    enum Status {
        UNINSTANTIATED,
        COMMITTED,
        COMPLETED,
        CANCELLED,
        ERROR
    }

    enum Decision {
        PLAYER1,
        PLAYER2,
        TIE,
        ERROR
    }

    struct Wager{
        uint id;
        address payable poster;
        uint amount;
        RockPaperOrScissors choice; // TODO: change to make choice encrypted
        Status status;
    }

    struct Challenge{
        uint id;
        address payable challenger;
        RockPaperOrScissors choice; // TODO: change to make encrypted choice
    }

    struct Result{
        uint id;
        address payable poster;
        address payable challenger;
        uint amount;
        RockPaperOrScissors posterChoice;
        RockPaperOrScissors challengerChoice;
        address payable winner;
        Status status;
    }

    mapping(uint => Wager) internal _wagers;

    mapping(address => uint[]) internal _userToTransactionIds;

    Result[] internal _resultHistory;

    Counters.Counter internal _transactionId;

    Counters.Counter internal _activeWagers;

    uint internal _staked;

    constructor() {
        _staked = 0;
    }

    function postWager(uint _amount, RockPaperOrScissors _choice) payable external nonReentrant {
        // require amount expected == amount paid
        require(msg.value == _amount, "amount sent is not the amount required");
        // require a non-zero amount wagered
        require(_amount > 0, "must be a non-zero amount");
        // create a wager struct, 
        Wager memory newWager = Wager(_transactionId.current(), payable(msg.sender), _amount, _choice, Status.COMMITTED);
        // add wager id to '_userToTransactionIds', 
        _userToTransactionIds[msg.sender].push(_transactionId.current());
        // add wager to _wagers,
        _wagers[_transactionId.current()] = newWager;
        // increment the wager id, 
        _transactionId.increment();
        // increment the number of active wagers
        _activeWagers.increment();
        // store ether sent
        _staked += _amount;

        emit WagerCreated(msg.sender, newWager.id, _amount);
    }

    function cancelWager(uint _id) external nonReentrant {
        // make sure the address cancelling is the original poster of the wager
        require(_wagers[_id].poster == msg.sender, "unable to cancel, must be the original poster");

        emit WagerCancelled(_wagers[_id].poster, _id);

        // create result struct with CANCELLED status and add to history
        // challenger and winner addresses set to zero
        createResult(
            _wagers[_id], 
            Challenge(0, payable(address(0)), RockPaperOrScissors.NULL), 
            payable(address(0)), 
            Status.CANCELLED
        );

        _staked -= _wagers[_id].amount;
        
        // delete the wager struct from the _wagers mapping
        delete _wagers[_id];
        // return stored ether to poster
        _wagers[_id].poster.transfer(_wagers[_id].amount);

        _activeWagers.decrement();
    }

    function callWager(uint _id, RockPaperOrScissors _choice) payable external nonReentrant {
        Wager memory wager = _wagers[_id];
        // make sure wager hasn't been consumed yet
        require(wager.status == Status.COMMITTED, "wager's status is not 'COMMITTED'");
        // make sure amount sent is the same amount that the poster wagered
        require(wager.amount == msg.value, "amount sent not the same as the wagered amount");
        // make sure challenger is not also the poster
        require(wager.poster != msg.sender, "challenger must be a different address from the one that posted the wager");

        // create Challenge struct
        Challenge memory challenge = Challenge(_id, payable(msg.sender), _choice);

        Decision decision = decideMatch(wager, challenge);

        // same choice case
        if (decision == Decision.TIE) {
            // create Result struct and add it to history with 0 address for winner and completed status
            createResult(wager, challenge, payable(address(0)), Status.COMPLETED);
            // challenger gets their tokens back
            challenge.challenger.transfer(msg.value);
            // poster gets their tokens back too
            wager.poster.transfer(wager.amount);
        }

        if (decision == Decision.PLAYER1) {
            // TODO: emit event for poster wins case
            // create result struct with COMPLETED status and add it to history
            createResult(wager, challenge, wager.poster, Status.COMPLETED);
            // poster gets the tokens
            wager.poster.transfer(msg.value + wager.amount);
        }

        if (decision == Decision.PLAYER2) {
            // TODO: emit event for challenger wins case
            // create result struct with COMPLETED status and add it to history
            createResult(wager, challenge, challenge.challenger, Status.COMPLETED);
            // challenger gets the tokens
            challenge.challenger.transfer(msg.value + wager.amount);
        }

        if (decision == Decision.ERROR) {
            // TODO: emit event for error case
            // create result struct with ERROR status and add it to history
            createResult(wager, challenge, payable(address(0)), Status.ERROR);
            // same thing happens as if it were a tie
            // both parties get tokens back
            wager.poster.transfer(wager.amount);
            challenge.challenger.transfer(msg.value);
        }

        _staked -= wager.amount + msg.value;

        _activeWagers.decrement();

        // delete wager from mapping to save storage
        delete _wagers[_id];
    }

    function decideMatch(Wager memory _wager, Challenge memory _challenge) internal pure returns (Decision) {
        // put decryption here... later
        RockPaperOrScissors choice1 = _wager.choice;
        RockPaperOrScissors choice2 = _challenge.choice;

        if (choice1 == choice2) {
            return Decision.TIE;
        }

        if (choice1 == RockPaperOrScissors.ROCK) {
            if (choice2 == RockPaperOrScissors.SCISSORS) {
                return Decision.PLAYER1;
            }
            if (choice2 == RockPaperOrScissors.PAPER) {
                return Decision.PLAYER2;
            }
        }

        if (choice1 == RockPaperOrScissors.PAPER) {
            if (choice2 == RockPaperOrScissors.ROCK) {
                return Decision.PLAYER1;
            }
            if (choice2 == RockPaperOrScissors.SCISSORS) {
                return Decision.PLAYER2;
            }
        }

        if (choice1 == RockPaperOrScissors.SCISSORS) {
            if (choice2 == RockPaperOrScissors.PAPER) {
                return Decision.PLAYER1;
            }
            if (choice2 == RockPaperOrScissors.ROCK) {
                return Decision.PLAYER2;
            }
        }

        // if we've reached this point, something is wrong
        return Decision.ERROR;
    }

    function createResult(Wager memory _wager, Challenge memory _challenge, address payable _winner, Status _status) internal {
        Result memory r = Result(
            _wager.id,
            _wager.poster,
            _challenge.challenger,
            _wager.amount,
            _wager.choice, // need to change later... encryption
            _challenge.choice, // need to change later
            _winner,
            _status
        );

        _resultHistory.push(r);

        emit Completed(_wager.poster, _challenge.challenger, _wager.id, _winner, _wager.amount);
    }

    function withdraw() external onlyOwner {
        // TODO: write withdraw function

    }

    function getUsersWagers() internal view returns(Wager[] memory) {
        uint z = 0;

        uint[] memory ids = _userToTransactionIds[msg.sender];

        for (uint i = 0; i < ids.length; i++) {
            if (_wagers[ids[i]].status == Status.COMMITTED) {
                z++;
            }
        }


        Wager[] memory ws = new Wager[](z);

        for (uint i = 0; i < ids.length; i++) {
            if (_wagers[ids[i]].status == Status.COMMITTED) {
                ws[z] = _wagers[ids[i]];
                z++;
            }
        }

        return ws;
    }

    function getUsersHistory() internal view returns(Result[] memory) {
        uint z = 0;

        Result memory curResult;
        
        for (uint i = 0; i < _resultHistory.length; i++) {
            curResult = _resultHistory[i];

            if (curResult.poster == msg.sender || curResult.challenger == msg.sender) {
                z++;
            }
        }

        Result[] memory rs = new Result[](z);

        uint y = 0;

        for(uint i = 0; i < _resultHistory.length; i++) {
            curResult = _resultHistory[i];

            if (curResult.poster == msg.sender || curResult.challenger == msg.sender) {
                rs[y] = curResult;
                y++;
            }
        }

        return rs;
    }

    function getUsersTransactions() external view returns (Wager[] memory,Result[] memory) {
        return(getUsersWagers(), getUsersHistory());
    }

    function getLatestResults() external view returns (Result[] memory) {
        // TODO: implement
    }

    function getLatestWagers() external view returns (Wager[] memory) {
        Wager[] memory ws = new Wager[](_activeWagers.current() > 10 ? 10 : _activeWagers.current());
        uint y = ws.length;

        for (uint i = 0; i < _transactionId.current() && y > 0; i++) {
            if (_wagers[i].status == Status.COMMITTED) {
                ws[y - 1] = _wagers[i];
                y--;
            }
        }

        return ws;
    }

    function getTotalAmountStaked() external view returns(uint) {
        return _staked;
    }

    // function remove(uint index) public{
    //     for(uint i = index; i < firstArray.length-1; i++){
    //         firstArray[i] = firstArray[i+1];      
    //     }
    //     firstArray.pop();
    // }

    receive() external payable {}

    fallback() external payable {}

}
