let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/94bc56785e632a3b7a3f260d66dfea9570e1bef3/package.dhall
        sha256:98c63c91aa308963b92bcdd08132be1965795a13ea03e25e6638775ecaf1bdc7

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "claude-hs"
      , namespace = "shinzui"
      , stableId = Some "project_01m7xa0y0sezcaabge5b5n3fdx"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Active
      , description = Some "Haskell client for the Anthropic Claude Messages API"
      , owners = [ "shinzui" ]
      , domains = [ "ai", "api" ]
      }
    , repos =
      [ Schema.Repo::{
        , name = "claude-hs"
        , github = Some "shinzui/claude-hs"
        , localPath = Some "."
        }
      ]
    , packages =
      [ Schema.Package::{
        , name = "claude-hs"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "."
        , description = Some "Typed HTTP client for direct Claude Messages and batches"
        }
      ]
    , okfBundles =
      [ Schema.OkfBundle::{
        , name = "friction-log"
        , path = "docs/friction-log"
        , okfVersion = "0.2"
        , profile = Some "docs/friction-log/profile.dhall"
        , description = Some "Friction met while implementing plans, before triage into bug reports and requests"
        }
      ]
    , standardRefs =
      [ Schema.MoriRef::{ namespace = "shinzui", name = "haskell-jitsurei" } ]
    }
