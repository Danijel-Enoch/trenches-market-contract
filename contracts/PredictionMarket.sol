// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./PositionToken.sol";

contract PredictionMarket {
    enum Outcome { PUMP, DUMP, NO_CHANGE, RUG, MOON }
    
    struct Market {
        address creator;
        string tokenAddress;
        uint256 initialPrice;
        uint256 createdAt;
        uint256 settlementTime;
        bool settled;
        Outcome winningOutcome;
        uint256 finalPrice;
        mapping(Outcome => uint256) totalShares;
        mapping(Outcome => uint256) totalVolume;
        mapping(Outcome => address) positionTokens;
    }
    
    uint256 public constant CREATOR_FEE = 0.01 ether;
    uint256 public constant TRADING_FEE_CREATOR = 10; // 0.1%
    uint256 public constant TRADING_FEE_PLATFORM = 100; // 1%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    address public platformOwner;
    uint256 public nextMarketId;
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(Outcome => uint256)) public accumulatedFees;
    
    event MarketCreated(uint256 indexed marketId, address creator, string tokenAddress, uint256 initialPrice, uint256 settlementTime);
    event SharesPurchased(uint256 indexed marketId, address buyer, Outcome outcome, uint256 shares, uint256 cost);
    event SharesSold(uint256 indexed marketId, address seller, Outcome outcome, uint256 shares, uint256 payout);
    event MarketSettled(uint256 indexed marketId, Outcome winningOutcome, uint256 finalPrice);
    event WinningsClaimed(uint256 indexed marketId, address winner, uint256 amount);
    
    constructor() {
        platformOwner = msg.sender;
    }
    
    function createMarket(string calldata _tokenAddress, uint256 _initialPrice) external payable returns (uint256) {
        require(msg.value >= CREATOR_FEE, "Insufficient creation fee");
        require(_initialPrice > 0, "Invalid initial price");
        
        uint256 marketId = nextMarketId++;
        Market storage market = markets[marketId];
        market.creator = msg.sender;
        market.tokenAddress = _tokenAddress;
        market.initialPrice = _initialPrice;
        market.createdAt = block.timestamp;
        market.settlementTime = getNextMidnight(block.timestamp);
        market.settled = false;
        
        string[5] memory outcomeNames = ["PUMP", "DUMP", "NO_CHANGE", "RUG", "MOON"];
        for (uint8 i = 0; i < 5; i++) {
            string memory name = string(abi.encodePacked(_tokenAddress, "-", outcomeNames[i]));
            string memory symbol = string(abi.encodePacked("POS-", outcomeNames[i]));
            
            PositionToken posToken = new PositionToken(name, symbol, marketId, i, address(this));
            market.positionTokens[Outcome(i)] = address(posToken);
        }
        
        payable(platformOwner).transfer(CREATOR_FEE);
        
        if (msg.value > CREATOR_FEE) {
            payable(msg.sender).transfer(msg.value - CREATOR_FEE);
        }
        
        emit MarketCreated(marketId, msg.sender, _tokenAddress, _initialPrice, market.settlementTime);
        return marketId;
    }
    
    function buyShares(uint256 _marketId, Outcome _outcome, uint256 _shares) external payable {
        Market storage market = markets[_marketId];
        require(!market.settled, "Market already settled");
        require(block.timestamp < market.settlementTime, "Market closed");
        require(_shares > 0, "Invalid shares amount");
        
        uint256 cost = calculateBuyCost(_marketId, _outcome, _shares);
        require(msg.value >= cost, "Insufficient payment");
        
        uint256 creatorFee = (cost * TRADING_FEE_CREATOR) / FEE_DENOMINATOR;
        uint256 platformFee = (cost * TRADING_FEE_PLATFORM) / FEE_DENOMINATOR;
        uint256 netCost = cost - creatorFee - platformFee;
        
        market.totalShares[_outcome] += _shares;
        market.totalVolume[_outcome] += netCost;
        
        accumulatedFees[_marketId][_outcome] += creatorFee + platformFee;
        
        PositionToken posToken = PositionToken(market.positionTokens[_outcome]);
        posToken.mint(msg.sender, _shares);
        
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
        
        emit SharesPurchased(_marketId, msg.sender, _outcome, _shares, cost);
    }
    
    function sellShares(uint256 _marketId, Outcome _outcome, uint256 _shares) external {
        Market storage market = markets[_marketId];
        require(_shares > 0, "Invalid shares amount");
        
        PositionToken posToken = PositionToken(market.positionTokens[_outcome]);
        require(posToken.balanceOf(msg.sender) >= _shares, "Insufficient shares");
        
        if (market.settled) {
            require(_outcome == market.winningOutcome, "Only winners can sell after settlement");
        } else {
            require(block.timestamp < market.settlementTime, "Market closed, awaiting settlement");
        }
        
        uint256 payout = calculateSellPayout(_marketId, _outcome, _shares);
        
        uint256 creatorFee = (payout * TRADING_FEE_CREATOR) / FEE_DENOMINATOR;
        uint256 platformFee = (payout * TRADING_FEE_PLATFORM) / FEE_DENOMINATOR;
        uint256 netPayout = payout - creatorFee - platformFee;
        
        market.totalShares[_outcome] -= _shares;
        
        if (market.totalVolume[_outcome] > netPayout) {
            market.totalVolume[_outcome] -= netPayout;
        } else {
            market.totalVolume[_outcome] = 0;
        }
        
        accumulatedFees[_marketId][_outcome] += creatorFee + platformFee;
        
        posToken.burn(msg.sender, _shares);
        
        payable(msg.sender).transfer(netPayout);
        
        emit SharesSold(_marketId, msg.sender, _outcome, _shares, netPayout);
    }
    
    function settleMarket(uint256 _marketId, uint256 _finalPrice) external {
        Market storage market = markets[_marketId];
        require(!market.settled, "Market already settled");
        require(block.timestamp >= market.settlementTime, "Settlement time not reached");
        
        market.settled = true;
        market.finalPrice = _finalPrice;
        market.winningOutcome = determineOutcome(market.initialPrice, _finalPrice);
        
        emit MarketSettled(_marketId, market.winningOutcome, _finalPrice);
    }
    
    function claimWinnings(uint256 _marketId) external {
        Market storage market = markets[_marketId];
        require(market.settled, "Market not settled");
        
        Outcome winningOutcome = market.winningOutcome;
        PositionToken posToken = PositionToken(market.positionTokens[winningOutcome]);
        uint256 userShares = posToken.balanceOf(msg.sender);
        require(userShares > 0, "No winning shares");
        
        uint256 totalWinningShares = market.totalShares[winningOutcome];
        require(totalWinningShares > 0, "No winning shares exist");
        
        uint256 totalPrizePool = 0;
        for (uint256 i = 0; i < 5; i++) {
            totalPrizePool += market.totalVolume[Outcome(i)];
        }
        
        uint256 userWinnings = (totalPrizePool * userShares) / totalWinningShares;
        
        posToken.burn(msg.sender, userShares);
        
        payable(msg.sender).transfer(userWinnings);
        
        emit WinningsClaimed(_marketId, msg.sender, userWinnings);
    }
    
    function withdrawFees(uint256 _marketId) external {
        Market storage market = markets[_marketId];
        require(market.settled, "Market not settled");
        
        uint256 totalCreatorFees = 0;
        uint256 totalPlatformFees = 0;
        
        for (uint256 i = 0; i < 5; i++) {
            uint256 fees = accumulatedFees[_marketId][Outcome(i)];
            uint256 creatorShare = (fees * TRADING_FEE_CREATOR) / (TRADING_FEE_CREATOR + TRADING_FEE_PLATFORM);
            uint256 platformShare = fees - creatorShare;
            
            totalCreatorFees += creatorShare;
            totalPlatformFees += platformShare;
            
            accumulatedFees[_marketId][Outcome(i)] = 0;
        }
        
        if (msg.sender == market.creator && totalCreatorFees > 0) {
            payable(market.creator).transfer(totalCreatorFees);
        }
        
        if (msg.sender == platformOwner && totalPlatformFees > 0) {
            payable(platformOwner).transfer(totalPlatformFees);
        }
    }
    
    function calculateBuyCost(uint256 _marketId, Outcome _outcome, uint256 _shares) public view returns (uint256) {
        Market storage market = markets[_marketId];
        uint256 currentShares = market.totalShares[_outcome];
        
        uint256 k = 1e15;
        uint256 cost = (k * _shares * (2 * currentShares + _shares)) / 2;
        
        return cost;
    }
    
    function calculateSellPayout(uint256 _marketId, Outcome _outcome, uint256 _shares) public view returns (uint256) {
        Market storage market = markets[_marketId];
        uint256 currentShares = market.totalShares[_outcome];
        require(currentShares >= _shares, "Not enough shares in pool");
        
        uint256 k = 1e15;
        uint256 payout = (k * _shares * (2 * currentShares - _shares)) / 2;
        
        return payout;
    }
    
    function determineOutcome(uint256 _initialPrice, uint256 _finalPrice) internal pure returns (Outcome) {
        if (_finalPrice >= _initialPrice * 150 / 100) {
            return Outcome.MOON;
        } else if (_finalPrice >= _initialPrice * 110 / 100) {
            return Outcome.PUMP;
        } else if (_finalPrice <= _initialPrice * 50 / 100) {
            return Outcome.RUG;
        } else if (_finalPrice <= _initialPrice * 90 / 100) {
            return Outcome.DUMP;
        } else {
            return Outcome.NO_CHANGE;
        }
    }
    
    function getNextMidnight(uint256 _timestamp) internal pure returns (uint256) {
        uint256 secondsInDay = 86400;
        uint256 dayStart = (_timestamp / secondsInDay) * secondsInDay;
        return dayStart + secondsInDay;
    }
    
    function getMarketInfo(uint256 _marketId) external view returns (
        address creator,
        string memory tokenAddress,
        uint256 initialPrice,
        uint256 createdAt,
        uint256 settlementTime,
        bool settled,
        uint256 finalPrice
    ) {
        Market storage market = markets[_marketId];
        return (
            market.creator,
            market.tokenAddress,
            market.initialPrice,
            market.createdAt,
            market.settlementTime,
            market.settled,
            market.finalPrice
        );
    }
    
    function getUserShares(uint256 _marketId, address _user, Outcome _outcome) external view returns (uint256) {
        Market storage market = markets[_marketId];
        PositionToken posToken = PositionToken(market.positionTokens[_outcome]);
        return posToken.balanceOf(_user);
    }
    
    function getOutcomeStats(uint256 _marketId, Outcome _outcome) external view returns (uint256 totalShares, uint256 totalVolume) {
        Market storage market = markets[_marketId];
        return (market.totalShares[_outcome], market.totalVolume[_outcome]);
    }
    
    function getPositionToken(uint256 _marketId, Outcome _outcome) external view returns (address) {
        return markets[_marketId].positionTokens[_outcome];
    }
}
