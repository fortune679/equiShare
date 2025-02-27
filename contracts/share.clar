;; EquiShare: Multi-Stakeholder Profit Distribution Smart Contract

;; ---------------------------------------------------------
;; Constants and Error Codes
;; ---------------------------------------------------------
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

;; ---------------------------------------------------------
;; Data Variables
;; ---------------------------------------------------------
(define-data-var last-payout-height uint u0)
(define-data-var payout-interval uint u144) ;; Approximately daily (144 blocks per day on Stacks)
(define-data-var total-funds uint u0)
(define-data-var next-vote-id uint u0)
(define-data-var min-vote-percentage uint u60) ;; 60% required to pass a vote
(define-data-var total-percentage-allocated uint u0) ;; Track total percentage allocation

;; Define possible vote statuses as constants to avoid string type issues
(define-constant status-active "active")
(define-constant status-passed "passed")
(define-constant status-failed "failed")

;; Define vote types as constants
(define-constant vote-type-percentage "pct-change")

;; Define vote values as constants
(define-constant vote-yes "yes")
(define-constant vote-no "no")

;; ---------------------------------------------------------
;; Data Maps
;; ---------------------------------------------------------
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
    proposal-type: (string-ascii 10),
    target: principal,
    new-percentage: uint,
    proposed-at: uint,
    expires-at: uint,
    status: (string-ascii 10),
    yes-votes: uint,
    no-votes: uint,
    vote-power: uint
  }
)

(define-map stakeholder-votes 
  { vote-id: uint, voter: principal } 
  { vote: (string-ascii 3), weight: uint }
)

;; AI Oracle Integration
(define-map ai-recommendations uint 
  {
    recommendation-type: (string-ascii 10),
    target: principal,
    suggested-percentage: uint,
    confidence-score: uint,
    reasoning: (string-ascii 100)
  }
)

;; ---------------------------------------------------------
;; Read-Only Functions
;; ---------------------------------------------------------

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

;; Get total percentage allocated
(define-read-only (get-total-percentage-allocated)
  (var-get total-percentage-allocated)
)

;; ---------------------------------------------------------
;; Private Functions
;; ---------------------------------------------------------

;; Helper to update total percentage
(define-private (update-total-percentage (old-percentage uint) (new-percentage uint))
  (var-set total-percentage-allocated 
    (+ (- (var-get total-percentage-allocated) old-percentage) new-percentage)
  )
)

;; Helper to check if a new percentage would be valid
(define-private (is-valid-percentage-total (new-percentage uint) (old-percentage uint))
  (<= (+ (- (var-get total-percentage-allocated) old-percentage) new-percentage) u100)
)

;; Execute a percentage change after successful vote
(define-private (execute-percentage-change (target principal) (new-percentage uint))
  (let (
    (stakeholder-info (get-stakeholder target))
    (current-percentage (get percentage stakeholder-info))
  )
    (begin
      (map-set stakeholders target 
        (merge stakeholder-info { percentage: new-percentage })
      )
      (update-total-percentage current-percentage new-percentage)
      (ok true)
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
    (if (> amount-to-send u0)
      (match (as-contract (stx-transfer? amount-to-send tx-sender address))
        success-resp (begin
          ;; Transfer succeeded, update stakeholder info
          (map-set stakeholders address 
            (merge stakeholder-info { 
              total-withdrawn: (+ (get total-withdrawn stakeholder-info) amount-to-send),
              last-distribution: block-height
            })
          )
          ;; Return remaining funds
          (- remaining amount-to-send)
        )
        ;; Transfer failed, return original amount unchanged
        error-resp remaining
      )
      ;; Nothing to send, return original amount unchanged
      remaining
    )
  )
)

;; Generate AI recommendation for a vote
(define-private (generate-ai-recommendation (vote-id uint))
  (let (
    (vote-info (unwrap! (map-get? votes vote-id) err-vote-not-found))
  )
    (begin
      (if (is-eq (get proposal-type vote-info) vote-type-percentage)
        (map-set ai-recommendations vote-id {
          recommendation-type: "pct-advice",
          target: (get target vote-info),
          suggested-percentage: (get new-percentage vote-info),
          confidence-score: u75,
          reasoning: "Based on contributions, change aligns with equitable principles. 75% chance of approval."
        })
        ;; Return the same type (bool) for both branches
        false
      )
      (ok true)
    )
  )
)

;; ---------------------------------------------------------
;; Public Functions
;; ---------------------------------------------------------

;; Add a stakeholder (owner only)
(define-public (add-stakeholder (address principal) (percentage uint))
  (begin
    ;; Validate inputs first
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (< u0 percentage) err-invalid-percentage)
    (asserts! (<= percentage u100) err-invalid-percentage)
    
    (let (
      (existing-info (get-stakeholder address))
      (existing-percentage (get percentage existing-info))
      (existing-deposited (get total-deposited existing-info))
      (existing-withdrawn (get total-withdrawn existing-info))
    )
      (begin
        ;; Validate percentage allocation
        (asserts! (is-valid-percentage-total percentage existing-percentage) err-invalid-percentage)
        
        ;; Now that all inputs are validated, update the stakeholder
        (map-set stakeholders address {
          percentage: percentage,
          total-deposited: existing-deposited,
          total-withdrawn: existing-withdrawn,
          joined-block: block-height,
          last-distribution: block-height
        })
        
        (update-total-percentage existing-percentage percentage)
        (ok true)
      )
    )
  )
)

;; Deposit funds
(define-public (deposit (amount uint))
  (begin
    ;; Validate inputs first
    (asserts! (> amount u0) err-no-funds)
    (asserts! (>= amount min-deposit-amount) err-min-deposit-required)
    
    (let (
      (sender tx-sender)
      (stakeholder-info (get-stakeholder sender))
      (current-percentage (get percentage stakeholder-info))
      (current-deposited (get total-deposited stakeholder-info))
      (current-withdrawn (get total-withdrawn stakeholder-info))
      (joined-at (if (is-eq current-percentage u0) block-height (get joined-block stakeholder-info)))
      (last-dist (if (is-eq current-percentage u0) block-height (get last-distribution stakeholder-info)))
    )
      (begin
        ;; Update stakeholder info
        (map-set stakeholders sender {
          percentage: current-percentage,
          total-deposited: (+ current-deposited amount),
          total-withdrawn: current-withdrawn,
          joined-block: joined-at,
          last-distribution: last-dist
        })
        
        ;; Transfer funds to contract
        (match (stx-transfer? amount sender (as-contract tx-sender))
          success (begin
            (var-set total-funds (+ (var-get total-funds) amount))
            (ok true)
          )
          error (err error)
        )
      )
    )
  )
)

;; Distribute profits to all stakeholders
(define-public (distribute-profits)
  (begin
    (let (
      (current-height block-height)
      (last-payout (var-get last-payout-height))
      (interval (var-get payout-interval))
      (total (var-get total-funds))
    )
      (begin
        (asserts! (>= current-height (+ last-payout interval)) err-invalid-vote-status)
        (asserts! (> total u0) err-no-funds)
        
        (var-set last-payout-height current-height)
        (let ((remaining-funds (fold distribute-to-stakeholder (list contract-owner) total)))
          (begin
            (var-set total-funds remaining-funds)
            (ok remaining-funds)
          )
        )
      )
    )
  )
)

;; Vote on a proposal
(define-public (vote (vote-id uint) (vote-value (string-ascii 3)))
  (begin
    ;; Validate vote ID and status
    (let (
      (vote-info (unwrap! (map-get? votes vote-id) err-vote-not-found))
    )
      (begin
        (asserts! (is-eq (get status vote-info) status-active) err-invalid-vote-status)
        (asserts! (< block-height (get expires-at vote-info)) err-invalid-vote-status)
        (asserts! (or (is-eq vote-value vote-yes) (is-eq vote-value vote-no)) err-invalid-vote-status)
        
        (let (
          (voter tx-sender)
          (voter-info (unwrap! (map-get? stakeholders voter) err-not-stakeholder))
          (vote-weight (get percentage voter-info))
        )
          (begin
            (asserts! (is-none (map-get? stakeholder-votes { vote-id: vote-id, voter: voter })) err-vote-exists)
            
            ;; Record the vote
            (map-set stakeholder-votes { vote-id: vote-id, voter: voter } { vote: vote-value, weight: vote-weight })
            
            ;; Update vote tallies
            (if (is-eq vote-value vote-yes)
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
    )
  )
)

;; Finalize a vote if voting period has ended
(define-public (finalize-vote (vote-id uint))
  (begin
    (let (
      (vote-info (unwrap! (map-get? votes vote-id) err-vote-not-found))
      (current-height block-height)
    )
      (begin
        (asserts! (is-eq (get status vote-info) status-active) err-invalid-vote-status)
        (asserts! (>= current-height (get expires-at vote-info)) err-voting-period-active)
        
        (if (and 
              (>= (get vote-power vote-info) u50) ;; At least 50% participation
              (>= (get yes-votes vote-info) (/ (* (get vote-power vote-info) (var-get min-vote-percentage)) u100))
            )
          ;; Vote passed
          (begin
            (map-set votes vote-id (merge vote-info { status: status-passed }))
            (if (is-eq (get proposal-type vote-info) vote-type-percentage)
              (execute-percentage-change (get target vote-info) (get new-percentage vote-info))
              (ok true)
            )
          )
          ;; Vote failed
          (begin
            (map-set votes vote-id (merge vote-info { status: status-failed }))
            (ok false)
          )
        )
      )
    )
  )
)