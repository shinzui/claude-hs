-- | Configuration and results shared by the Claude HTTP endpoints.
module Claude.Client
  ( Client,
    ClientConfig (..),
    defaultClientConfig,
    newClient,
    RequestOptions (..),
    defaultRequestOptions,
    Response (..),
    ResponseMetadata (..),
    ApiError (..),
    ClientError (..),
    TransportFailure (..),
  )
where

import Claude.Internal.Http
