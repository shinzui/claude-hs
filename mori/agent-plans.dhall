let AgentPlans =
      https://raw.githubusercontent.com/shinzui/mori-schema/94bc56785e632a3b7a3f260d66dfea9570e1bef3/extensions/agent-plans/package.dhall
        sha256:0b567808087da1924fb121df044c9432f676bb81305d5373809e3182d054943b

let hard = λ(target : Text) → AgentPlans.PlanDependency::{ kind = AgentPlans.DependencyKind.Hard, target = target }

in  AgentPlans.AgentPlansCatalog::{
    , plans =
      [ AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.MasterPlan
        , file = "docs/masterplans/1-build-a-haskell-client-for-the-claude-messages-api.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/1-send-messages-and-count-input-tokens.md"
        , status = AgentPlans.PlanStatus.NotStarted
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/2-stream-message-events-as-they-arrive.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/1-send-messages-and-count-input-tokens"
          , hard "mori://shinzui/claude-hs/plans/4-support-current-claude-reasoning-tools-caching-and-citations"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/3-submit-message-batches-and-consume-their-results.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/1-send-messages-and-count-input-tokens"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/4-support-current-claude-reasoning-tools-caching-and-citations.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/1-send-messages-and-count-input-tokens"
          ]
        }
      , AgentPlans.ExposedPlan::{
        , kind = AgentPlans.PlanKind.ExecPlan
        , file = "docs/plans/5-verify-the-client-through-baikai-shikumi-and-shikigami.md"
        , status = AgentPlans.PlanStatus.NotStarted
        , dependencies =
          [ hard "mori://shinzui/claude-hs/plans/2-stream-message-events-as-they-arrive"
          , hard "mori://shinzui/claude-hs/plans/4-support-current-claude-reasoning-tools-caching-and-citations"
          ]
        }
      ]
    }
