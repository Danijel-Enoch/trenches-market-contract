# Share Token Reward System

## Overview

The PredictionMarket contract now includes a comprehensive share token reward system that incentivizes market creators and rewards winners. Users earn share tokens (MST - Market Share Token) which can later be redeemed for protocol tokens deposited by the admin.

## Key Features

### 1. Share Token (MST)
- ERC20 token automatically deployed with the PredictionMarket contract
- Minted as rewards for various activities
- Can be burned to claim proportional protocol tokens

### 2. Reward Distribution

#### Market Creation Rewards
- **Amount**: 1,000 MST tokens (1000 * 1e18)
- **When**: Immediately upon creating a new market
- **Purpose**: Incentivize market creation

#### Trading Activity Rewards
- **Amount**: 10 MST tokens (10 * 1e18) per trade
- **Who**: Market creator earns these
- **When**: Each time someone buys shares in their market
- **Purpose**: Reward market creators for attracting trading activity

#### Winner Rewards
- **Amount**: shares * 100 MST tokens
- **Who**: Winners who claim their winnings
- **When**: Upon claiming winnings after market settlement
- **Example**: If you win with 100 shares, you get 10,000 MST tokens
- **Purpose**: Bonus reward for successful predictions

### 3. Protocol Token Redemption

The admin can deposit protocol tokens into the contract, which users can claim proportionally based on their share token holdings.

#### Process:
1. Admin sets the protocol token address (one-time operation)
2. Admin deposits protocol tokens to the contract
3. Users redeem their share tokens for protocol tokens
4. Share tokens are burned upon redemption
5. Protocol tokens distributed proportionally

#### Calculation:
```
Protocol Tokens Received = (Protocol Token Balance × User's Share Tokens) / Total Share Tokens Issued
```

## Contract Functions

### For Admin

#### `setProtocolToken(address _protocolToken)`
- Sets the protocol token address
- Can only be called once
- Only callable by platform owner

#### `depositProtocolTokens(uint256 _amount)`
- Deposits protocol tokens for distribution
- Requires prior approval from the token contract
- Only callable by platform owner
- Emits `ProtocolTokenDeposited` event

### For Users

#### `claimProtocolTokens(uint256 _shareAmount)`
- Burns user's share tokens and receives proportional protocol tokens
- Requires sufficient share token balance
- Emits `ProtocolTokenClaimed` event

### View Functions

#### `getShareTokenAddress()`
- Returns the address of the share token contract

#### `getProtocolTokenAddress()`
- Returns the address of the protocol token

#### `getUserShareBalance(address _user)`
- Returns a user's share token balance

#### `getProtocolTokenInfo()`
- Returns current protocol token balance and total shares issued

## Events

```solidity
event ShareTokensEarned(address indexed user, uint256 amount, string reason);
event ProtocolTokenDeposited(uint256 amount);
event ProtocolTokenClaimed(address indexed user, uint256 shareTokensBurned, uint256 protocolTokensReceived);
```

## Example Workflow

### Scenario: Alice creates a market, Bob trades, and wins

1. **Market Creation**
   - Alice creates a market for "TOKEN" prediction
   - Alice receives: 1,000 MST tokens

2. **Trading Activity**
   - Bob buys 100 shares predicting PUMP
   - Alice receives: 10 MST tokens (trading reward)
   - Bob's 100 shares are minted to his address

3. **Market Settlement**
   - Bot settles the market with PUMP outcome
   - Bob won his prediction

4. **Winner Claims**
   - Bob claims his winnings
   - Bob receives: ETH winnings + (100 × 100 = 10,000 MST tokens)

5. **Protocol Token Distribution**
   - Admin deposits 100,000 protocol tokens
   - Total MST issued: 11,010 tokens (Alice: 1,010, Bob: 10,000)
   - Bob redeems his 10,000 MST:
     - Receives: (100,000 × 10,000) / 11,010 ≈ 90,827 protocol tokens
   - Alice redeems her 1,010 MST:
     - Receives: (100,000 × 1,010) / 11,010 ≈ 9,173 protocol tokens

## Configuration Constants

```solidity
uint256 public constant CREATOR_INITIAL_SHARES = 1000 * 1e18;  // Initial reward for market creation
uint256 public constant TRADER_SHARE_REWARD = 10 * 1e18;       // Reward per trade to creator
uint256 public constant WINNER_SHARE_MULTIPLIER = 100;          // Multiplier for winner rewards
```

## Security Considerations

1. **Protocol Token Setting**: Can only be set once to prevent manipulation
2. **Proportional Distribution**: Share tokens determine proportional claim to protocol tokens
3. **Burn Mechanism**: Share tokens are burned upon claiming to prevent double-claiming
4. **Access Control**: Only platform owner can deposit protocol tokens

## Testing

Comprehensive tests are available in `test/ShareTokenReward.t.sol`:
- `testCreatorReceivesShareTokens`: Verifies creator receives initial shares
- `testCreatorEarnsSharesOnTrading`: Verifies trading rewards
- `testWinnerReceivesShareTokens`: Verifies winner bonus rewards
- `testProtocolTokenClaim`: Verifies redemption mechanism
- `testProtocolTokenDistribution`: Verifies proportional distribution

Run tests with:
```bash
forge test --match-contract ShareTokenRewardTest -vv
```

## Integration Notes

- Share tokens are automatically deployed with the PredictionMarket contract
- No additional deployment steps required for the share token
- Protocol token must be an ERC20-compliant contract
- Ensure protocol token approvals before depositing
