let AgentPlans =
      https://raw.githubusercontent.com/shinzui/mori-schema/94bc56785e632a3b7a3f260d66dfea9570e1bef3/extensions/agent-plans/package.dhall
        sha256:0b567808087da1924fb121df044c9432f676bb81305d5373809e3182d054943b

let hard = λ(target : Text) → AgentPlans.PlanDependency::{ kind = AgentPlans.DependencyKind.Hard, target = target }

in  AgentPlans.AgentPlansCatalog::{
    , plans =
      [ AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/1-build-a-haskell-client-for-the-claude-messages-api.md"
        , status = AgentPlans.PlanStatus.Complete
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/1-send-messages-and-count-input-tokens.md"
        , status = AgentPlans.PlanStatus.Complete
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/2-stream-message-events-as-they-arrive.md"
        , status = AgentPlans.PlanStatus.Complete
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/1-send-messages-and-count-input-tokens"
          , hard "mori://shinzui/claude-hs/plans/4-support-current-claude-reasoning-tools-caching-and-citations"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/3-submit-message-batches-and-consume-their-results.md"
        , status = AgentPlans.PlanStatus.Complete
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/1-send-messages-and-count-input-tokens"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/4-support-current-claude-reasoning-tools-caching-and-citations.md"
        , status = AgentPlans.PlanStatus.Complete
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/1-send-messages-and-count-input-tokens"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/5-verify-the-client-through-baikai-shikumi-and-shikigami.md"
        , status = AgentPlans.PlanStatus.Complete
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/2-stream-message-events-as-they-arrive"
          , hard "mori://shinzui/claude-hs/plans/4-support-current-claude-reasoning-tools-caching-and-citations"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/2-reach-mercury-claude-feature-parity-and-migrate-baikai.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/6-complete-claude-messages-request-and-tool-feature-coverage.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/7-preserve-advanced-claude-response-and-streaming-evidence.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/8-remove-the-mercury-claude-dependency-from-baikai.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/6-complete-claude-messages-request-and-tool-feature-coverage"
          , hard "mori://shinzui/claude-hs/plans/7-preserve-advanced-claude-response-and-streaming-evidence"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/3-assemble-streamed-claude-responses-for-conversation-replay.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/4-run-client-tools-across-claude-conversation-turns.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/5-use-files-and-document-artifacts-with-claude-messages.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/6-complete-advanced-messages-controls-and-signed-compaction.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/7-parse-structured-claude-outputs-into-haskell-values.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/9-discover-available-claude-models-and-their-capabilities.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/10-fold-message-events-into-a-complete-response.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/11-return-the-assembled-message-from-a-live-stream.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/10-fold-message-events-into-a-complete-response"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/12-execute-registered-client-tools-across-message-turns.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/13-continue-tool-conversations-with-server-held-threads.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/12-execute-registered-client-tools-across-message-turns"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/14-manage-files-through-the-direct-claude-api.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/15-send-typed-documents-and-consume-generated-file-references.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/14-manage-files-through-the-direct-claude-api"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/16-carry-advanced-request-controls-across-messages-endpoints.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/17-compact-a-conversation-and-replay-its-signed-summary.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/10-fold-message-events-into-a-complete-response"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/18-decode-schema-constrained-message-responses.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/19-request-and-parse-structured-outputs-across-unary-and-streaming-calls.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/18-decode-schema-constrained-message-responses"
          , hard "mori://shinzui/claude-hs/plans/11-return-the-assembled-message-from-a-live-stream"
          ]
        }
      ]
    }
