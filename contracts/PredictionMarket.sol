// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./PositionToken.sol";
import "./ShareToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    
    uint256 public constant CREATOR_INITIAL_SHARES = 1000 * 1e18;
    uint256 public constant TRADER_SHARE_REWARD = 10 * 1e18;
    uint256 public constant WINNER_SHARE_MULTIPLIER = 100;
    
    address public platformOwner;
    uint256 public nextMarketId;
    mapping(uint256 => Market) public markets;
    mapping(address => bool) public authorizedBots;
    
    ShareToken public shareToken;
    IERC20 public protocolToken;
    uint256 public protocolTokenBalance;
    uint256 public totalSharesIssued;
    
    event MarketCreated(uint256 indexed marketId, address creator, string tokenAddress, uint256 initialPrice, uint256 settlementTime);
    event SharesPurchased(uint256 indexed marketId, address buyer, Outcome outcome, uint256 shares, uint256 cost);
    event SharesSold(uint256 indexed marketId, address seller, Outcome outcome, uint256 shares, uint256 payout);
    event MarketSettled(uint256 indexed marketId, Outcome winningOutcome, uint256 finalPrice);
    event WinningsClaimed(uint256 indexed marketId, address winner, uint256 amount);
    event BotAuthorized(address indexed bot, bool authorized);
    event BatchSettlement(uint256[] marketIds, uint256 successCount);
    event FeesPaid(uint256 indexed marketId, address indexed creator, uint256 creatorFee, uint256 platformFee);
    event ShareTokensEarned(address indexed user, uint256 amount, string reason);
    event ProtocolTokenDeposited(uint256 amount);
    event ProtocolTokenClaimed(address indexed user, uint256 shareTokensBurned, uint256 protocolTokensReceived);
    
    constructor() {
        platformOwner = msg.sender;
        shareToken = new ShareToken(address(this));
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
        
        shareToken.mint(msg.sender, CREATOR_INITIAL_SHARES);
        totalSharesIssued += CREATOR_INITIAL_SHARES;
        emit ShareTokensEarned(msg.sender, CREATOR_INITIAL_SHARES, "Market creation");
        
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
        
        // Send fees immediately
        payable(market.creator).transfer(creatorFee);
        payable(platformOwner).transfer(platformFee);
        
        PositionToken posToken = PositionToken(market.positionTokens[_outcome]);
        posToken.mint(msg.sender, _shares);
        
        shareToken.mint(market.creator, TRADER_SHARE_REWARD);
        totalSharesIssued += TRADER_SHARE_REWARD;
        emit ShareTokensEarned(market.creator, TRADER_SHARE_REWARD, "Trading activity");
        
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
        
        emit FeesPaid(_marketId, market.creator, creatorFee, platformFee);
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
        
        posToken.burn(msg.sender, _shares);
        
        // Send fees immediately
        payable(market.creator).transfer(creatorFee);
        payable(platformOwner).transfer(platformFee);
        
        payable(msg.sender).transfer(netPayout);
        
        emit FeesPaid(_marketId, market.creator, creatorFee, platformFee);
        emit SharesSold(_marketId, msg.sender, _outcome, _shares, netPayout);
    }
    
    function settleMarket(uint256 _marketId, uint256 _finalPrice) external {
        require(authorizedBots[msg.sender] || msg.sender == platformOwner, "Not authorized");
        Market storage market = markets[_marketId];
        require(!market.settled, "Market already settled");
        require(block.timestamp >= market.settlementTime, "Settlement time not reached");
        
        market.settled = true;
        market.finalPrice = _finalPrice;
        market.winningOutcome = determineOutcome(market.initialPrice, _finalPrice);
        
        emit MarketSettled(_marketId, market.winningOutcome, _finalPrice);
    }
    
    function batchSettleMarkets(uint256[] calldata _marketIds, uint256[] calldata _finalPrices) external {
        require(authorizedBots[msg.sender] || msg.sender == platformOwner, "Not authorized");
        require(_marketIds.length == _finalPrices.length, "Array length mismatch");
        
        uint256 successCount = 0;
        
        for (uint256 i = 0; i < _marketIds.length; i++) {
            Market storage market = markets[_marketIds[i]];
            
            if (!market.settled && block.timestamp >= market.settlementTime) {
                market.settled = true;
                market.finalPrice = _finalPrices[i];
                market.winningOutcome = determineOutcome(market.initialPrice, _finalPrices[i]);
                
                emit MarketSettled(_marketIds[i], market.winningOutcome, _finalPrices[i]);
                successCount++;
            }
        }
        
        emit BatchSettlement(_marketIds, successCount);
    }
    
    function authorizeBot(address _bot, bool _authorized) external {
        require(msg.sender == platformOwner, "Only platform owner");
        authorizedBots[_bot] = _authorized;
        emit BotAuthorized(_bot, _authorized);
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
        
        uint256 shareReward = userShares * WINNER_SHARE_MULTIPLIER;
        shareToken.mint(msg.sender, shareReward);
        totalSharesIssued += shareReward;
        emit ShareTokensEarned(msg.sender, shareReward, "Winning claim");
        
        payable(msg.sender).transfer(userWinnings);
        
        emit WinningsClaimed(_marketId, msg.sender, userWinnings);
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
    
    function getUnsettledMarkets(uint256[] calldata _marketIds) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _marketIds.length; i++) {
            if (!markets[_marketIds[i]].settled && block.timestamp >= markets[_marketIds[i]].settlementTime) {
                count++;
            }
        }
        
        uint256[] memory unsettled = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _marketIds.length; i++) {
            if (!markets[_marketIds[i]].settled && block.timestamp >= markets[_marketIds[i]].settlementTime) {
                unsettled[index] = _marketIds[i];
                index++;
            }
        }
        
        return unsettled;
    }
    
    function isAuthorizedBot(address _bot) external view returns (bool) {
        return authorizedBots[_bot];
    }
    
    function setProtocolToken(address _protocolToken) external {
        require(msg.sender == platformOwner, "Only platform owner");
        require(address(protocolToken) == address(0), "Protocol token already set");
        protocolToken = IERC20(_protocolToken);
    }
    
    function depositProtocolTokens(uint256 _amount) external {
        require(msg.sender == platformOwner, "Only platform owner");
        require(address(protocolToken) != address(0), "Protocol token not set");
        require(_amount > 0, "Invalid amount");
        
        protocolToken.transferFrom(msg.sender, address(this), _amount);
        protocolTokenBalance += _amount;
        
        emit ProtocolTokenDeposited(_amount);
    }
    
    function claimProtocolTokens(uint256 _shareAmount) external {
        require(address(protocolToken) != address(0), "Protocol token not set");
        require(_shareAmount > 0, "Invalid share amount");
        require(shareToken.balanceOf(msg.sender) >= _shareAmount, "Insufficient share tokens");
        require(totalSharesIssued > 0, "No shares issued");
        require(protocolTokenBalance > 0, "No protocol tokens available");
        
        uint256 protocolAmount = (protocolTokenBalance * _shareAmount) / totalSharesIssued;
        require(protocolAmount > 0, "Protocol amount too small");
        
        shareToken.burn(msg.sender, _shareAmount);
        totalSharesIssued -= _shareAmount;
        protocolTokenBalance -= protocolAmount;
        
        protocolToken.transfer(msg.sender, protocolAmount);
        
        emit ProtocolTokenClaimed(msg.sender, _shareAmount, protocolAmount);
    }
    
    function getShareTokenAddress() external view returns (address) {
        return address(shareToken);
    }
    
    function getProtocolTokenAddress() external view returns (address) {
        return address(protocolToken);
    }
    
    function getUserShareBalance(address _user) external view returns (uint256) {
        return shareToken.balanceOf(_user);
    }
    
    function getProtocolTokenInfo() external view returns (uint256 balance, uint256 totalShares) {
        return (protocolTokenBalance, totalSharesIssued);
    }
}
