{-# LANGUAGE OverloadedStrings #-}

module Walmart.Types
  ( OrderId (..)
  , UsItemId (..)
  , OperationName (..)
  , QueryHash
  , unQueryHash
  , mkQueryHash
  , OrderChannel (..)
  , SalesUnitType (..)
  , WalmartItem (..)
  , WalmartOrder (..)
  , OrderSummary (..)
  , CategoryId (..)
  , SearchQuery (..)
  , SearchResult (..)
  , CategoryFacet (..)
  , Fulfillment (..)
  , FulfillmentOption (..)
  , StoreContext (..)
  , ProductSummary (..)
  , WalmartError (..)
  , BodyPreview (..)
  ) where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Char (isDigit)
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Money (Discrete)

newtype OrderId = OrderId { unOrderId :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON OrderId where
  toJSON = toJSON . unOrderId

newtype UsItemId = UsItemId { unUsItemId :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON UsItemId where
  toJSON = toJSON . unUsItemId

-- | The name Walmart's gateway knows an operation by, and the key its
-- persisted query hash is catalogued under.
newtype OperationName = OperationName { unOperationName :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON OperationName where
  toJSON = toJSON . unOperationName

-- | The id of a query document registered on Walmart's servers. Only
-- 'mkQueryHash' constructs one, so a value of this type is always in the
-- shape the gateway accepts.
newtype QueryHash = QueryHash Text
  deriving stock (Show, Eq, Ord)

unQueryHash :: QueryHash -> Text
unQueryHash (QueryHash h) = h

instance ToJSON QueryHash where
  toJSON = toJSON . unQueryHash

-- | Accept exactly 64 lowercase hex characters.
mkQueryHash :: Text -> Maybe QueryHash
mkQueryHash raw
  | T.length raw == 64 && T.all isLowerHex raw = Just (QueryHash raw)
  | otherwise = Nothing
  where
    isLowerHex c = isDigit c || (c >= 'a' && c <= 'f')

-- | Where the order was placed. getOrder must be told which kind it is
-- fetching, so the summary records it.
data OrderChannel = InStore | Online
  deriving stock (Show, Eq)

instance ToJSON OrderChannel where
  toJSON InStore = "in_store"
  toJSON Online  = "online"

data SalesUnitType = Each | EachWeight | PackWeight
  deriving stock (Show, Eq)

instance ToJSON SalesUnitType where
  toJSON Each       = "each"
  toJSON EachWeight = "each_weight"
  toJSON PackWeight = "pack_weight"

data WalmartItem = WalmartItem
  { wiName          :: Text
  , wiQuantity      :: Scientific
  , wiLinePrice     :: Maybe (Discrete "USD" "cent")
  , wiUsItemId      :: UsItemId
  , wiSalesUnitType :: SalesUnitType
  } deriving stock (Show, Eq)

instance ToJSON WalmartItem where
  toJSON item = object
    [ "name"             .= wiName item
    , "quantity"         .= wiQuantity item
    , "line_price_cents" .= fmap toInteger (wiLinePrice item)
    , "us_item_id"       .= wiUsItemId item
    , "sales_unit_type"  .= wiSalesUnitType item
    ]

data WalmartOrder = WalmartOrder
  { woOrderId   :: OrderId
  , woOrderDate :: UTCTime
  , woItems     :: [WalmartItem]
  } deriving stock (Show)

instance ToJSON WalmartOrder where
  toJSON order = object
    [ "order_id"   .= woOrderId order
    , "order_date" .= woOrderDate order
    , "items"      .= woItems order
    ]

data OrderSummary = OrderSummary
  { osOrderId   :: OrderId
  , osChannel   :: OrderChannel
  , osItemCount :: Int
  , osStatus    :: Maybe Text
  } deriving stock (Show)

instance ToJSON OrderSummary where
  toJSON summary = object
    [ "order_id"   .= osOrderId summary
    , "channel"    .= osChannel summary
    , "item_count" .= osItemCount summary
    , "status"     .= osStatus summary
    ]

-- | One product as a search or category listing reports it.
data ProductSummary = ProductSummary
  { psUsItemId     :: UsItemId
  , psName         :: Text
  , psBrand        :: Maybe Text
  , psPrice        :: Maybe (Discrete "USD" "cent")
  , psPricePerUnit :: Maybe Text
  , psAvailability :: Maybe Text
  , psDescription  :: Maybe Text
  , psDepartment   :: Maybe Text
  , psCategoryPath :: Maybe CategoryId
  , psFulfillment  :: [FulfillmentOption]
  } deriving stock (Show, Eq)

instance ToJSON ProductSummary where
  toJSON p = object
    [ "us_item_id"     .= psUsItemId p
    , "name"           .= psName p
    , "brand"          .= psBrand p
    , "price_cents"    .= fmap toInteger (psPrice p)
    , "price_per_unit" .= psPricePerUnit p
    , "availability"   .= psAvailability p
    , "description"    .= psDescription p
    , "department"     .= psDepartment p
    , "category_path"  .= psCategoryPath p
    , "fulfillment"    .= psFulfillment p
    ]

-- | The first 200 characters of a response body, kept for diagnostics.
newtype BodyPreview = BodyPreview { unBodyPreview :: Text }
  deriving stock (Show, Eq)

data WalmartError
  = WalmartNetworkError Text
  | WalmartParseError Text String
  | WalmartBadRequest BodyPreview
  | WalmartRateLimited
  | WalmartAccessDenied
  | WalmartHttpError Int BodyPreview
  | WalmartJsonDecodeError String BodyPreview
    -- | The catalog holds no hash for this operation, and discovery did
    -- not supply one.
  | WalmartOperationUnresolved OperationName
    -- | Walmart still rejected the request after the catalog was
    -- refreshed. A newer hash is not the problem, so the response body
    -- is carried for whatever the gateway objected to instead.
  | WalmartStaleAfterRefresh OperationName BodyPreview
  | WalmartDiscoveryFailed Text
  deriving stock (Show, Eq)

-- | Walmart's category identifier, as it appears in search facets and
-- is accepted back as a search filter.
newtype CategoryId = CategoryId { unCategoryId :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON CategoryId where
  toJSON = toJSON . unCategoryId

data SearchQuery = SearchQuery
  { sqTerm       :: Text
  , sqCategoryId :: Maybe CategoryId
  , sqPage       :: Int
  , sqLimit      :: Int
  } deriving stock (Show, Eq)

-- | Results plus the categories Walmart offers to narrow them, so a
-- caller can discover a category id from a search rather than having to
-- know one already.
data SearchResult = SearchResult
  { srProducts   :: [ProductSummary]
  , srCategories :: [CategoryFacet]
  , srStore      :: Maybe StoreContext
  } deriving stock (Show, Eq)

instance ToJSON SearchResult where
  toJSON r = object
    [ "products"   .= srProducts r
    , "categories" .= srCategories r
    , "store"      .= srStore r
    ]

data CategoryFacet = CategoryFacet
  { cfId    :: CategoryId
  , cfName  :: Text
  , cfCount :: Maybe Int
  } deriving stock (Show, Eq)

instance ToJSON CategoryFacet where
  toJSON c = object
    [ "category_id" .= cfId c
    , "name"        .= cfName c
    , "count"       .= cfCount c
    ]

-- | How Walmart offers to get an item to you. Its vocabulary is
-- open-ended, so a tag this client does not know is carried through
-- rather than failing the search that mentioned it.
data Fulfillment
  = Delivery
  | Pickup
  | Shipping
  | UnknownFulfillment Text
  deriving stock (Show, Eq, Ord)

instance ToJSON Fulfillment where
  toJSON Delivery                 = "delivery"
  toJSON Pickup                   = "pickup"
  toJSON Shipping                 = "shipping"
  toJSON (UnknownFulfillment tag) = toJSON tag

-- | One way to obtain an item, and the soonest Walmart offered it.
data FulfillmentOption = FulfillmentOption
  { foMethod   :: Fulfillment
  , foEarliest :: Maybe UTCTime
  } deriving stock (Show, Eq)

instance ToJSON FulfillmentOption where
  toJSON o = object
    [ "method"   .= foMethod o
    , "earliest" .= foEarliest o
    ]

-- | The store Walmart answered for. Stock is reported against a
-- specific store, so a result that does not say which one is ambiguous.
data StoreContext = StoreContext
  { scStoreId    :: Text
  , scPostalCode :: Maybe Text
  } deriving stock (Show, Eq)

instance ToJSON StoreContext where
  toJSON s = object
    [ "store_id"    .= scStoreId s
    , "postal_code" .= scPostalCode s
    ]
