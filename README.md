# EquiShare Smart Contract

EquiShare is a multi-stakeholder profit distribution smart contract built on the Stacks blockchain that allows for equitable and transparent sharing of revenue or profits among project participants.

## Overview

EquiShare enables organizations to:
- Distribute profits automatically to stakeholders based on percentage allocations
- Manage stakeholder participation through voting
- Propose and vote on changes to profit sharing percentages
- Integrate AI recommendations for optimal profit distribution

## Features

- **Automated Distribution**: Profits are automatically distributed to stakeholders on a configurable schedule
- **Democratic Governance**: Stakeholders can vote on important contract changes based on their ownership percentages
- **AI-Powered Recommendations**: Built-in AI oracle provides suggestions for equitable profit distribution
- **Transparent Operation**: All stakeholder information and contract operations are publicly visible
- **Simple Deposit System**: Users can deposit funds to be distributed according to the current percentage allocations

## Key Functions

### For Contract Owner
- `add-stakeholder`: Add a new stakeholder with a specified percentage allocation

### For Stakeholders
- `deposit`: Deposit funds into the contract
- `propose-percentage-change`: Propose a change to a stakeholder's percentage allocation
- `vote`: Vote on proposed changes
- `finalize-vote`: Complete a vote once the voting period has ended
- `distribute-profits`: Trigger distribution of profits to all stakeholders (when the payout interval has passed)

### Read-Only Functions
- `get-stakeholder`: Get information about a specific stakeholder
- `is-stakeholder`: Check if an address is a registered stakeholder
- `get-vote`: Get information about a specific vote
- `get-stakeholder-vote`: Get a stakeholder's vote on a specific proposal
- `get-balance`: Get the current contract balance
- `get-next-payout-info`: Get information about the next scheduled payout
- `get-ai-recommendation`: Get AI recommendations for a specific vote
- `get-total-percentage-allocated`: Get the total percentage allocated to all stakeholders

## Requirements

- Stacks blockchain compatible wallet
- Minimum deposit amount: 1 STX (1,000,000 microSTX)

## Usage Example

```clarity
;; Add a stakeholder with 20% allocation (contract owner only)
(contract-call? .equishare add-stakeholder 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u20)

;; Deposit 10 STX to the contract
(contract-call? .equishare deposit u10000000)

;; Propose changing a stakeholder's allocation to 25%
(contract-call? .equishare propose-percentage-change 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u25)

;; Vote on a proposal (yes or no)
(contract-call? .equishare vote u1 "yes")

;; Finalize a vote after voting period ends
(contract-call? .equishare finalize-vote u1)

;; Distribute profits to all stakeholders
(contract-call? .equishare distribute-profits)
```

## Security Considerations

- Contract owner has special privileges for adding stakeholders
- All stakeholder percentage allocations must sum to 100% or less
- The contract validates all inputs to prevent abuse
- Voting has a minimum participation threshold and required approval percentage
