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

;; Complete unstaking after mandatory cooldown period
(define-public (complete-unstake)
  (let (
      (staking-position (unwrap! (map-get? StakingPositions tx-sender) ERR-NO-STAKE))
      (cooldown-start (unwrap! (get cooldown-start staking-position) ERR-NOT-AUTHORIZED))
    )
    ;; Verify cooldown period completion
    (asserts!
      (>= (- stacks-block-height cooldown-start) (var-get cooldown-period))
      ERR-COOLDOWN-ACTIVE
    )
    ;; Execute STX return to user wallet
    (try! (as-contract (stx-transfer? (get amount staking-position) tx-sender tx-sender)))
    ;; Clean up staking position record
    (map-delete StakingPositions tx-sender)
    (ok true)
  )
)

;; PUBLIC FUNCTIONS - GOVERNANCE

;; Submit new governance proposal for community voting
(define-public (create-proposal
    (description (string-utf8 256))
    (voting-period uint)
  )
  (let (
      (user-position (unwrap! (map-get? UserPositions tx-sender) ERR-NOT-AUTHORIZED))
      (proposal-id (+ (var-get proposal-count) u1))
    )
    ;; Validate proposer credentials and parameters
    (asserts! (>= (get voting-power user-position) u1000000) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-description description) ERR-INVALID-PROTOCOL)
    (asserts! (is-valid-voting-period voting-period) ERR-INVALID-PROTOCOL)
    ;; Create new governance proposal
    (map-set Proposals { proposal-id: proposal-id } {
      creator: tx-sender,
      description: description,
      start-block: stacks-block-height,
      end-block: (+ stacks-block-height voting-period),
      executed: false,
      votes-for: u0,
      votes-against: u0,
      minimum-votes: u1000000,
    })
    ;; Update proposal counter
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

;; Cast weighted vote on active governance proposal
(define-public (vote-on-proposal
    (proposal-id uint)
    (vote-for bool)
  )
  (let (
      (proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id })
        ERR-INVALID-PROTOCOL
      ))
      (user-position (unwrap! (map-get? UserPositions tx-sender) ERR-NOT-AUTHORIZED))
      (voting-power (get voting-power user-position))
      (max-proposal-id (var-get proposal-count))
    )
    ;; Validate voting eligibility and timing
    (asserts! (< stacks-block-height (get end-block proposal)) ERR-NOT-AUTHORIZED)
    (asserts! (and (> proposal-id u0) (<= proposal-id max-proposal-id))
      ERR-INVALID-PROTOCOL
    )
    ;; Record weighted vote based on user's staking power
    (map-set Proposals { proposal-id: proposal-id }
      (merge proposal {
        votes-for: (if vote-for
          (+ (get votes-for proposal) voting-power)
          (get votes-for proposal)
        ),
        votes-against: (if vote-for
          (get votes-against proposal)
          (+ (get votes-against proposal) voting-power)
        ),
      })
    )
    (ok true)
  )
)

;; PUBLIC FUNCTIONS - EMERGENCY

;; Emergency protocol pause for critical situations
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

;; Resume normal protocol operations after emergency
(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

;; READ-ONLY FUNCTIONS - GETTERS

;; Retrieve contract owner address
(define-read-only (get-contract-owner)
  (ok CONTRACT-OWNER)
)

;; Get total STX locked in protocol vault
(define-read-only (get-stx-pool)
  (ok (var-get stx-pool))
)

;; Get current proposal count for governance tracking
(define-read-only (get-proposal-count)
  (ok (var-get proposal-count))
)

;; PRIVATE FUNCTIONS - UTILITIES

;; Calculate user tier level and reward multiplier based on stake
(define-private (get-tier-info (stake-amount uint))
  (if (>= stake-amount u10000000)
    {
      tier-level: u3,
      reward-multiplier: u200,
    } ;; Gold Tier: 2x rewards
    (if (>= stake-amount u5000000)
      {
        tier-level: u2,
        reward-multiplier: u150,
      } ;; Silver Tier: 1.5x rewards
      {
        tier-level: u1,
        reward-multiplier: u100,
      } ;; Bronze Tier: 1x rewards
    )
  )
)

;; Calculate time-lock bonus multiplier for enhanced rewards
(define-private (calculate-lock-multiplier (lock-period uint))
  (if (>= lock-period u8640) ;; 2 months lock
    u150 ;; 1.5x bonus multiplier
    (if (>= lock-period u4320) ;; 1 month lock
      u125 ;; 1.25x bonus multiplier
      u100 ;; No lock bonus
    )
  )
)

;; Compute accumulated rewards based on staking position and duration
(define-private (calculate-rewards
    (user principal)
    (blocks uint)
  )
  (let (
      (staking-position (unwrap! (map-get? StakingPositions user) u0))
      (user-position (unwrap! (map-get? UserPositions user) u0))
      (stake-amount (get amount staking-position))
      (base-rate (var-get base-reward-rate))
      (multiplier (get rewards-multiplier user-position))
    )
    ;; Formula: (stake * rate * multiplier * blocks) / normalization factor
    (/ (* (* (* stake-amount base-rate) multiplier) blocks) u14400000)
  )
)

;; PRIVATE FUNCTIONS - VALIDATION

;; Validate proposal description meets requirements
(define-private (is-valid-description (desc (string-utf8 256)))
  (and
    (>= (len desc) u10) ;; Minimum 10 characters for clarity
    (<= (len desc) u256) ;; Maximum 256 characters for conciseness
  )
)

;; Validate lock period is within acceptable options
(define-private (is-valid-lock-period (lock-period uint))
  (or
    (is-eq lock-period u0) ;; No lock period
    (is-eq lock-period u4320) ;; 1 month lock (30 days * 144 blocks)
    (is-eq lock-period u8640) ;; 2 months lock (60 days * 144 blocks)
  )
)

;; Validate voting period duration for governance proposals
(define-private (is-valid-voting-period (period uint))
  (and
    (>= period u100) ;; Minimum voting period (~42 minutes)
    (<= period u2880) ;; Maximum voting period (~20 hours)
  )
)
