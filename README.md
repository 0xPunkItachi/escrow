# escrow

# 🔒 Locked Token Voting Power Governance (Flow Blockchain)

A decentralized **governance smart contract** that links **voting power to locked tokens**, enabling fair and time-weighted decision-making.  
Users can lock their tokens (in this case, native Flow testnet tokens represented as ETH in the EVM layer) for fixed durations to earn proportional voting power.

> 🌐 **Deployed on Flow Blockchain (Testnet)**  
> **Contract Address:** `0x9879A8Cdc01890c5ab9769Ec42b0456570F4DA03`

---

## 🧩 Overview

This smart contract introduces a **voting power system derived from locked tokens** — a simplified model of “voting escrow governance.”  
Participants gain **greater voting power the longer they lock their tokens**. The system supports creating proposals, weighted voting, and automatic result computation — all directly on-chain.

Built entirely in **Solidity**, this contract is designed for educational and demonstrative use on Flow’s EVM-compatible testnet, following strict simplicity constraints:
- **No constructors**
- **No imports**
- **No input fields in external functions**

---

## ✨ Key Features

✅ **Lock Tokens for Time-Based Voting Power**  
Lock tokens for **30, 90, or 365 days** — the longer the lock, the higher your voting weight.

✅ **Time-Weighted Voting Power**  
Voting weight = locked amount × remaining lock duration (normalized to 30-day units).

✅ **On-Chain Proposal System**  
Create proposals, vote (yes/no), and automatically determine outcomes on-chain.

✅ **Snapshot Protection**  
Voting power is **snapshotted at vote time** — users can’t withdraw or change locks to influence past votes.

✅ **Single Active Proposal**  
To maintain simplicity, only one active proposal exists at a time.

✅ **No Imports or Constructors**  
Fully self-contained Solidity smart contract for maximum transparency.

---

## 🛠️ Technical Specifications

| Parameter | Description |
|------------|--------------|
| **Blockchain** | Flow Blockchain (Testnet) |
| **Contract Address** | `0x9879A8Cdc01890c5ab9769Ec42b0456570F4DA03` |
| **Lock Durations** | 30 days, 90 days, 365 days |
| **Voting Period** | 3 days per proposal |
| **Voting Power Formula** | `power = amount × remaining_time / 30_days` |
| **Proposal Outcome** | `yes > no` (simple majority) |
| **Security Level** | Educational / Non-production |
| **Funds Locked** | ETH equivalent on Flow EVM testnet |

---

## ⚙️ Smart Contract Functions

### 🏁 Initialization
| Function | Description |
|-----------|--------------|
| `initialize()` | Sets the contract owner. Must be called once after deployment. |

---

### 🔐 Token Locking
| Function | Description |
|-----------|--------------|
| `lock30Days()` | Locks tokens for 30 days. |
| `lock90Days()` | Locks tokens for 90 days. |
| `lock365Days()` | Locks tokens for 365 days. |
| `withdrawUnlocked()` | Withdraws tokens once the lock period expires. |

> 💡 **Locking Formula:**  
> - 1 wei = 1 token unit.  
> - Voting power increases with both **amount** and **remaining time**.

---

### 🗳️ Governance Actions
| Function | Description |
|-----------|--------------|
| `createProposal()` | Creates a new proposal (only one active at a time). |
| `voteYes()` | Votes “Yes” on the active proposal using your current voting power. |
| `voteNo()` | Votes “No” on the active proposal using your current voting power. |
| `executeProposal()` | Finalizes voting after the proposal ends and records the result. |

---

### 🧾 Utility & Admin
| Function | Description |
|-----------|--------------|
| `currentVotingWeight(address)` | Returns current voting power for a user. |
| `getLockedAmount(address)` | Shows locked token amount for a user. |
| `getUnlockTime(address)` | Displays the unlock timestamp for a user. |
| `emergencyWithdrawAll()` | Owner-only emergency function to withdraw contract balance. |

---

## 🧠 How It Works

1. **Initialize**
   ```solidity
   initialize()
