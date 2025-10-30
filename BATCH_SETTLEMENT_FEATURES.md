# Batch Settlement & Bot Authorization Features

## New Features Added

### 1. Bot Authorization System
Admin (platform owner) can authorize multiple settlement bots:

```solidity
function authorizeBot(address _bot, bool _authorized) external;
function isAuthorizedBot(address _bot) external view returns (bool);
```

**Access Control:**
- Only platform owner can authorize/deauthorize bots
- Both authorized bots and platform owner can settle markets

### 2. Batch Settlement
Efficiently settle multiple markets in a single transaction:

```solidity
function batchSettleMarkets(uint256[] calldata _marketIds, uint256[] calldata _finalPrices) external;
```

**Features:**
- Processes array of market IDs and their final prices
- Skips already settled markets (no revert)
- Skips markets not yet ready for settlement
- Emits `BatchSettlement` event with success count
- Gas efficient for settling many markets at midnight

### 3. Helper Functions

**Get Unsettled Markets:**
```solidity
function getUnsettledMarkets(uint256[] calldata _marketIds) external view returns (uint256[] memory);
```
Returns only markets that are ready for settlement but not yet settled.

**Check Bot Authorization:**
```solidity
function isAuthorizedBot(address _bot) external view returns (bool);
```
Query if an address is authorized to settle markets.

## Usage Example

### Authorize a Bot
```solidity
// Platform owner authorizes settlement bot
predictionMarket.authorizeBot(0xBotAddress, true);

// Later, deauthorize if needed
predictionMarket.authorizeBot(0xBotAddress, false);
```

### Batch Settlement
```solidity
// Get list of markets to check
uint256[] memory marketIds = [1, 2, 3, 4, 5];

// Find which ones need settlement
uint256[] memory unsettled = predictionMarket.getUnsettledMarkets(marketIds);

// Fetch prices from oracle/API for each market
uint256[] memory prices = fetchPrices(unsettled);

// Settle all at once
predictionMarket.batchSettleMarkets(unsettled, prices);
```

## Events

```solidity
event BotAuthorized(address indexed bot, bool authorized);
event BatchSettlement(uint256[] marketIds, uint256 successCount);
```

## Test Coverage

### Bot Authorization Tests (4 tests)
- ✅ `testAuthorizeBot` - Platform owner can authorize bots
- ✅ `testUnauthorizeBot` - Can deauthorize previously authorized bots
- ✅ `testOnlyOwnerCanAuthorizeBot` - Only platform owner can authorize
- ✅ `testAuthorizedBotCanSettle` - Authorized bots can settle markets

### Batch Settlement Tests (3 tests)
- ✅ `testBatchSettleMarkets` - Successfully settles multiple markets
- ✅ `testBatchSettleArrayLengthMismatch` - Validates array lengths match
- ✅ `testBatchSettleSkipsAlreadySettled` - Gracefully skips settled markets

### Helper Function Tests (2 tests)
- ✅ `testGetUnsettledMarkets` - Returns only unsettled markets
- ✅ `testUnauthorizedBotCannotSettle` - Prevents unauthorized settlement

## Gas Optimization

Batch settlement saves gas compared to individual transactions:
- Single `batchSettleMarkets(3)`: ~16.8M gas
- 3 individual `settleMarket()`: ~17.1M gas (3 × 5.7M)
- **Savings**: ~300k gas for 3 markets, increases with more markets

## Security Features

1. **Access Control**: Only authorized bots + platform owner can settle
2. **Idempotent**: Batch settlement won't revert on already-settled markets
3. **Time-locked**: Markets can only be settled after midnight deadline
4. **No Double Settlement**: Once settled, outcome cannot be changed
