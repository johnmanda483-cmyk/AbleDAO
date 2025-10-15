;; AbleDAO - Decentralized Autonomous Organization for Disabled Rights Advocacy
;; Main governance contract for member management, proposals, and voting

;; ===== CONSTANTS =====

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-member (err u101))
(define-constant err-already-member (err u102))
(define-constant err-proposal-not-found (err u103))
(define-constant err-proposal-ended (err u104))
(define-constant err-already-voted (err u105))
(define-constant err-insufficient-funds (err u106))
(define-constant err-proposal-not-passed (err u107))
(define-constant err-proposal-already-executed (err u108))
(define-constant err-invalid-amount (err u109))
(define-constant err-invalid-duration (err u110))

;; Voting thresholds
(define-constant min-approval-threshold u60) ;; 60% approval required
(define-constant min-quorum-threshold u25)   ;; 25% participation required
(define-constant max-voting-duration u14400) ;; ~10 days in blocks (144 blocks/day)
(define-constant min-voting-duration u1440)  ;; ~1 day in blocks

;; ===== DATA VARIABLES =====

(define-data-var treasury-balance uint u0)
(define-data-var member-count uint u0)
(define-data-var proposal-count uint u0)
(define-data-var dao-initialized bool false)

;; ===== DATA MAPS =====

;; Member registry with registration details
(define-map members 
    principal 
    {
        joined-at: uint,
        voting-power: uint,
        is-active: bool,
        accessibility-needs: (string-ascii 200)
    }
)

;; Proposal registry with comprehensive governance data
(define-map proposals 
    uint 
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        proposal-type: (string-ascii 50),
        amount-requested: uint,
        recipient: (optional principal),
        start-block: uint,
        end-block: uint,
        yes-votes: uint,
        no-votes: uint,
        executed: bool,
        created-at: uint
    }
)

;; Individual vote tracking
(define-map votes 
    { proposal-id: uint, voter: principal } 
    { vote: bool, voted-at: uint }
)

;; Member vote history for reputation tracking
(define-map member-vote-history 
    principal 
    { total-votes: uint, last-vote-block: uint }
)

;; ===== PUBLIC FUNCTIONS =====

;; Initialize the DAO with founder as first member
(define-public (initialize-dao (initial-balance uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (var-get dao-initialized)) (err u111))
        (var-set dao-initialized true)
        (var-set treasury-balance initial-balance)
        (map-set members contract-owner {
            joined-at: stacks-block-height,
            voting-power: u1,
            is-active: true,
            accessibility-needs: "founder-member"
        })
        (var-set member-count u1)
        (ok true)
    )
)

;; Register new DAO member with accessibility information
(define-public (register-member (accessibility-info (string-ascii 200)))
    (let 
        (
            (current-member (map-get? members tx-sender))
        )
        (asserts! (is-none current-member) err-already-member)
        (asserts! (var-get dao-initialized) (err u112))
        (map-set members tx-sender {
            joined-at: stacks-block-height,
            voting-power: u1,
            is-active: true,
            accessibility-needs: accessibility-info
        })
        (var-set member-count (+ (var-get member-count) u1))
        (ok true)
    )
)

;; Create governance proposal
(define-public (create-proposal 
    (title (string-ascii 100)) 
    (description (string-ascii 500))
    (proposal-type (string-ascii 50))
    (amount uint)
    (recipient (optional principal))
    (duration uint)
    )
    (let 
        (
            (proposal-id (+ (var-get proposal-count) u1))
            (member-info (map-get? members tx-sender))
        )
        (asserts! (is-some member-info) err-not-member)
        (asserts! (get is-active (unwrap-panic member-info)) err-not-member)
        (asserts! (and (>= duration min-voting-duration) (<= duration max-voting-duration)) err-invalid-duration)
        (asserts! (or (is-eq amount u0) (> amount u0)) err-invalid-amount)
        
        (map-set proposals proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            proposal-type: proposal-type,
            amount-requested: amount,
            recipient: recipient,
            start-block: stacks-block-height,
            end-block: (+ stacks-block-height duration),
            yes-votes: u0,
            no-votes: u0,
            executed: false,
            created-at: stacks-block-height
        })
        
        (var-set proposal-count proposal-id)
        (ok proposal-id)
    )
)

;; Cast vote on proposal
(define-public (vote-on-proposal (proposal-id uint) (vote bool))
    (let 
        (
            (proposal (map-get? proposals proposal-id))
            (member-info (map-get? members tx-sender))
            (existing-vote (map-get? votes { proposal-id: proposal-id, voter: tx-sender }))
        )
        (asserts! (is-some proposal) err-proposal-not-found)
        (asserts! (is-some member-info) err-not-member)
        (asserts! (get is-active (unwrap-panic member-info)) err-not-member)
        (asserts! (is-none existing-vote) err-already-voted)
        
        (let 
            (
                (proposal-data (unwrap-panic proposal))
                (voting-power (get voting-power (unwrap-panic member-info)))
            )
            (asserts! (<= stacks-block-height (get end-block proposal-data)) err-proposal-ended)
            
            ;; Record the vote
            (map-set votes 
                { proposal-id: proposal-id, voter: tx-sender } 
                { vote: vote, voted-at: stacks-block-height }
            )
            
            ;; Update proposal vote counts
            (if vote
                (map-set proposals proposal-id 
                    (merge proposal-data { yes-votes: (+ (get yes-votes proposal-data) voting-power) })
                )
                (map-set proposals proposal-id 
                    (merge proposal-data { no-votes: (+ (get no-votes proposal-data) voting-power) })
                )
            )
            
            ;; Update member vote history
            (let 
                (
                    (vote-history (default-to { total-votes: u0, last-vote-block: u0 } 
                                               (map-get? member-vote-history tx-sender)))
                )
                (map-set member-vote-history tx-sender {
                    total-votes: (+ (get total-votes vote-history) u1),
                    last-vote-block: stacks-block-height
                })
            )
            
            (ok true)
        )
    )
)

;; Execute approved proposal
(define-public (execute-proposal (proposal-id uint))
    (let 
        (
            (proposal (map-get? proposals proposal-id))
        )
        (asserts! (is-some proposal) err-proposal-not-found)
        
        (let 
            (
                (proposal-data (unwrap-panic proposal))
                (total-votes (+ (get yes-votes proposal-data) (get no-votes proposal-data)))
                (member-count-current (var-get member-count))
            )
            (asserts! (> stacks-block-height (get end-block proposal-data)) (err u113))
            (asserts! (not (get executed proposal-data)) err-proposal-already-executed)
            
            ;; Check quorum (25% of members must vote)
            (asserts! (>= (* total-votes u100) (* member-count-current min-quorum-threshold)) (err u114))
            
            ;; Check approval (60% of votes must be yes)
            (asserts! (>= (* (get yes-votes proposal-data) u100) (* total-votes min-approval-threshold)) err-proposal-not-passed)
            
            ;; Mark as executed
            (map-set proposals proposal-id (merge proposal-data { executed: true }))
            
            ;; Execute proposal actions for funding if amount > 0
            (if (> (get amount-requested proposal-data) u0)
                (begin
                    (asserts! (>= (var-get treasury-balance) (get amount-requested proposal-data)) err-insufficient-funds)
                    (var-set treasury-balance (- (var-get treasury-balance) (get amount-requested proposal-data)))
                    (match (get recipient proposal-data)
                        recipient (stx-transfer? (get amount-requested proposal-data) (as-contract tx-sender) recipient)
                        (ok true) ;; No recipient specified
                    )
                )
                (ok true) ;; No funding requested
            )
        )
    )
)

;; Add funds to DAO treasury
(define-public (fund-treasury (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

;; Update member accessibility needs
(define-public (update-accessibility-info (new-info (string-ascii 200)))
    (let 
        (
            (member-info (map-get? members tx-sender))
        )
        (asserts! (is-some member-info) err-not-member)
        
        (let 
            (
                (current-info (unwrap-panic member-info))
            )
            (map-set members tx-sender (merge current-info { accessibility-needs: new-info }))
            (ok true)
        )
    )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get member information
(define-read-only (get-member-info (member principal))
    (map-get? members member)
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Check if user has voted on proposal
(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes { proposal-id: proposal-id, voter: voter })
)

;; Get current treasury balance
(define-read-only (get-treasury-balance)
    (var-get treasury-balance)
)

;; Get total member count
(define-read-only (get-member-count)
    (var-get member-count)
)

;; Get total proposal count
(define-read-only (get-proposal-count)
    (var-get proposal-count)
)

;; Check if proposal has passed
(define-read-only (proposal-passed? (proposal-id uint))
    (let 
        (
            (proposal (map-get? proposals proposal-id))
        )
        (match proposal
            proposal-data 
            (let 
                (
                    (total-votes (+ (get yes-votes proposal-data) (get no-votes proposal-data)))
                    (member-count-current (var-get member-count))
                )
                (and 
                    (> stacks-block-height (get end-block proposal-data))
                    (>= (* total-votes u100) (* member-count-current min-quorum-threshold))
                    (>= (* (get yes-votes proposal-data) u100) (* total-votes min-approval-threshold))
                )
            )
            false
        )
    )
)

;; Get member vote history
(define-read-only (get-member-vote-history (member principal))
    (default-to { total-votes: u0, last-vote-block: u0 } 
                (map-get? member-vote-history member))
)

;; Check DAO initialization status
(define-read-only (is-dao-initialized)
    (var-get dao-initialized)
)

;; Calculate current proposal voting stats
(define-read-only (get-proposal-stats (proposal-id uint))
    (let 
        (
            (proposal (map-get? proposals proposal-id))
        )
        (match proposal
            proposal-data 
            (let 
                (
                    (total-votes (+ (get yes-votes proposal-data) (get no-votes proposal-data)))
                    (member-count-current (var-get member-count))
                )
                (some {
                    yes-votes: (get yes-votes proposal-data),
                    no-votes: (get no-votes proposal-data),
                    total-votes: total-votes,
                    participation-rate: (if (> member-count-current u0) 
                                          (/ (* total-votes u100) member-count-current) u0),
                    approval-rate: (if (> total-votes u0) 
                                     (/ (* (get yes-votes proposal-data) u100) total-votes) u0),
                    is-active: (<= stacks-block-height (get end-block proposal-data)),
                    blocks-remaining: (if (<= stacks-block-height (get end-block proposal-data))
                                        (- (get end-block proposal-data) stacks-block-height) u0)
                })
            )
            none
        )
    )
)

