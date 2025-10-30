// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/PredictionMarket.sol";
import "../contracts/PositionToken.sol";

/**
 * @title PredictionMarketTest
 * @notice Comprehensive test suite for the PredictionMarket contract
 * @dev Tests cover:
 *  - Market creation with fees
 *  - Buying and selling shares with bonding curve
 *  - ERC20 position token minting/burning
 *  - Market settlement and outcome determination
 *  - Winner claims and prize pool distribution
 *  - Fee collection for creators and platform
 *  - Edge cases and access control
 */
contract PredictionMarketTest is Test {
    PredictionMarket public market;
    
    address public platformOwner = address(0x100);
    address public creator = address(0x200);
    address public trader1 = address(0x300);
    address public trader2 = address(0x400);
    address public settlementBot = address(0x500);
    
    uint256 public constant CREATOR_FEE = 0.01 ether;
    
    function setUp() public {
        vm.deal(platformOwner, 100 ether);
        vm.deal(creator, 100 ether);
        vm.deal(trader1, 100 ether);
        vm.deal(trader2, 100 ether);
        vm.deal(settlementBot, 100 ether);
        
        vm.prank(platformOwner);
        market = new PredictionMarket();
    }
    
    function testCreateMarket() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (
            address marketCreator,
            string memory tokenAddress,
            uint256 initialPrice,
            uint256 createdAt,
            uint256 settlementTime,
            bool settled,
            uint256 finalPrice
        ) = market.getMarketInfo(marketId);
        
        assertEq(marketCreator, creator);
        assertEq(tokenAddress, "TOKEN-0x123");
        assertEq(initialPrice, 1000e18);
        assertGt(settlementTime, block.timestamp);
        assertFalse(settled);
        assertEq(finalPrice, 0);
        
        // Verify position tokens were created
        for (uint8 i = 0; i < 5; i++) {
            address posToken = market.getPositionToken(marketId, PredictionMarket.Outcome(i));
            assertTrue(posToken != address(0));
        }
    }
    
    function testCreateMarketInsufficientFee() public {
        vm.prank(creator);
        vm.expectRevert("Insufficient creation fee");
        market.createMarket{value: 0.005 ether}("TOKEN-0x123", 1000e18);
    }
    
    function testCreateMarketInvalidPrice() public {
        vm.prank(creator);
        vm.expectRevert("Invalid initial price");
        market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 0);
    }
    
    function testBuyShares() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        uint256 sharesToBuy = 100;
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, sharesToBuy);
        
        vm.prank(trader1);
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, sharesToBuy);
        
        // Check user received position tokens
        address pumpToken = market.getPositionToken(marketId, PredictionMarket.Outcome.PUMP);
        uint256 balance = PositionToken(pumpToken).balanceOf(trader1);
        assertEq(balance, sharesToBuy);
        
        // Check total shares updated
        (uint256 totalShares, ) = market.getOutcomeStats(marketId, PredictionMarket.Outcome.PUMP);
        assertEq(totalShares, sharesToBuy);
    }
    
    function testBuyMultipleOutcomes() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        uint256 shares = 100;
        
        // Buy PUMP
        uint256 costPump = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, shares);
        vm.prank(trader1);
        market.buyShares{value: costPump}(marketId, PredictionMarket.Outcome.PUMP, shares);
        
        // Buy DUMP
        uint256 costDump = market.calculateBuyCost(marketId, PredictionMarket.Outcome.DUMP, shares);
        vm.prank(trader1);
        market.buyShares{value: costDump}(marketId, PredictionMarket.Outcome.DUMP, shares);
        
        // Verify balances
        address pumpToken = market.getPositionToken(marketId, PredictionMarket.Outcome.PUMP);
        address dumpToken = market.getPositionToken(marketId, PredictionMarket.Outcome.DUMP);
        
        assertEq(PositionToken(pumpToken).balanceOf(trader1), shares);
        assertEq(PositionToken(dumpToken).balanceOf(trader1), shares);
    }
    
    function testBondingCurve() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        // First purchase
        uint256 cost1 = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        // Buy first shares to increase supply
        vm.prank(trader1);
        market.buyShares{value: cost1}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        // Second purchase should be more expensive
        uint256 cost2 = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        assertTrue(cost2 > cost1, "Bonding curve should increase price");
    }
    
    function testSellShares() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        uint256 sharesToBuy = 100;
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, sharesToBuy);
        
        vm.prank(trader1);
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, sharesToBuy);
        
        // Sell half
        uint256 sharesToSell = 50;
        uint256 balanceBefore = trader1.balance;
        
        vm.prank(trader1);
        market.sellShares(marketId, PredictionMarket.Outcome.PUMP, sharesToSell);
        
        // Check tokens burned
        address pumpToken = market.getPositionToken(marketId, PredictionMarket.Outcome.PUMP);
        uint256 remainingBalance = PositionToken(pumpToken).balanceOf(trader1);
        assertEq(remainingBalance, sharesToBuy - sharesToSell);
        
        // Check got ETH back
        assertTrue(trader1.balance > balanceBefore);
    }
    
    function testSellInsufficientShares() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        vm.prank(trader1);
        vm.expectRevert("Insufficient shares");
        market.sellShares(marketId, PredictionMarket.Outcome.PUMP, 100);
    }
    
    function testCannotBuyAfterSettlement() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        
        // Warp to after settlement time
        vm.warp(settlementTime + 1);
        
        // Settle market
        vm.prank(settlementBot);
        market.settleMarket(marketId, 1100e18); // 10% pump
        
        // Try to buy
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        vm.prank(trader1);
        vm.expectRevert("Market already settled");
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, 100);
    }
    
    function testSettleMarketPump() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        
        vm.warp(settlementTime + 1);
        
        vm.prank(settlementBot);
        market.settleMarket(marketId, 1150e18); // 15% up = PUMP
        
        (, , , , , bool settled, uint256 finalPrice) = market.getMarketInfo(marketId);
        assertTrue(settled);
        assertEq(finalPrice, 1150e18);
    }
    
    function testSettleMarketDump() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        
        vm.prank(settlementBot);
        market.settleMarket(marketId, 850e18); // 15% down = DUMP
        
        (, , , , , bool settled, ) = market.getMarketInfo(marketId);
        assertTrue(settled);
    }
    
    function testSettleMarketMoon() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        
        vm.prank(settlementBot);
        market.settleMarket(marketId, 2000e18); // 100% up = MOON (>50%)
        
        (, , , , , bool settled, ) = market.getMarketInfo(marketId);
        assertTrue(settled);
    }
    
    function testSettleMarketRug() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        
        vm.prank(settlementBot);
        market.settleMarket(marketId, 100e18); // 90% down = RUG (>50% down)
        
        (, , , , , bool settled, ) = market.getMarketInfo(marketId);
        assertTrue(settled);
    }
    
    function testSettleMarketNoChange() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        
        vm.prank(settlementBot);
        market.settleMarket(marketId, 1005e18); // 0.5% up = NO_CHANGE
        
        (, , , , , bool settled, ) = market.getMarketInfo(marketId);
        assertTrue(settled);
    }
    
    function testCannotSettleBeforeTime() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        vm.prank(settlementBot);
        vm.expectRevert("Settlement time not reached");
        market.settleMarket(marketId, 1100e18);
    }
    
    function testClaimWinnings() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        // Trader1 bets on PUMP
        uint256 costPump = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        vm.prank(trader1);
        market.buyShares{value: costPump}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        // Trader2 bets on DUMP
        uint256 costDump = market.calculateBuyCost(marketId, PredictionMarket.Outcome.DUMP, 100);
        vm.prank(trader2);
        market.buyShares{value: costDump}(marketId, PredictionMarket.Outcome.DUMP, 100);
        
        // Settle with PUMP winning
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        vm.prank(settlementBot);
        market.settleMarket(marketId, 1150e18); // PUMP wins
        
        // Trader1 claims winnings
        uint256 balanceBefore = trader1.balance;
        vm.prank(trader1);
        market.claimWinnings(marketId);
        
        assertTrue(trader1.balance > balanceBefore, "Winner should receive funds");
        
        // Check tokens were burned
        address pumpToken = market.getPositionToken(marketId, PredictionMarket.Outcome.PUMP);
        assertEq(PositionToken(pumpToken).balanceOf(trader1), 0);
    }
    
    function testLoserCannotClaimWinnings() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        // Trader2 bets on DUMP
        uint256 costDump = market.calculateBuyCost(marketId, PredictionMarket.Outcome.DUMP, 100);
        vm.prank(trader2);
        market.buyShares{value: costDump}(marketId, PredictionMarket.Outcome.DUMP, 100);
        
        // Settle with PUMP winning
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        vm.prank(settlementBot);
        market.settleMarket(marketId, 1150e18); // PUMP wins
        
        // Trader2 tries to claim (should fail)
        vm.prank(trader2);
        vm.expectRevert("No winning shares");
        market.claimWinnings(marketId);
    }
    
    function testOnlyWinnersCanSellAfterSettlement() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        // Traders bet on different outcomes
        uint256 costPump = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        vm.prank(trader1);
        market.buyShares{value: costPump}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        uint256 costDump = market.calculateBuyCost(marketId, PredictionMarket.Outcome.DUMP, 100);
        vm.prank(trader2);
        market.buyShares{value: costDump}(marketId, PredictionMarket.Outcome.DUMP, 100);
        
        // Settle
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        vm.prank(settlementBot);
        market.settleMarket(marketId, 1150e18); // PUMP wins
        
        // Loser cannot sell
        vm.prank(trader2);
        vm.expectRevert("Only winners can sell after settlement");
        market.sellShares(marketId, PredictionMarket.Outcome.DUMP, 50);
        
        // Winner can sell
        vm.prank(trader1);
        market.sellShares(marketId, PredictionMarket.Outcome.PUMP, 50);
    }
    
    function testPositionTokensAreTransferable() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        vm.prank(trader1);
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        // Transfer tokens to trader2
        address pumpToken = market.getPositionToken(marketId, PredictionMarket.Outcome.PUMP);
        vm.prank(trader1);
        PositionToken(pumpToken).transfer(trader2, 50);
        
        assertEq(PositionToken(pumpToken).balanceOf(trader1), 50);
        assertEq(PositionToken(pumpToken).balanceOf(trader2), 50);
        
        // Trader2 can now sell transferred tokens
        vm.prank(trader2);
        market.sellShares(marketId, PredictionMarket.Outcome.PUMP, 25);
        
        assertEq(PositionToken(pumpToken).balanceOf(trader2), 25);
    }
    
    function testMultipleWinnersSplitPrizePool() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        // Both traders bet on PUMP
        uint256 cost1 = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        vm.prank(trader1);
        market.buyShares{value: cost1}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        uint256 cost2 = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        vm.prank(trader2);
        market.buyShares{value: cost2}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        // Settle with PUMP winning
        (, , , , uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        vm.warp(settlementTime + 1);
        vm.prank(settlementBot);
        market.settleMarket(marketId, 1150e18);
        
        // Both claim
        uint256 balance1Before = trader1.balance;
        uint256 balance2Before = trader2.balance;
        
        vm.prank(trader1);
        market.claimWinnings(marketId);
        
        vm.prank(trader2);
        market.claimWinnings(marketId);
        
        uint256 winnings1 = trader1.balance - balance1Before;
        uint256 winnings2 = trader2.balance - balance2Before;
        
        // Both should receive equal amounts (50/50 split since same shares)
        assertEq(winnings1, winnings2);
    }
    
    function testGetUserShares() public {
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        uint256 cost = market.calculateBuyCost(marketId, PredictionMarket.Outcome.PUMP, 100);
        vm.prank(trader1);
        market.buyShares{value: cost}(marketId, PredictionMarket.Outcome.PUMP, 100);
        
        uint256 shares = market.getUserShares(marketId, trader1, PredictionMarket.Outcome.PUMP);
        assertEq(shares, 100);
    }
    
    function testPlatformOwnerReceivesCreationFee() public {
        uint256 balanceBefore = platformOwner.balance;
        
        vm.prank(creator);
        market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        assertEq(platformOwner.balance, balanceBefore + CREATOR_FEE);
    }
    
    function testExcessCreationFeeRefunded() public {
        uint256 balanceBefore = creator.balance;
        uint256 excessPayment = CREATOR_FEE + 1 ether;
        
        vm.prank(creator);
        market.createMarket{value: excessPayment}("TOKEN-0x123", 1000e18);
        
        assertEq(creator.balance, balanceBefore - CREATOR_FEE);
    }
    
    function testMidnightCalculation() public {
        // Warp to a specific time
        vm.warp(1000000);
        
        vm.prank(creator);
        uint256 marketId = market.createMarket{value: CREATOR_FEE}("TOKEN-0x123", 1000e18);
        
        (, , , uint256 createdAt, uint256 settlementTime, , ) = market.getMarketInfo(marketId);
        
        // Settlement time should be next midnight
        assertTrue(settlementTime > createdAt);
        assertTrue(settlementTime % 86400 == 0); // Should be multiple of 1 day
    }
}
