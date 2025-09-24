# Music Royalty Distribution Platform

A blockchain-powered platform that automates royalty calculation and distribution for artists, labels, and rights holders across streaming platforms and music usages.

## Overview

This platform addresses the complexity and delays in royalty payments by providing transparent, immutable, and automated calculation and distribution of royalties based on verified usage data. The system ensures that every stakeholder is paid fairly and on time.

## Key Features

### Royalty Ingestion and Tracking
- Track streaming plays, radio spins, downloads, and user-generated content usage
- Attribution by ISRC, ISWC, and other identifiers
- Deduplication and fraud detection for play events
- Event proofs via cryptographic hashes

### Rights Management
- Support for multiple rights holders per track (writers, publishers, labels)
- Split percentages per right holder
- Support for sub-publishing and territorial rights
- Role-based permissions for catalog management

### Royalty Calculation
- Dynamic per-stream payout rates by platform and territory
- Tiered payout rules (free vs premium users)
- Minimum payout thresholds and carryover balances
- Recoupable advances and chargebacks

### Distribution & Payouts
- Automated on-chain settlement per cycle (weekly/monthly)
- Multiple payout currencies and stablecoins
- Bulk payouts with batched transactions
- Ledger of all disbursements

### Dispute Resolution
- Stakeholder dispute submission and tracking
- Evidence submission using hashed documents
- Transparent adjudication workflow
- Audit trail and final settlement

## Smart Contract Architecture

- Royalty Registry Contract: Tracks works, rights holders, and ownership splits
- Usage Ledger Contract: Receives and verifies usage events and accrues royalties
- Payouts Contract: Executes distributions to rights holders

Note: For this MVP, a single contract consolidates core features without cross-contract calls.

## Data Model

- Track: id, isrc, title, rights-holders (list), splits
- UsageEvent: id, track-id, platform, territory, units, event-hash
- Accrual: track-id, amount, currency
- Payout: cycle-id, track-id, recipient, amount, txid

## Getting Started

### Prerequisites
- Clarinet installed
- Node.js and npm
- Stacks wallet (Hiro)

### Development
```bash
clarinet check
```

## Security
- Input validation on all public functions
- Role-based access control for catalog and payout management
- Immutable audit logs

## License
MIT