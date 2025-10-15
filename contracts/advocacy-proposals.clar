;; AbleDAO Advocacy Proposals - Specialized contract for disability rights advocacy
;; Manages advocacy campaigns, funding, and impact tracking

;; ===== CONSTANTS =====

(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u200))
(define-constant err-campaign-not-found (err u201))
(define-constant err-campaign-ended (err u202))
(define-constant err-insufficient-funding (err u203))
(define-constant err-campaign-already-funded (err u204))
(define-constant err-invalid-target (err u205))
(define-constant err-campaign-not-active (err u206))
(define-constant err-duplicate-support (err u207))
(define-constant err-invalid-impact-score (err u208))
(define-constant err-milestone-not-found (err u209))
(define-constant err-milestone-completed (err u210))

;; Campaign constants
(define-constant min-funding-goal u10000)    ;; Minimum 10,000 microSTX funding goal
(define-constant max-funding-goal u10000000) ;; Maximum 10,000,000 microSTX funding goal
(define-constant min-campaign-duration u2880) ;; ~2 days in blocks
(define-constant max-campaign-duration u43200) ;; ~30 days in blocks
(define-constant impact-score-max u100)       ;; Maximum impact score

;; ===== DATA VARIABLES =====

(define-data-var campaign-count uint u0)
(define-data-var total-funds-raised uint u0)
(define-data-var active-campaigns uint u0)
(define-data-var milestone-count uint u0)

;; ===== DATA MAPS =====

;; Advocacy campaign registry
(define-map advocacy-campaigns 
    uint 
    {
        creator: principal,
        title: (string-ascii 100),
        description: (string-ascii 800),
        category: (string-ascii 50),
        funding-goal: uint,
        funds-raised: uint,
        supporter-count: uint,
        start-block: uint,
        end-block: uint,
        is-active: bool,
        is-funded: bool,
        target-population: (string-ascii 200),
        expected-impact: (string-ascii 300),
        created-at: uint
    }
)

;; Campaign supporter tracking
(define-map campaign-supporters 
    { campaign-id: uint, supporter: principal } 
    { 
        amount-contributed: uint, 
        supported-at: uint,
        accessibility-note: (string-ascii 200)
    }
)

;; Impact tracking and reporting
(define-map campaign-impact 
    uint 
    {
        impact-score: uint,
        people-helped: uint,
        goals-achieved: uint,
        total-goals: uint,
        final-report: (string-ascii 500),
        reported-at: uint,
        verified: bool
    }
)

;; Advocacy categories with metrics
(define-map advocacy-categories 
    (string-ascii 50) 
    {
        total-campaigns: uint,
        total-funding: uint,
        success-rate: uint,
        last-updated: uint
    }
)

;; Campaign milestones
(define-map campaign-milestones 
    uint 
    {
        campaign-id: uint,
        title: (string-ascii 100),
        description: (string-ascii 300),
        target-date: uint,
        completed: bool,
        completed-at: (optional uint),
        evidence: (string-ascii 300)
    }
)

;; Community engagement metrics
(define-map community-engagement 
    principal 
    {
        campaigns-created: uint,
        campaigns-supported: uint,
        total-contributed: uint,
        advocacy-score: uint,
        last-activity: uint
    }
)

;; ===== PUBLIC FUNCTIONS =====

;; Create new advocacy campaign
(define-public (create-advocacy-campaign 
    (title (string-ascii 100))
    (description (string-ascii 800))
    (category (string-ascii 50))
    (funding-goal uint)
    (duration uint)
    (target-population (string-ascii 200))
    (expected-impact (string-ascii 300))
    )
    (let 
        (
            (campaign-id (+ (var-get campaign-count) u1))
        )
        (asserts! (and (>= funding-goal min-funding-goal) (<= funding-goal max-funding-goal)) err-invalid-target)
        (asserts! (and (>= duration min-campaign-duration) (<= duration max-campaign-duration)) (err u211))
        
        ;; Create campaign
        (map-set advocacy-campaigns campaign-id {
            creator: tx-sender,
            title: title,
            description: description,
            category: category,
            funding-goal: funding-goal,
            funds-raised: u0,
            supporter-count: u0,
            start-block: stacks-block-height,
            end-block: (+ stacks-block-height duration),
            is-active: true,
            is-funded: false,
            target-population: target-population,
            expected-impact: expected-impact,
            created-at: stacks-block-height
        })
        
        ;; Update counters
        (var-set campaign-count campaign-id)
        (var-set active-campaigns (+ (var-get active-campaigns) u1))
        
        ;; Update category statistics
        (let 
            (
                (category-stats (default-to 
                    { total-campaigns: u0, total-funding: u0, success-rate: u0, last-updated: u0 }
                    (map-get? advocacy-categories category)
                ))
            )
            (map-set advocacy-categories category 
                (merge category-stats {
                    total-campaigns: (+ (get total-campaigns category-stats) u1),
                    last-updated: stacks-block-height
                })
            )
        )
        
        ;; Update creator's engagement
        (let 
            (
                (engagement (default-to 
                    { campaigns-created: u0, campaigns-supported: u0, total-contributed: u0, advocacy-score: u0, last-activity: u0 }
                    (map-get? community-engagement tx-sender)
                ))
            )
            (map-set community-engagement tx-sender 
                (merge engagement {
                    campaigns-created: (+ (get campaigns-created engagement) u1),
                    advocacy-score: (+ (get advocacy-score engagement) u5),
                    last-activity: stacks-block-height
                })
            )
        )
        
        (ok campaign-id)
    )
)

;; Support advocacy campaign with funding
(define-public (support-campaign (campaign-id uint) (amount uint) (accessibility-note (string-ascii 200)))
    (let 
        (
            (campaign (map-get? advocacy-campaigns campaign-id))
            (existing-support (map-get? campaign-supporters { campaign-id: campaign-id, supporter: tx-sender }))
        )
        (asserts! (is-some campaign) err-campaign-not-found)
        (asserts! (is-none existing-support) err-duplicate-support)
        (asserts! (> amount u0) (err u212))
        
        (let 
            (
                (campaign-data (unwrap-panic campaign))
            )
            (asserts! (get is-active campaign-data) err-campaign-not-active)
            (asserts! (<= stacks-block-height (get end-block campaign-data)) err-campaign-ended)
            (asserts! (not (get is-funded campaign-data)) err-campaign-already-funded)
            
            ;; Transfer funds
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            
            ;; Record support
            (map-set campaign-supporters 
                { campaign-id: campaign-id, supporter: tx-sender }
                { 
                    amount-contributed: amount, 
                    supported-at: stacks-block-height,
                    accessibility-note: accessibility-note
                }
            )
            
            ;; Update campaign stats
            (let 
                (
                    (new-funds-raised (+ (get funds-raised campaign-data) amount))
                    (new-supporter-count (+ (get supporter-count campaign-data) u1))
                    (funding-complete (>= new-funds-raised (get funding-goal campaign-data)))
                )
                (map-set advocacy-campaigns campaign-id 
                    (merge campaign-data {
                        funds-raised: new-funds-raised,
                        supporter-count: new-supporter-count,
                        is-funded: funding-complete
                    })
                )
                
                ;; Update global stats
                (var-set total-funds-raised (+ (var-get total-funds-raised) amount))
                
                ;; If funding complete, update category success rate
                (if funding-complete
                    (begin
                        (var-set active-campaigns (- (var-get active-campaigns) u1))
                        (let 
                            (
                                (category-stats (unwrap-panic (map-get? advocacy-categories (get category campaign-data))))
                            )
                            (map-set advocacy-categories (get category campaign-data)
                                (merge category-stats {
                                    total-funding: (+ (get total-funding category-stats) new-funds-raised),
                                    last-updated: stacks-block-height
                                })
                            )
                        )
                    )
                    true
                )
            )
            
            ;; Update supporter's engagement
            (let 
                (
                    (engagement (default-to 
                        { campaigns-created: u0, campaigns-supported: u0, total-contributed: u0, advocacy-score: u0, last-activity: u0 }
                        (map-get? community-engagement tx-sender)
                    ))
                )
                (map-set community-engagement tx-sender 
                    (merge engagement {
                        campaigns-supported: (+ (get campaigns-supported engagement) u1),
                        total-contributed: (+ (get total-contributed engagement) amount),
                        advocacy-score: (+ (get advocacy-score engagement) u3),
                        last-activity: stacks-block-height
                    })
                )
            )
            
            (ok true)
        )
    )
)

;; Add campaign milestone
(define-public (add-campaign-milestone 
    (campaign-id uint)
    (title (string-ascii 100))
    (description (string-ascii 300))
    (target-date uint)
    )
    (let 
        (
            (campaign (map-get? advocacy-campaigns campaign-id))
            (milestone-id (+ (var-get milestone-count) u1))
        )
        (asserts! (is-some campaign) err-campaign-not-found)
        (asserts! (is-eq tx-sender (get creator (unwrap-panic campaign))) err-unauthorized)
        
        (map-set campaign-milestones milestone-id {
            campaign-id: campaign-id,
            title: title,
            description: description,
            target-date: target-date,
            completed: false,
            completed-at: none,
            evidence: ""
        })
        
        (var-set milestone-count milestone-id)
        (ok milestone-id)
    )
)

;; Complete campaign milestone
(define-public (complete-milestone (milestone-id uint) (evidence (string-ascii 300)))
    (let 
        (
            (milestone (map-get? campaign-milestones milestone-id))
        )
        (asserts! (is-some milestone) err-milestone-not-found)
        
        (let 
            (
                (milestone-data (unwrap-panic milestone))
                (campaign (unwrap-panic (map-get? advocacy-campaigns (get campaign-id milestone-data))))
            )
            (asserts! (is-eq tx-sender (get creator campaign)) err-unauthorized)
            (asserts! (not (get completed milestone-data)) err-milestone-completed)
            
            (map-set campaign-milestones milestone-id 
                (merge milestone-data {
                    completed: true,
                    completed-at: (some stacks-block-height),
                    evidence: evidence
                })
            )
            
            (ok true)
        )
    )
)

;; Report campaign impact
(define-public (report-impact 
    (campaign-id uint)
    (impact-score uint)
    (people-helped uint)
    (goals-achieved uint)
    (total-goals uint)
    (final-report (string-ascii 500))
    )
    (let 
        (
            (campaign (map-get? advocacy-campaigns campaign-id))
        )
        (asserts! (is-some campaign) err-campaign-not-found)
        (asserts! (<= impact-score impact-score-max) err-invalid-impact-score)
        (asserts! (<= goals-achieved total-goals) (err u213))
        
        (let 
            (
                (campaign-data (unwrap-panic campaign))
            )
            (asserts! (is-eq tx-sender (get creator campaign-data)) err-unauthorized)
            (asserts! (get is-funded campaign-data) (err u214))
            
            (map-set campaign-impact campaign-id {
                impact-score: impact-score,
                people-helped: people-helped,
                goals-achieved: goals-achieved,
                total-goals: total-goals,
                final-report: final-report,
                reported-at: stacks-block-height,
                verified: false
            })
            
            ;; Update creator's advocacy score based on impact
            (let 
                (
                    (engagement (unwrap-panic (map-get? community-engagement tx-sender)))
                    (impact-bonus (/ impact-score u10)) ;; Convert impact score to bonus points
                )
                (map-set community-engagement tx-sender 
                    (merge engagement {
                        advocacy-score: (+ (get advocacy-score engagement) impact-bonus),
                        last-activity: stacks-block-height
                    })
                )
            )
            
            (ok true)
        )
    )
)

;; Withdraw funds from completed campaign
(define-public (withdraw-campaign-funds (campaign-id uint))
    (let 
        (
            (campaign (map-get? advocacy-campaigns campaign-id))
        )
        (asserts! (is-some campaign) err-campaign-not-found)
        
        (let 
            (
                (campaign-data (unwrap-panic campaign))
            )
            (asserts! (is-eq tx-sender (get creator campaign-data)) err-unauthorized)
            (asserts! (get is-funded campaign-data) err-insufficient-funding)
            (asserts! (> (get funds-raised campaign-data) u0) (err u215))
            
            (let 
                (
                    (withdraw-amount (get funds-raised campaign-data))
                )
                ;; Transfer funds to campaign creator
                (try! (stx-transfer? withdraw-amount (as-contract tx-sender) tx-sender))
                
                ;; Mark funds as withdrawn by setting to 0
                (map-set advocacy-campaigns campaign-id 
                    (merge campaign-data { funds-raised: u0 })
                )
                
                (ok withdraw-amount)
            )
        )
    )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get campaign details
(define-read-only (get-campaign (campaign-id uint))
    (map-get? advocacy-campaigns campaign-id)
)

;; Get campaign support information
(define-read-only (get-support-info (campaign-id uint) (supporter principal))
    (map-get? campaign-supporters { campaign-id: campaign-id, supporter: supporter })
)

;; Get campaign impact report
(define-read-only (get-campaign-impact (campaign-id uint))
    (map-get? campaign-impact campaign-id)
)

;; Get category statistics
(define-read-only (get-category-stats (category (string-ascii 50)))
    (map-get? advocacy-categories category)
)

;; Get community engagement metrics
(define-read-only (get-engagement-metrics (user principal))
    (map-get? community-engagement user)
)

;; Get milestone information
(define-read-only (get-milestone (milestone-id uint))
    (map-get? campaign-milestones milestone-id)
)

;; Get total campaigns count
(define-read-only (get-campaign-count)
    (var-get campaign-count)
)

;; Get total funds raised across all campaigns
(define-read-only (get-total-funds-raised)
    (var-get total-funds-raised)
)

;; Get active campaigns count
(define-read-only (get-active-campaigns)
    (var-get active-campaigns)
)

;; Check if campaign is fully funded
(define-read-only (is-campaign-funded? (campaign-id uint))
    (match (map-get? advocacy-campaigns campaign-id)
        campaign (get is-funded campaign)
        false
    )
)

;; Get campaign funding progress
(define-read-only (get-funding-progress (campaign-id uint))
    (match (map-get? advocacy-campaigns campaign-id)
        campaign 
        (some {
            funds-raised: (get funds-raised campaign),
            funding-goal: (get funding-goal campaign),
            progress-percentage: (if (> (get funding-goal campaign) u0)
                (/ (* (get funds-raised campaign) u100) (get funding-goal campaign))
                u0
            ),
            supporter-count: (get supporter-count campaign),
            is-funded: (get is-funded campaign),
            blocks-remaining: (if (<= stacks-block-height (get end-block campaign))
                (- (get end-block campaign) stacks-block-height)
                u0
            )
        })
        none
    )
)

;; Calculate advocacy effectiveness score
(define-read-only (get-advocacy-effectiveness (campaign-id uint))
    (let 
        (
            (campaign-opt (map-get? advocacy-campaigns campaign-id))
            (impact-opt (map-get? campaign-impact campaign-id))
        )
        (match campaign-opt
            campaign-data
            (match impact-opt
                impact-data
                (let 
                    (
                        (funding-efficiency (if (> (get funds-raised campaign-data) u0)
                            (/ (* (get people-helped impact-data) u100) (get funds-raised campaign-data))
                            u0
                        ))
                        (goal-completion (if (> (get total-goals impact-data) u0)
                            (/ (* (get goals-achieved impact-data) u100) (get total-goals impact-data))
                            u0
                        ))
                        (community-support (get supporter-count campaign-data))
                    )
                    (some {
                        impact-score: (get impact-score impact-data),
                        funding-efficiency: funding-efficiency,
                        goal-completion-rate: goal-completion,
                        community-support: community-support,
                        overall-effectiveness: (/ (+ (get impact-score impact-data) goal-completion (if (< community-support u100) community-support u100)) u3)
                    })
                )
                none
            )
            none
        )
    )
)

