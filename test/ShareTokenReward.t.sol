// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/PredictionMarket.sol";
import "../contracts/ShareToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockProtocolToken is ERC20 {
    constructor() ERC20("Protocol Token", "PROTO") {
        _mint(msg.sender, 1000000 * 1e18);
    }
}

contract ShareTokenRewardTest is Test {
    PredictionMarket public market;
    MockProtocolToken public protocolToken;
    
    address public creator = makeAddr("creator");
    address public trader1 = makeAddr("trader1");
    address public trader2 = makeAddr("trader2");
    address public owner;
    
    receive() external payable {}
    
    function setUp() public {
        owner = address(this);
        market = new PredictionMarket();
        protocolToken = new MockProtocolToken();
        
        vm.deal(creator, 100 ether);
        vm.deal(trader1, 100 ether);
        vm.deal(trader2, 100 ether);
    }
    
    function testCreatorReceivesShareTokens() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: 0.01 ether}("TOKEN", 1000);
        
        uint256 creatorShares = market.getUserShareBalance(creator);
        assertEq(creatorShares, 1000 * 1e18, "Creator should receive 1000 share tokens");
    }
    
    function testCreatorEarnsSharesOnTrading() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: 0.01 ether}("TOKEN", 1000);
        
        uint256 initialShares = market.getUserShareBalance(creator);
        
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        vm.prank(trader1);
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        uint256 afterTradeShares = market.getUserShareBalance(creator);
        assertEq(afterTradeShares, initialShares + 10 * 1e18, "Creator should earn 10 share tokens per trade");
    }
    
    function testWinnerReceivesShareTokens() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: 0.01 ether}("TOKEN", 1000);
        
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        vm.prank(trader1);
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        vm.warp(block.timestamp + 1 days);
        
        market.settleMarket(marketId, 1150);
        
        uint256 beforeClaim = market.getUserShareBalance(trader1);
        
        vm.prank(trader1);
        market.claimWinnings(marketId);
        
        uint256 afterClaim = market.getUserShareBalance(trader1);
        assertEq(afterClaim, beforeClaim + (100 * 100), "Winner should receive share tokens (shares * 100)");
    }
    
    function testProtocolTokenClaim() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: 0.01 ether}("TOKEN", 1000);
        
        market.setProtocolToken(address(protocolToken));
        
        uint256 depositAmount = 10000 * 1e18;
        protocolToken.approve(address(market), depositAmount);
        market.depositProtocolTokens(depositAmount);
        
        uint256 creatorShares = market.getUserShareBalance(creator);
        
        vm.startPrank(creator);
        ShareToken shareToken = ShareToken(market.getShareTokenAddress());
        shareToken.approve(address(market), creatorShares);
        
        uint256 protocolBalanceBefore = protocolToken.balanceOf(creator);
        market.claimProtocolTokens(creatorShares);
        uint256 protocolBalanceAfter = protocolToken.balanceOf(creator);
        
        assertGt(protocolBalanceAfter, protocolBalanceBefore, "Creator should receive protocol tokens");
        assertEq(market.getUserShareBalance(creator), 0, "Share tokens should be burned");
        vm.stopPrank();
    }
    
    function testProtocolTokenDistribution() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: 0.01 ether}("TOKEN", 1000);
        
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        vm.prank(trader1);
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        market.setProtocolToken(address(protocolToken));
        
        uint256 depositAmount = 10000 * 1e18;
        protocolToken.approve(address(market), depositAmount);
        market.depositProtocolTokens(depositAmount);
        
        uint256 creatorShares = market.getUserShareBalance(creator);
        (uint256 protocolBalance, uint256 totalShares) = market.getProtocolTokenInfo();
        
        assertEq(protocolBalance, depositAmount, "Protocol balance should match deposit");
        assertEq(totalShares, 1000 * 1e18 + 10 * 1e18, "Total shares should be 1000 (creation) + 10 (trading)");
        
        uint256 expectedProtocol = (protocolBalance * creatorShares) / totalShares;
        
        vm.startPrank(creator);
        ShareToken shareToken = ShareToken(market.getShareTokenAddress());
        shareToken.approve(address(market), creatorShares);
        
        market.claimProtocolTokens(creatorShares);
        uint256 receivedProtocol = protocolToken.balanceOf(creator);
        
        assertEq(receivedProtocol, expectedProtocol, "Creator should receive proportional protocol tokens");
        vm.stopPrank();
    }
}
