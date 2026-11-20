-- | Configuration and results shared by the Claude HTTP endpoints.
module Claude.Client
  ( Client,
    ClientPool,
    newClientPool,
    newClientWithPool,
    ClientConfig (..),
    defaultClientConfig,
    newClient,
    RequestOptions (..),
    defaultRequestOptions,
    Response (..),
    ResponseMetadata (..),
    ApiError (..),
    ApiErrorCategory (..),
    apiErrorCategory,
    ClientError (..),
    TransportFailure (..),
  )
where

import Claude.Internal.Http
