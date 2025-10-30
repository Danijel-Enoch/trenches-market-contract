# Prediction Market Test Suite

## Overview
Comprehensive Solidity test suite for the PredictionMarket contract with **24 passing tests** covering all core functionality.

## Test Coverage

### Market Creation (4 tests)
- ✅ `testCreateMarket` - Verifies market creation with proper initialization
- ✅ `testCreateMarketInsufficientFee` - Ensures 0.01 ETH fee is required
- ✅ `testCreateMarketInvalidPrice` - Rejects zero initial price
- ✅ `testMidnightCalculation` - Validates settlement time at next midnight

### Buying & Selling Shares (7 tests)
- ✅ `testBuyShares` - Users receive ERC20 position tokens when buying
- ✅ `testBuyMultipleOutcomes` - Users can bet on multiple outcomes
- ✅ `testBondingCurve` - Price increases with supply (quadratic bonding curve)
- ✅ `testSellShares` - Users can sell shares and tokens are burned
- ✅ `testSellInsufficientShares` - Prevents selling more than owned
- ✅ `testCannotBuyAfterSettlement` - Markets close after settlement
- ✅ `testPositionTokensAreTransferable` - ERC20 tokens are fully transferable

### Market Settlement (6 tests)
- ✅ `testSettleMarketPump` - Correctly identifies +10% price movement
- ✅ `testSettleMarketDump` - Correctly identifies -10% price movement
- ✅ `testSettleMarketMoon` - Correctly identifies +50% price movement
- ✅ `testSettleMarketRug` - Correctly identifies -50% price movement
- ✅ `testSettleMarketNoChange` - Correctly identifies minimal price change
- ✅ `testCannotSettleBeforeTime` - Prevents early settlement

### Winner Claims & Prize Distribution (5 tests)
- ✅ `testClaimWinnings` - Winners can claim proportional share of prize pool
- ✅ `testLoserCannotClaimWinnings` - Losers cannot claim
- ✅ `testOnlyWinnersCanSellAfterSettlement` - Only winning outcome holders can sell post-settlement
- ✅ `testMultipleWinnersSplitPrizePool` - Multiple winners split fairly

### Fee Management (2 tests)
- ✅ `testPlatformOwnerReceivesCreationFee` - 0.01 ETH goes to platform
- ✅ `testExcessCreationFeeRefunded` - Overpayment is refunded
- ✅ `testGetUserShares` - Query user position balances

## Key Features Tested

1. **ERC20 Position Tokens**: Users receive actual transferable ERC20 tokens
2. **Bonding Curve Pricing**: Dynamic pricing based on supply
3. **5 Outcomes**: PUMP, DUMP, NO_CHANGE, RUG, MOON
4. **Fee Structure**: 0.1% creator fee + 1% platform fee on trades
5. **Winner-Takes-All**: Prize pool distributed to winning outcome holders
6. **Daily Settlement**: Markets settle at midnight

## Running Tests

```bash
forge test --match-path test/PredictionMarket.t.sol
```

## Gas Usage
- Market Creation: ~5.5M gas (includes deploying 5 ERC20 tokens)
- Buy Shares: ~140k gas average
- Sell Shares: ~150k gas average
- Settlement: ~170k gas
- Claim Winnings: ~120k gas
