//  __          __                     betyourassets.xyz            __                              
// |  |--.-----|  |_.--.--.-----.--.--.----.---.-.-----.-----.-----|  |_.-----.  .--.--.--.--.-----.
// |  _  |  -__|   _|  |  |  _  |  |  |   _|  _  |__ --|__ --|  -__|   _|__ --|__|_   _|  |  |-- __|
// |_____|_____|____|___  |_____|_____|__| |___._|_____|_____|_____|____|_____|__|__.__|___  |_____|
//  

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./SafeMath.sol";

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256); 
    function safeTransferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function safeTransfer(address recipient, uint256 amount) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address); 
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

contract BetYourAssets {
    using SafeMath for uint256;

    // Constants for minimum and maximum bet timeouts
    uint public MIN_BET_TIMEOUT = 60 minutes;
    uint public MAX_BET_TIMEOUT = 365 days;

    address payable public owner;
    address payable public newOwner;

    // Percentage fees
    uint256 public feePercentage = 3;
    uint256 public middleManFeePercentage = 2;
    uint256 public cancellationFeePercentage = 5;

    // Maximum number of participants and flag for middleman participation
    uint8 public maxParticipants = 5;
    bool public allowMiddlemanParticipation = false;

    // Enum for bet status and bet type
    enum BetStatus { Ongoing, Resolved, Cancelled }
    enum BetType { Ether, ERC20, ERC721 }

    // Struct to represent a bet
    struct Bet {
        string title;
        uint256 betAmount;
        address middleMan;
        address payable[] participants;
        BetStatus status;
        uint256 creationTime;
        BetType betType;
        address tokenAddress;
        uint256 timeout;
        bool paused;
    }

    // Storage for bets and participant-related mappings
    mapping(uint256 => Bet) public bets;
    mapping(uint256 => mapping(address => uint256)) public participantTokenIds;
    mapping(uint256 => mapping(address => bool)) public hasJoined;
    uint256 public betCount = 0;

    // Events to track bet creation, joining, resolution, and cancellation
    event BetCreated(uint256 indexed betId, address indexed creator, uint256 betAmount, uint256 customTimeout);
    event BetJoined(uint256 indexed betId, address indexed participant);
    event BetResolved(uint256 indexed betId);
    event BetCancelled(uint256 indexed betId);

    // Modifier for owner-only functions
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this");
        _;
    }

    // Modifier for checks when a bet is not paused
    modifier whenBetNotPaused(uint256 betId) {
        require(!bets[betId].paused, "Bet is paused");
        _;
    }

    // Contract constructor, sets the owner
    constructor() {
        owner = payable(msg.sender);
    }

    // Owner Only Functions

    // Function to set the maximum number of participants
    function setMaxParticipants(uint8 _maxParticipants) external onlyOwner {
        require(_maxParticipants > 1, "There should be at least two participants");
        maxParticipants = _maxParticipants;
    }

    // Function to update the minimum and maximum bet timeouts
    function updateTimeouts(uint256 newMinBetTimeout, uint256 newMaxBetTimeout) public onlyOwner {
        require(newMinBetTimeout <= newMaxBetTimeout, "Minimum timeout should be less than or equal to maximum timeout");
        MIN_BET_TIMEOUT = newMinBetTimeout;
        MAX_BET_TIMEOUT = newMaxBetTimeout;
    }

    // Function to toggle middleman participation
    function toggleMiddlemanParticipation(bool allowParticipation) external onlyOwner {
        allowMiddlemanParticipation = allowParticipation;
    }

    // Function to pause a bet
    function pauseBet(uint256 betId) external onlyOwner {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        bet.paused = true;
    }

    // Function to unpause a bet
    function unpauseBet(uint256 betId) external onlyOwner {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        bet.paused = false;
    }

    // Function to change the middleman of a bet
    function changeMiddleman(uint256 betId, address newMiddleman) external onlyOwner {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        bet.middleMan = newMiddleman;
    }

    // Function to set the fee percentage
    function setFeePercentage(uint8 _feePercentage) external onlyOwner {
        require(_feePercentage <= 30, "Fee percentage cannot be greater than 30");
        feePercentage = _feePercentage;
    }

    // Function to set the middleman fee percentage
    function setMiddleManFeePercentage(uint256 _newFee) external onlyOwner {
        require(_newFee <= 30, "Middleman fee percentage cannot be greater than 30");
        middleManFeePercentage = _newFee;
    }

    // Function to set the cancellation fee percentage
    function setCancellationFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 30, "Cancellation fee percentage cannot be greater than 30");
        cancellationFeePercentage = newFeePercentage;
    }

    // Function to initiate the ownership transfer process
    function initiateOwnershipTransfer(address payable _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be the zero address");
        newOwner = _newOwner;
    }

    // Function to confirm the ownership transfer
    function acceptOwnership() external {
        require(msg.sender == newOwner, "Only the new owner can accept ownership");
        owner = newOwner;
        newOwner = payable(address(0));
    }

    // Create Functions

    // Function to create an Ether bet
    function createEtherBet(string memory _title, address middleMan, uint256 customTimeout) external payable {
        require(msg.value > 0, "Bet amount must be greater than 0 ETH");
        require(middleMan != address(0), "MiddleMan address cannot be zero address");
        require(allowMiddlemanParticipation || msg.sender != middleMan, "Middleman participation is not allowed");
        require(customTimeout >= MIN_BET_TIMEOUT && customTimeout <= MAX_BET_TIMEOUT, "Invalid timeout duration");

        bets[betCount] = Bet({
            title: _title,
            betAmount: msg.value,
            middleMan: middleMan,
            participants: new address payable[](0),
            status: BetStatus.Ongoing,
            creationTime: block.timestamp,
            betType: BetType.Ether,
            tokenAddress: address(0),
            timeout: customTimeout,
            paused: false
        });

        bets[betCount].participants.push(payable(msg.sender));

        emit BetCreated(betCount, msg.sender, msg.value, customTimeout);
        betCount++;
    }

    // Function to create an ERC20 bet
    function createERC20Bet(string memory _title, address middleMan, uint256 customTimeout, uint256 betAmount, address tokenAddress) external {
        require(betAmount > 0, "Bet amount must be greater than 0");
        require(tokenAddress != address(0), "Token address cannot be zero address");
        require(middleMan != address(0), "MiddleMan address cannot be zero address");
        require(allowMiddlemanParticipation || msg.sender != middleMan, "Middleman participation is not allowed");
        require(customTimeout >= MIN_BET_TIMEOUT && customTimeout <= MAX_BET_TIMEOUT, "Invalid timeout duration");

        IERC20 token = IERC20(tokenAddress);
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= betAmount, "Insufficient allowance for the bet");

        require(token.transferFrom(msg.sender, address(this), betAmount), "Token transfer failed");

        bets[betCount] = Bet({
            title: _title,
            betAmount: betAmount,
            middleMan: middleMan,
            participants: new address payable[](0),
            status: BetStatus.Ongoing,
            creationTime: block.timestamp,
            betType: BetType.ERC20,
            tokenAddress: tokenAddress,
            timeout: customTimeout,
            paused: false
        });

        bets[betCount].participants.push(payable(msg.sender));

        emit BetCreated(betCount, msg.sender, betAmount, customTimeout);
        betCount++;
    }

    // Function to create an ERC721 bet
    function createERC721Bet(string memory _title, address middleMan, address _tokenAddress, uint256 _tokenId, uint256 customTimeout) external {
        require(customTimeout >= MIN_BET_TIMEOUT && customTimeout <= MAX_BET_TIMEOUT, "Invalid timeout duration");
        require(_tokenAddress != address(0), "Token address cannot be zero address");
        require(middleMan != address(0), "MiddleMan address cannot be zero address");
        require(allowMiddlemanParticipation || msg.sender != middleMan, "Middleman participation is not allowed");

        IERC721 token = IERC721(_tokenAddress);
        require(token.isApprovedForAll(msg.sender, address(this)) || token.getApproved(_tokenId) == address(this), "Contract not approved for the required token transfer");
        require(token.ownerOf(_tokenId) == msg.sender, "You don't own this token");
        token.transferFrom(msg.sender, address(this), _tokenId);

        bets[betCount] = Bet({
            title: _title,
            betAmount: 0,
            middleMan: middleMan,
            participants: new address payable[](0),
            status: BetStatus.Ongoing,
            creationTime: block.timestamp,
            betType: BetType.ERC721, 
            tokenAddress: _tokenAddress,
            timeout: customTimeout,
            paused: false 
        });

        bets[betCount].participants.push(payable(msg.sender));
        participantTokenIds[betCount][msg.sender] = _tokenId;

        emit BetCreated(betCount, msg.sender, 0, customTimeout);
        betCount++;
    }

    // Join Functions
  
    // Function to join an ETHER bet
    function joinEtherBet(uint256 betId) external payable whenBetNotPaused(betId) {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        require(bet.betType == BetType.Ether, "Not an Ether bet");
        require(!hasJoined[betId][msg.sender], "You have already joined this bet");
        require(msg.sender != owner, "Bet creator cannot participate");
        require(allowMiddlemanParticipation || msg.sender != bet.middleMan, "Middleman participation not allowed");
        require(msg.value == bet.betAmount, "Incorrect bet amount sent");
        require(bet.participants.length < maxParticipants, "Maximum participants reached");

        bet.participants.push(payable(msg.sender));
        hasJoined[betId][msg.sender] = true;
        emit BetJoined(betId, msg.sender);
    }

    // Function to join an ERC20 bet
    function joinERC20Bet(uint256 betId, uint256 amount) external whenBetNotPaused(betId) {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        require(bet.betType == BetType.ERC20, "Not an ERC20 bet");
        require(!hasJoined[betId][msg.sender], "You have already joined this bet");
        require(msg.sender != bet.participants[0], "The creator cannot join their own bet");
        require(msg.sender != owner, "Bet creator cannot participate");
        require(allowMiddlemanParticipation || msg.sender != bet.middleMan, "Middleman participation not allowed");
        require(amount == bet.betAmount, "Incorrect bet amount");
        require(bet.participants.length < maxParticipants, "Maximum participants reached");

        IERC20 token = IERC20(bet.tokenAddress);
        uint256 allowance = token.allowance(msg.sender, address(this));
        require(allowance >= amount, "Contract not approved for the required token amount");

        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        bet.participants.push(payable(msg.sender));
        hasJoined[betId][msg.sender] = true;
        emit BetJoined(betId, msg.sender);
    }

    // Function to join an ERC721 bet
    function joinERC721Bet(uint256 betId, uint256[] memory tokenIds) external whenBetNotPaused(betId) {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        require(bet.participants.length < maxParticipants, "Max participants reached");
        require(bet.timeout.add(bet.creationTime) > block.timestamp, "Bet has expired");
        require(bet.betType == BetType.ERC721, "Bet type is not ERC721");
        require(msg.sender != owner, "Bet creator cannot participate");
        require(allowMiddlemanParticipation || msg.sender != bet.middleMan, "Middleman participation not allowed");

        IERC721 token = IERC721(bet.tokenAddress);
        require(token.isApprovedForAll(msg.sender, address(this)), "Contract not approved for token");

        uint256 requiredTokenCount = bet.participants.length;
        require(tokenIds.length == requiredTokenCount, "Must provide the same number of tokens as required in the bet");

        for (uint256 i = 0; i < requiredTokenCount; i++) {
            require(token.ownerOf(tokenIds[i]) == msg.sender, "Not the owner of one or more participant tokens");
        }

        for (uint256 i = 0; i < requiredTokenCount; i++) {
            participantTokenIds[betId][msg.sender] = tokenIds[i];
            token.transferFrom(msg.sender, address(this), tokenIds[i]);
        }

        bet.participants.push(payable(msg.sender));
        hasJoined[betId][msg.sender] = true;

        emit BetJoined(betId, msg.sender);
    }

    //  Public View Functions

    // Function to get any bet details 
    function getBetDetails(uint256 betId) public view returns (string memory title, address creator, uint256 betAmount, address middleMan, address payable[] memory participants, BetStatus status, BetType betType, uint256 timeout, bool paused, address tokenAddress) {
        require(betId < betCount, "Invalid bet ID");

        Bet storage bet = bets[betId];
        return (bet.title, bet.participants[0], bet.betAmount, bet.middleMan, bet.participants, bet.status, bet.betType, bet.timeout, bet.paused, bet.tokenAddress);
    }

    // Function to get the bet status 
    function getBetStatus(uint256 betId) public view returns (BetStatus) {
        require(betId < betCount, "Invalid bet ID");

        Bet storage bet = bets[betId];
        return bet.status;
    }
    // Function to get total bets 
    function getBetCount() public view returns (uint256) {
        return betCount;
    }

    // Function to check if a user is a participant of the bet  
    function hasAddressJoinedBet(uint256 betId, address participant) public view returns (bool) {
        require(betId < betCount, "Invalid bet ID");
        return hasJoined[betId][participant];
    }

    // Function to see every bet user has participated in 
    function getBetHistory(address user) public view returns (uint[] memory) {
        uint[] memory userBetHistory = new uint[](betCount);
        uint counter = 0;
    
        for (uint i = 0; i < betCount; i++) {
                if (hasJoined[i][user] || bets[i].participants[0] == user) {
                userBetHistory[counter] = i;
                counter++;
        }
    }
        // Trim the array to the correct size
        uint[] memory result = new uint[](counter);
        for (uint j = 0; j < counter; j++) {
        result[j] = userBetHistory[j];
    }
    
    return result;
    }

    // Function to see total eth wagered
    function getTotalWagered() public view returns (uint) {
        uint totalWagered;
        
        for (uint i = 0; i < betCount; i++) {
            totalWagered += bets[i].betAmount;
        }
        return totalWagered;
    }

    // Resolving Logic

    // Function to resolve a bet
    function resolveBet(uint256 betId, address winner) external whenBetNotPaused(betId) {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        require(!bet.paused, "Bet is paused");
        require(msg.sender == bet.middleMan, "Only the middleman can resolve this bet");

        bool isParticipant = false;
        for (uint i = 0; i < bet.participants.length; i++) {
            if (bet.participants[i] == winner) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant, "Winner must be a participant of the bet");

        uint256 totalPool = bet.betAmount.mul(bet.participants.length);
        uint256 fee = totalPool.mul(feePercentage).div(100);
        uint256 middleManFee = totalPool.mul(middleManFeePercentage).div(100);
        uint256 totalFee = fee.add(middleManFee);
        uint256 payoutAmount = totalPool.sub(totalFee);

        if (bet.betType == BetType.Ether) {
            // Update state before external transfers
            (bet.status, bet.betAmount) = (BetStatus.Resolved, 0);

            (bool success, ) = owner.call{value: fee}("");
            require(success, "Fee transfer failed");

            (success, ) = payable(bet.middleMan).call{value: middleManFee}("");
            require(success, "Middleman fee transfer failed");

            (success, ) = payable(winner).call{value: payoutAmount}("");
            require(success, "Payout transfer failed");
        } else if (bet.betType == BetType.ERC20) {
            // Update state before external transfers
            (bet.status, bet.betAmount) = (BetStatus.Resolved, 0);

            IERC20 token = IERC20(bet.tokenAddress);

            require(token.safeTransfer(owner, fee), "Fee transfer failed");
            require(token.safeTransfer(bet.middleMan, middleManFee), "Middleman fee transfer failed");
            require(token.safeTransfer(winner, payoutAmount), "Payout transfer failed");
        } else if (bet.betType == BetType.ERC721) {
            // Update state before external transfers
            (bet.status, bet.betAmount) = (BetStatus.Resolved, 0);

            IERC721 token = IERC721(bet.tokenAddress);

            for (uint i = 0; i < bet.participants.length; i++) {
                uint256 tokenId = participantTokenIds[betId][bet.participants[i]];
                // Update state, then transfer
                token.transferFrom(address(this), winner, tokenId);
            }
        }
    }

    // Canceling Logic

    // Function to cancel a bet
    function cancelBet(uint256 betId) external whenBetNotPaused(betId) {
        Bet storage bet = bets[betId];
        require(bet.status == BetStatus.Ongoing, "Bet is not ongoing");
        require(!bet.paused, "Bet is paused");

        if (msg.sender == bet.middleMan) {
            // Middleman can cancel the bet at any time
        } else {
            require(bet.timeout.add(bet.creationTime) <= block.timestamp, "Permission denied");
            // Owner and participants can only cancel after the timeout has passed
        }

        uint256 totalPool = bet.betAmount.mul(bet.participants.length);
        uint256 cancellationFee = totalPool.mul(cancellationFeePercentage).div(100);
        uint256 refundAmount = totalPool.sub(cancellationFee);

        if (bet.betType == BetType.Ether) {
            // Update state before external transfers
            (bet.status, bet.betAmount) = (BetStatus.Cancelled, 0);

            (bool success, ) = owner.call{value: cancellationFee}("");
            require(success, "Cancellation fee transfer failed");

            for (uint i = 0; i < bet.participants.length; i++) {
                // Update state, then transfer
                (success, ) = bet.participants[i].call{value: refundAmount.div(bet.participants.length)}("");
                require(success, "Refund transfer failed");
            }
        } else if (bet.betType == BetType.ERC20) {
            // Update state before external transfers
            (bet.status, bet.betAmount) = (BetStatus.Cancelled, 0);

            IERC20 token = IERC20(bet.tokenAddress);

            require(token.safeTransfer(owner, cancellationFee), "Cancellation fee transfer failed");

            for (uint i = 0; i < bet.participants.length; i++) {
                // Update state, then transfer
                bool transferSucceeded = token.safeTransfer(bet.participants[i], refundAmount.div(bet.participants.length));
                require(transferSucceeded, "Token refund transfer failed");
            }
        } else if (bet.betType == BetType.ERC721) {
            // Update state before external transfers
            (bet.status, bet.betAmount) = (BetStatus.Cancelled, 0);

            IERC721 token = IERC721(bet.tokenAddress);

            for (uint i = 0; i < bet.participants.length; i++) {
                uint256 tokenId = participantTokenIds[betId][bet.participants[i]];
                // Update state, then transfer
                token.transferFrom(address(this), bet.participants[i], tokenId);
            }
        }
    }
}
