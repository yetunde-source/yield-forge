;; Title: YieldForge Protocol - Intelligent Yield Optimization & Governance Hub
;;
;; Summary:
;; YieldForge transforms traditional staking into an intelligent yield optimization
;; engine with progressive reward tiers, democratic governance mechanisms, and
;; institutional-grade risk management. Users unlock enhanced earning potential
;; through strategic time commitments while participating in protocol evolution.
;;
;; Description:
;; The YieldForge Protocol represents a paradigm shift in DeFi yield generation,
;; combining adaptive staking mechanics with community-driven governance. Through
;; sophisticated tier-based reward optimization and time-locked staking strategies,
;; participants can maximize their capital efficiency while maintaining full
;; control over protocol direction. Built with enterprise-level security features
;; including emergency safeguards and mandatory cooling periods, YieldForge ensures
;; sustainable long-term value creation for all stakeholders.

;; TOKEN DEFINITIONS

(define-fungible-token ANALYTICS-TOKEN u0)

;; CORE CONSTANTS

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-PROTOCOL (err u1001))
(define-constant ERR-INVALID-AMOUNT (err u1002))
(define-constant ERR-INSUFFICIENT-STX (err u1003))
(define-constant ERR-COOLDOWN-ACTIVE (err u1004))
(define-constant ERR-NO-STAKE (err u1005))
(define-constant ERR-BELOW-MINIMUM (err u1006))
(define-constant ERR-PAUSED (err u1007))

;; PROTOCOL STATE

(define-data-var contract-paused bool false)
(define-data-var emergency-mode bool false)
(define-data-var stx-pool uint u0)
(define-data-var base-reward-rate uint u500) ;; 5% base rate (100 = 1%)
(define-data-var bonus-rate uint u100) ;; 1% bonus for longer staking
(define-data-var minimum-stake uint u1000000) ;; Minimum stake amount
(define-data-var cooldown-period uint u1440) ;; 24 hour cooldown in blocks
(define-data-var proposal-count uint u0)

;; DATA STRUCTURES

;; Governance proposal tracking
(define-map Proposals
  { proposal-id: uint }
  {
    creator: principal,
    description: (string-utf8 256),
    start-block: uint,
    end-block: uint,
    executed: bool,
    votes-for: uint,
    votes-against: uint,
    minimum-votes: uint,
  }
)

;; User portfolio and tier status
(define-map UserPositions
  principal
  {
    total-collateral: uint,
    total-debt: uint,
    health-factor: uint,
    last-updated: uint,
    stx-staked: uint,
    analytics-tokens: uint,
    voting-power: uint,
    tier-level: uint,
    rewards-multiplier: uint,
  }
)

;; Active staking positions with time locks
(define-map StakingPositions
  principal
  {
    amount: uint,
    start-block: uint,
    last-claim: uint,
    lock-period: uint,
    cooldown-start: (optional uint),
    accumulated-rewards: uint,
  }
)

;; Tier configuration and benefits
(define-map TierLevels
  uint
  {
    minimum-stake: uint,
    reward-multiplier: uint,
    features-enabled: (list 10 bool),
  }
)

;; PUBLIC FUNCTIONS - CORE SETUP

;; Initialize protocol parameters and establish tier structure
(define-public (initialize-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; Configure Bronze Tier (Entry Level)
    (map-set TierLevels u1 {
      minimum-stake: u1000000, ;; 1M uSTX
      reward-multiplier: u100, ;; 1x base multiplier
      features-enabled: (list true false false false false false false false false false),
    })
    ;; Configure Silver Tier (Intermediate)
    (map-set TierLevels u2 {
      minimum-stake: u5000000, ;; 5M uSTX
      reward-multiplier: u150, ;; 1.5x multiplier
      features-enabled: (list true true true false false false false false false false),
    })
    ;; Configure Gold Tier (Premium)
    (map-set TierLevels u3 {
      minimum-stake: u10000000, ;; 10M uSTX
      reward-multiplier: u200, ;; 2x multiplier
      features-enabled: (list true true true true true false false false false false),
    })
    (ok true)
  )
)

;; PUBLIC FUNCTIONS - STAKING

;; Stake STX tokens with optional time commitment for enhanced yield
(define-public (stake-stx
    (amount uint)
    (lock-period uint)
  )
  (let ((current-position (default-to {
      total-collateral: u0,
      total-debt: u0,
      health-factor: u0,
      last-updated: u0,
      stx-staked: u0,
      analytics-tokens: u0,
      voting-power: u0,
      tier-level: u0,
      rewards-multiplier: u100,
    }
      (map-get? UserPositions tx-sender)
    )))
    ;; Validate staking parameters
    (asserts! (is-valid-lock-period lock-period) ERR-INVALID-PROTOCOL)
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (>= amount (var-get minimum-stake)) ERR-BELOW-MINIMUM)
    ;; Execute STX transfer to protocol vault
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    ;; Calculate new tier status and reward multipliers
    (let (
        (new-total-stake (+ (get stx-staked current-position) amount))
        (tier-info (get-tier-info new-total-stake))
        (lock-multiplier (calculate-lock-multiplier lock-period))
      )
      ;; Register new staking position
      (map-set StakingPositions tx-sender {
        amount: amount,
        start-block: stacks-block-height,
        last-claim: stacks-block-height,
        lock-period: lock-period,
        cooldown-start: none,
        accumulated-rewards: u0,
      })
      ;; Update user profile with enhanced tier benefits
      (map-set UserPositions tx-sender
        (merge current-position {
          stx-staked: new-total-stake,
          tier-level: (get tier-level tier-info),
          rewards-multiplier: (* (get reward-multiplier tier-info) lock-multiplier),
        })
      )
      ;; Update global STX pool metrics
      (var-set stx-pool (+ (var-get stx-pool) amount))
      (ok true)
    )
  )
)

;; Begin unstaking process with mandatory security cooldown
(define-public (initiate-unstake (amount uint))
  (let (
      (staking-position (unwrap! (map-get? StakingPositions tx-sender) ERR-NO-STAKE))
      (current-amount (get amount staking-position))
    )
    ;; Validate withdrawal request
    (asserts! (>= current-amount amount) ERR-INSUFFICIENT-STX)
    (asserts! (is-none (get cooldown-start staking-position)) ERR-COOLDOWN-ACTIVE)
    ;; Activate security cooldown period
    (map-set StakingPositions tx-sender
      (merge staking-position { cooldown-start: (some stacks-block-height) })
    )
    (ok true)
  )
)