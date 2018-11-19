pragma solidity ^0.4.24;

import "./ERC20.sol";

contract RetreatEscrow {
    enum DepositStatus { Pending, Slashed, Challenged }

    enum VoteOptions { Yes, No, Abstain }

    event DepositCreated(string indexed name, address indexed depositer);
    event DepositSlashed(string indexed name);
    event SlashChallenged(string indexed name);
    event DepositRefunded(string indexed name);
    event DepositBurned(string indexed name);

    struct Deposit {
        address depositer;
        uint value;
        DepositStatus status;
        string name;
    }

    string[] public names;

    mapping(string => Deposit) public deposits;

    uint public numChallenges;
    mapping(string => uint) public voteCounts;
    mapping(string => mapping(string => bool)) alreadyVoted;
    mapping(string => uint) public numVotes;


    ERC20 public currency;
    uint public minDeposit;
    address public escrowManager;

    uint public depositPeriodEnd;
    uint public slashPeriodEnd;
    uint public challengePeriodEnd;
    uint public votingPeriodEnd;

    function RetreatEscrow(address _escrowManager, ERC20 _currency, uint _minDeposit, uint _depositPeriodEnd, uint _slashPeriodEnd, uint _challengePeriodEnd, uint _votingPeriodEnd) public {
        escrowManager = _escrowManager;
        currency = _currency;
        minDeposit = _minDeposit;

        depositPeriodEnd = _depositPeriodEnd;
        slashPeriodEnd = _slashPeriodEnd;
        challengePeriodEnd = _challengePeriodEnd;
        votingPeriodEnd = _votingPeriodEnd;
    }

    function deposit(address depositer, ERC20 currency, uint amount, string name) external depositPeriodOnly{
        require(currency == currency, "incorrect ERC20");
        require(amount >= minDeposit, "not enough deposit");
        require(currency.allowance(depositer, this) >= amount, "not enough ERC20 allowance");

        currency.transferFrom(depositer, this, amount);

        Deposit memory deposit = Deposit(depositer, amount, DepositStatus.Pending, name);

        deposits[name] = deposit;
        names.push(name);

        emit DepositCreated(name, depositer);
    }

    function slash(string name) external onlyEscrowManager slashPeriodOnly {
        Deposit deposit = deposits[name];
        require(deposit.status == DepositStatus.Pending, "can only slash pending deposits");
        deposit.status = DepositStatus.Slashed;

        emit DepositSlashed(deposit.name);
    }

    function challenge(string name) external challengePeriodOnly {
        Deposit deposit = deposits[name];
        require(deposit.status == DepositStatus.Slashed, "can only challenge slashed proposals");
        require(msg.sender == deposit.depositer, "can only challenge for your own deposit");
        
        deposit.status = DepositStatus.Challenged;

        numChallenges++;

        emit SlashChallenged(name);
    }

    function vote(string voter, string challenger, VoteOptions vote) external votingPeriodOnly {
        Deposit depositVoter = deposits[voter];
        require(depositVoter.depositer == msg.sender, "voter does not match msg sender");
        
        Deposit deposit = deposits[challenger];
        require(deposit.status == DepositStatus.Challenged, "can only vote on challenged slashes");

        require(!alreadyVoted[challenger][voter], "cannot double vote");
        alreadyVoted[challenger][voter] = true;

        numVotes[voter]++;

        if (vote == VoteOptions.Yes) {
            voteCounts[challenger]++;
        } else if (vote == VoteOptions.No) {
            voteCounts[challenger]--;
        }
    }

    function refundAndBurn() external refundPeriodOnly {
        for (uint i = 0; i < names.length; i++) {
            string name = names[i];
            Deposit deposit = deposits[name];

            if (numVotes[name] != numChallenges) {
                emit DepositBurned(name);
            } else {
                if (deposit.status == DepositStatus.Pending) {
                    currency.transfer(deposit.depositer, deposit.value);
                    emit DepositRefunded(name);
                } else if (deposit.status == DepositStatus.Slashed) {
                    emit DepositBurned(name);
                } else {
                    if (voteCounts[name] >= 0) {
                        currency.transfer(deposit.depositer, deposit.value);
                        emit DepositRefunded(name);
                    } else {
                        emit DepositBurned(name);
                    }
                }
            }
        }
        selfdestruct(escrowManager);
    }


    // Fallback
    function() external {}

    // ---------------------------------------------------------
    // Modifiers

    modifier onlyEscrowManager() {
        require(msg.sender == escrowManager, "can only be called by escrow manager");
        _;
    }

    modifier depositPeriodOnly() {
        require(block.timestamp <= depositPeriodEnd, "deposit period is over");
        _;
    }

    modifier slashPeriodOnly() {
        require(block.timestamp > depositPeriodEnd, "slash period has not yet begun");
        require(block.timestamp <= slashPeriodEnd, "slash period is over");
        _;
    }

    modifier challengePeriodOnly() {
        require(block.timestamp > slashPeriodEnd, "challenge period has not yet begun");
        require(block.timestamp <= challengePeriodEnd, "challenge period is over");
        _;
    }

    modifier votingPeriodOnly() {
        require(block.timestamp > slashPeriodEnd, "voting period has not yet begun");
        require(block.timestamp <= votingPeriodEnd, "voting period is over");
        _;
    }

    modifier refundPeriodOnly() {
        require(block.timestamp > votingPeriodEnd, "refund period has not yet begun");
        _;
    }
}