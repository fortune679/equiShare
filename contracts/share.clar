;; EquiShare: Multi-Stakeholder Profit Distribution Smart Contract
;; Author: Claude
;; Date: February 27, 2025

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-stakeholder (err u101))
(define-constant err-invalid-percentage (err u102))
(define-constant err-no-funds (err u103))
(define-constant err-vote-exists (err u104))
(define-constant err-vote-not-found (err u105))
(define-constant err-invalid-vote-status (err u106))
(define-constant err-voting-period-active (err u107))
(define-constant err-min-deposit-required (err u108))
(define-constant min-deposit-amount u1000000) ;; 1 STX

;; Data Variables
(define-data-var last-payout-height uint u0)
(define-data-var payout-interval uint u144) ;; Approximately daily (144 blocks per day on Stacks)
(define-data-var total-funds uint u0)
(define-data-var next-vote-id uint u0)
(define-data-var min-vote-percentage uint u60) ;; 60% required to pass a vote

;; Data Maps
(define-map stakeholders principal 
  {
    percentage: uint,
    total-deposited: uint,
    total-withdrawn: uint,
    joined-block: uint,
    last-distribution: uint
  }
)

(define-map votes uint 
  {
    proposer: principal,
    proposal-type: (string-utf8 20),
    target: principal,
    new-percentage: uint,
    proposed-at: uint,
    expires-at: uint,
    status: (string-utf8 10),
    yes-votes: uint,
    no-votes: uint,
    vote-power: uint
  }
)

(define-map stakeholder-votes 
  { vote-id: uint, voter: principal } 
  { vote: (string-utf8 3), weight: uint }
)

;; AI Oracle Integration
;; This represents an interface to an AI oracle that can analyze voting patterns
;; and suggest optimal profit distributions
(define-map ai-recommendations uint 
  {
    recommendation-type: (string-utf8 20),
    target: principal,
    suggested-percentage: uint,
    confidence-score: uint,
    reasoning: (string-utf8 500)
  }
)

;; Read-Only Functions

;; Get stakeholder information
(define-read-only (get-stakeholder (address principal))
  (default-to 
    {
      percentage: u0,
      total-deposited: u0,
      total-withdrawn: u0,
      joined-block: u0,
      last-distribution: u0
    } 
    (map-get? stakeholders address)
  )
)

;; Check if an address is a stakeholder
(define-read-only (is-stakeholder (address principal))
  (is-some (map-get? stakeholders address))
)

;; Get vote information
(define-read-only (get-vote (vote-id uint))
  (map-get? votes vote-id)
)

;; Get stakeholder's vote on a specific proposal
(define-read-only (get-stakeholder-vote (vote-id uint) (voter principal))
  (map-get? stakeholder-votes { vote-id: vote-id, voter: voter })
)

;; Get contract balance
(define-read-only (get-balance)
  (var-get total-funds)
)

;; Get time until next payout
(define-read-only (get-next-payout-info)
  (let (
    (last-payout (var-get last-payout-height))
    (interval (var-get payout-interval))
    (current-height block-height)
  )
  {
    last-payout: last-payout,
    next-payout: (+ last-payout interval),
    blocks-remaining: (if (>= current-height (+ last-payout interval))
                        u0
                        (- (+ last-payout interval) current-height))
  })
)

;; Get AI recommendation for a specific vote
(define-read-only (get-ai-recommendation (vote-id uint))
  (map-get? ai-recommendations vote-id)
)

;; Public Functions

;; Add a stakeholder (owner only)
(define-public (add-stakeholder (address principal) (percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (< u0 percentage) err-invalid-percentage)
    (asserts! (<= percentage u100) err-invalid-percentage)
    (asserts! (is-valid-percentage-total (+ percentage (get-total-percentage-excluding address))) err-invalid-percentage)
    
    (map-set stakeholders address {
      percentage: percentage,
      total-deposited: u0,
      total-withdrawn: u0,
      joined-block: block-height,
      last-distribution: block-height
    })
    
    (ok true)
  )
)

;; Deposit funds
(define-public (deposit)
  (let (
    (amount (get-stx-balance))
    (sender tx-sender)
    (stakeholder-info (get-stakeholder sender))
  )
    (begin
      (asserts! (> amount u0) err-no-funds)
      (asserts! (>= amount min-deposit-amount) err-min-deposit-required)
      
      ;; If not a stakeholder yet, add with 0% (will need a vote to get percentage)
      (if (is-eq (get percentage stakeholder-info) u0)
        (map-set stakeholders sender {
          percentage: u0,
          total-deposited: amount,
          total-withdrawn: u0,
          joined-block: block-height,
          last-distribution: block-height
        })
        (map-set stakeholders sender {
          percentage: (get percentage stakeholder-info),
          total-deposited: (+ (get total-deposited stakeholder-info) amount),
          total-withdrawn: (get total-withdrawn stakeholder-info),
          joined-block: (get joined-block stakeholder-info),
          last-distribution: (get last-distribution stakeholder-info)
        })
      )
      
      (stx-transfer? amount sender (as-contract tx-sender))
      (var-set total-funds (+ (var-get total-funds) amount))
      (ok true)
    )
  )
)

;; Distribute profits to all stakeholders
(define-public (distribute-profits)
  (let (
    (current-height block-height)
    (last-payout (var-get last-payout-height))
    (interval (var-get payout-interval))
  )
    (begin
      (asserts! (>= current-height (+ last-payout interval)) err-invalid-vote-status)
      (asserts! (> (var-get total-funds) u0) err-no-funds)
      
      ;; Execute the distribution process
      (var-set last-payout-height current-height)
      (ok (distribute-to-all-stakeholders))
    )
  )
)

;; Propose a change to a stakeholder's percentage
(define-public (propose-percentage-change (target principal) (new-percentage uint))
  (let (
    (vote-id (var-get next-vote-id))
    (proposer tx-sender)
  )
    (begin
      (asserts! (is-stakeholder proposer) err-not-stakeholder)
      (asserts! (<= new-percentage u100) err-invalid-percentage)
      (asserts! (is-valid-percentage-total (+ new-percentage (get-total-percentage-excluding target))) err-invalid-percentage)
      
      (map-set votes vote-id {
        proposer: proposer,
        proposal-type: "percentage-change",
        target: target,
        new-percentage: new-percentage,
        proposed-at: block-height,
        expires-at: (+ block-height u144), ;; 24 hours to vote
        status: "active",
        yes-votes: u0,
        no-votes: u0,
        vote-power: u0
      })
      
      ;; Generate AI recommendation for this vote
      (generate-ai-recommendation vote-id)
      
      (var-set next-vote-id (+ vote-id u1))
      (ok vote-id)
    )
  )
)

;; Vote on a proposal
(define-public (vote (vote-id uint) (vote-value (string-utf8 3)))
  (let (
    (voter tx-sender)
    (vote-info (unwrap! (map-get? votes vote-id) err-vote-not-found))
    (voter-info (unwrap! (map-get? stakeholders voter) err-not-stakeholder))
    (vote-weight (get percentage voter-info))
  )
    (begin
      (asserts! (is-eq (get status vote-info) "active") err-invalid-vote-status)
      (asserts! (< block-height (get expires-at vote-info)) err-invalid-vote-status)
      (asserts! (or (is-eq vote-value "yes") (is-eq vote-value "no")) err-invalid-vote-status)
      (asserts! (is-none (map-get? stakeholder-votes { vote-id: vote-id, voter: voter })) err-vote-exists)
      
      ;; Record the vote
      (map-set stakeholder-votes { vote-id: vote-id, voter: voter } { vote: vote-value, weight: vote-weight })
      
      ;; Update vote tallies
      (if (is-eq vote-value "yes")
        (map-set votes vote-id 
          (merge vote-info { 
            yes-votes: (+ (get yes-votes vote-info) vote-weight),
            vote-power: (+ (get vote-power vote-info) vote-weight)
          })
        )
        (map-set votes vote-id 
          (merge vote-info { 
            no-votes: (+ (get no-votes vote-info) vote-weight),
            vote-power: (+ (get vote-power vote-info) vote-weight)
          })
        )
      )
      
      (ok true)
    )
  )
)

;; Finalize a vote if voting period has ended
(define-public (finalize-vote (vote-id uint))
  (let (
    (vote-info (unwrap! (map-get? votes vote-id) err-vote-not-found))
    (current-height block-height)
  )
    (begin
      (asserts! (is-eq (get status vote-info) "active") err-invalid-vote-status)
      (asserts! (>= current-height (get expires-at vote-info)) err-voting-period-active)
      
      (if (and 
            (>= (get vote-power vote-info) u50) ;; At least 50% participation
            (>= (get yes-votes vote-info) (/ (* (get vote-power vote-info) (var-get min-vote-percentage)) u100))
          )
        ;; Vote passed
        (begin
          (map-set votes vote-id (merge vote-info { status: "passed" }))
          (if (is-eq (get proposal-type vote-info) "percentage-change")
            (execute-percentage-change (get target vote-info) (get new-percentage vote-info))
            (ok true)
          )
        )
        ;; Vote failed
        (begin
          (map-set votes vote-id (merge vote-info { status: "failed" }))
          (ok false)
        )
      )
    )
  )
)

;; Private Functions

;; Helper to calculate total percentage allocated excluding a specific address
(define-private (get-total-percentage-excluding (exclude-address principal))
  (fold percentage-sum-except (map-keys stakeholders) u0 exclude-address)
)

;; Helper for folding to sum percentages
(define-private (percentage-sum-except (address principal) (total uint) (exclude principal))
  (if (is-eq address exclude)
    total
    (+ total (get percentage (get-stakeholder address)))
  )
)

;; Check if percentage total is valid (should be <= 100%)
(define-private (is-valid-percentage-total (total uint))
  (<= total u100)
)

;; Execute a percentage change after successful vote
(define-private (execute-percentage-change (target principal) (new-percentage uint))
  (let (
    (stakeholder-info (get-stakeholder target))
  )
    (begin
      (map-set stakeholders target 
        (merge stakeholder-info { percentage: new-percentage })
      )
      (ok true)
    )
  )
)

;; Distribute profits to all stakeholders
(define-private (distribute-to-all-stakeholders)
  (let (
    (total-to-distribute (var-get total-funds))
  )
    (begin
      (var-set total-funds u0)
      (fold distribute-to-stakeholder (map-keys stakeholders) total-to-distribute)
    )
  )
)

;; Distribute profits to a single stakeholder
(define-private (distribute-to-stakeholder (address principal) (remaining uint))
  (let (
    (stakeholder-info (get-stakeholder address))
    (percentage (get percentage stakeholder-info))
    (amount-to-send (/ (* remaining percentage) u100))
  )
    (begin
      (if (> amount-to-send u0)
        (as-contract (stx-transfer? amount-to-send tx-sender address))
        true
      )
      
      (map-set stakeholders address 
        (merge stakeholder-info { 
          total-withdrawn: (+ (get total-withdrawn stakeholder-info) amount-to-send),
          last-distribution: block-height
        })
      )
      
      ;; Return remaining funds
      (- remaining amount-to-send)
    )
  )
)

;; Generate AI recommendation for a vote
(define-private (generate-ai-recommendation (vote-id uint))
  (let (
    (vote-info (unwrap! (map-get? votes vote-id) err-vote-not-found))
  )
    (begin
      ;; In a real implementation, this would call an oracle
      ;; Here we simulate with a simplified recommendation
      (if (is-eq (get proposal-type vote-info) "percentage-change")
        (map-set ai-recommendations vote-id {
          recommendation-type: "percentage-analysis",
          target: (get target vote-info),
          suggested-percentage: (get new-percentage vote-info),
          confidence-score: u75,
          reasoning: "Based on stakeholder contributions and past distribution patterns, this change aligns with equitable distribution principles. Historical voting patterns suggest this has a 75% chance of approval."
        })
        true
      )
      true
    )
  )
)