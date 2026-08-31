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
  , StoreId (..)
  , PostalCode (..)
  , AccessType (..)
  , Store (..)
  , StoreSearch (..)
  , CartId (..)
  , OfferId (..)
  , CartLine (..)
  , CartTotals (..)
  , Cart (..)
  , CartUpdate (..)
  , ReceiptLine (..)
  , ReservationId (..)
  , Upc (..)
  , Specification (..)
  , ProductDetail (..)
  , ReservedSlot (..)
  , Reservation (..)
  , CartReceipt (..)
  , FulfillmentIntent (..)
  , StoreChoice (..)
  , intentLabel
  , SlotId (..)
  , AccessPointId (..)
  , SlotMetadata (..)
  , SlotTiming (..)
  , Slot (..)
  , SlotDay (..)
  , SlotAccessPoint (..)
  , SlotSchedule (..)
  ) where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Char (isDigit)
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (Day, UTCTime)
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
  , psOfferId      :: OfferId
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
    , "offer_id"       .= psOfferId p
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
    -- | The gateway understood the hash but not the variables, and said
    -- which ones it objected to. The catalog is not at fault, so no
    -- refresh is attempted.
  | WalmartInvalidVariables [Text]
    -- | The page renderer did not deliver a document: it exited with
    -- an error, or the document carried no product data.
  | WalmartRenderFailed Text
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

-- | Walmart's numeric store identifier, as text because it is only ever
-- passed back to Walmart.
newtype StoreId = StoreId { unStoreId :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON StoreId where
  toJSON = toJSON . unStoreId

newtype PostalCode = PostalCode { unPostalCode :: Text }
  deriving stock (Show, Eq)

instance ToJSON PostalCode where
  toJSON = toJSON . unPostalCode

-- | A way a store can hand over an order. Walmart's vocabulary is
-- open-ended, so an unfamiliar tag is carried through rather than
-- failing the store that offers it.
data AccessType
  = DeliveryAddress
  | PickupInStore
  | PickupCurbside
  | UnknownAccessType Text
  deriving stock (Show, Eq, Ord)

instance ToJSON AccessType where
  toJSON DeliveryAddress           = "delivery"
  toJSON PickupInStore             = "pickup_in_store"
  toJSON PickupCurbside            = "pickup_curbside"
  toJSON (UnknownAccessType tag)   = toJSON tag

data Store = Store
  { storeId            :: StoreId
  , storeName          :: Text
  , storeCity          :: Text
  , storeState         :: Text
  , storePostalCode    :: PostalCode
  , storeDistanceMiles :: Scientific
  , storeAccessTypes   :: [AccessType]
  } deriving stock (Show, Eq)

instance ToJSON Store where
  toJSON s = object
    [ "store_id"       .= storeId s
    , "name"           .= storeName s
    , "city"           .= storeCity s
    , "state"          .= storeState s
    , "postal_code"    .= storePostalCode s
    , "distance_miles" .= storeDistanceMiles s
    , "access_types"   .= storeAccessTypes s
    ]

-- | Where to look for stores: around a postal code, out to a radius.
data StoreSearch = StoreSearch
  { ssPostalCode  :: PostalCode
  , ssRadiusMiles :: Int
  } deriving stock (Show, Eq)

newtype CartId = CartId { unCartId :: Text }
  deriving stock (Show, Eq)

instance ToJSON CartId where
  toJSON = toJSON . unCartId

-- | The id of one seller's offer of an item. It is what the cart keys
-- lines by; a search result carries it alongside the item id.
newtype OfferId = OfferId { unOfferId :: Text }
  deriving stock (Show, Eq, Ord)

instance ToJSON OfferId where
  toJSON = toJSON . unOfferId

data CartLine = CartLine
  { clUsItemId      :: UsItemId
  , clOfferId       :: OfferId
  , clName          :: Text
  , clQuantity      :: Scientific
  , clSalesUnitType :: SalesUnitType
  , clLinePrice     :: Discrete "USD" "cent"
  , clAvailability  :: Maybe Text
  } deriving stock (Show, Eq)

instance ToJSON CartLine where
  toJSON l = object
    [ "us_item_id"       .= clUsItemId l
    , "offer_id"         .= clOfferId l
    , "name"             .= clName l
    , "quantity"         .= clQuantity l
    , "sales_unit_type"  .= clSalesUnitType l
    , "line_price_cents" .= toInteger (clLinePrice l)
    , "availability"     .= clAvailability l
    ]

-- | What Walmart has priced so far. A cart mutation answers with the
-- subtotal alone; reading the cart adds the estimated total and the
-- order minimum with the fee charged for falling short of it.
data CartTotals = CartTotals
  { ctSubtotal        :: Discrete "USD" "cent"
  , ctEstimatedTotal  :: Maybe (Discrete "USD" "cent")
  , ctOrderMinimum    :: Maybe (Discrete "USD" "cent")
  , ctBelowMinimumFee :: Maybe (Discrete "USD" "cent")
  } deriving stock (Show, Eq)

instance ToJSON CartTotals where
  toJSON t = object
    [ "subtotal_cents"          .= toInteger (ctSubtotal t)
    , "estimated_total_cents"   .= fmap toInteger (ctEstimatedTotal t)
    , "order_minimum_cents"     .= fmap toInteger (ctOrderMinimum t)
    , "below_minimum_fee_cents" .= fmap toInteger (ctBelowMinimumFee t)
    ]

-- | The session's cart as Walmart reports it: which store it is
-- assorted against, how Walmart decided that, its lines, and what has
-- been priced. An empty cart is not priced at all.
data Cart = Cart
  { cartId             :: CartId
  , cartStoreId        :: StoreId
  , cartIntent         :: FulfillmentIntent
  , cartStoreChoice    :: StoreChoice
  , cartLines          :: [CartLine]
  , cartTotals         :: Maybe CartTotals
  , cartReservation    :: Maybe Reservation
  } deriving stock (Show, Eq)

instance ToJSON Cart where
  toJSON c = object
    [ "cart_id"         .= cartId c
    , "store_id"        .= cartStoreId c
    , "intent"          .= cartIntent c
    , "store_choice"    .= cartStoreChoice c
    , "lines"           .= cartLines c
    , "totals"          .= cartTotals c
    , "reservation"     .= cartReservation c
    ]

-- | Set one offer's quantity in the cart. Zero removes the line.
data CartUpdate = CartUpdate
  { cuOfferId  :: OfferId
  , cuQuantity :: Int
  } deriving stock (Show, Eq)

-- | How the cart came to be assorted against its store: chosen by the
-- shopper, inferred by Walmart from the session, or not reported (a
-- cancelled reservation answers without saying).
data StoreChoice = ChosenStore | InferredStore | UnstatedStore
  deriving stock (Show, Eq)

instance ToJSON StoreChoice where
  toJSON ChosenStore   = "chosen"
  toJSON InferredStore = "inferred"
  toJSON UnstatedStore = "unstated"

-- | How the customer means to receive the cart.
data FulfillmentIntent = DeliveryIntent | PickupIntent
  deriving stock (Show, Eq)

intentLabel :: FulfillmentIntent -> Text
intentLabel DeliveryIntent = "DELIVERY"
intentLabel PickupIntent   = "PICKUP"

instance ToJSON FulfillmentIntent where
  toJSON = toJSON . intentLabel

newtype SlotId = SlotId { unSlotId :: Text }
  deriving stock (Show, Eq)

instance ToJSON SlotId where
  toJSON = toJSON . unSlotId

-- | The store-side point an order is handed over from; a delivery slot
-- names the one that dispatches it.
newtype AccessPointId = AccessPointId { unAccessPointId :: Text }
  deriving stock (Show, Eq)

instance ToJSON AccessPointId where
  toJSON = toJSON . unAccessPointId

-- | The opaque description Walmart attaches to a slot and expects back
-- verbatim when the slot is reserved.
newtype SlotMetadata = SlotMetadata { unSlotMetadata :: Text }
  deriving stock (Show, Eq)

instance ToJSON SlotMetadata where
  toJSON = toJSON . unSlotMetadata

-- | When a slot delivers. A scheduled slot is a window; an express slot
-- promises arrival within some minutes of ordering. A kind this client
-- does not know is carried through with its name so it still lists.
data SlotTiming
  = Scheduled UTCTime UTCTime
  | Express Int
  | UnknownSlotKind Text
  deriving stock (Show, Eq)

instance ToJSON SlotTiming where
  toJSON (Scheduled start end) = object [ "kind" .= ("scheduled" :: Text), "start" .= start, "end" .= end ]
  toJSON (Express minutes)     = object [ "kind" .= ("express" :: Text), "within_minutes" .= minutes ]
  toJSON (UnknownSlotKind tag) = object [ "kind" .= tag ]

data Slot = Slot
  { slotId          :: SlotId
  , slotAccessPoint :: AccessPointId
  , slotTiming      :: SlotTiming
  , slotAvailable   :: Bool
  , slotFee         :: Discrete "USD" "cent"
    -- | When Walmart stops honouring the slot as offered.
  , slotExpiry      :: Maybe UTCTime
  , slotMetadata    :: Maybe SlotMetadata
  } deriving stock (Show, Eq)

instance ToJSON Slot where
  toJSON s = object
    [ "slot_id"         .= slotId s
    , "access_point_id" .= slotAccessPoint s
    , "timing"          .= slotTiming s
    , "available"       .= slotAvailable s
    , "fee_cents"       .= toInteger (slotFee s)
    , "expires_at"      .= slotExpiry s
    , "slot_metadata"   .= slotMetadata s
    ]

data SlotDay = SlotDay
  { sdDay   :: Day
  , sdSlots :: [Slot]
  } deriving stock (Show, Eq)

instance ToJSON SlotDay where
  toJSON d = object [ "day" .= sdDay d, "slots" .= sdSlots d ]

data SlotAccessPoint = SlotAccessPoint
  { apId        :: AccessPointId
  , apName      :: Text
  , apStoreId   :: StoreId
  } deriving stock (Show, Eq)

instance ToJSON SlotAccessPoint where
  toJSON a = object
    [ "access_point_id" .= apId a
    , "name"            .= apName a
    , "store_id"        .= apStoreId a
    ]

-- | The slots Walmart offers the cart, by day, and the access points
-- they dispatch from.
data SlotSchedule = SlotSchedule
  { ssAccessPoints :: [SlotAccessPoint]
  , ssDays         :: [SlotDay]
  } deriving stock (Show, Eq)

instance ToJSON SlotSchedule where
  toJSON s = object
    [ "access_points" .= ssAccessPoints s
    , "days"          .= ssDays s
    ]

-- | A line as a cart mutation reports it. The mutation answers with
-- identifiers and prices only; names and stock come from reading the
-- cart.
data ReceiptLine = ReceiptLine
  { rlUsItemId  :: UsItemId
  , rlOfferId   :: OfferId
  , rlQuantity  :: Scientific
  , rlLinePrice :: Discrete "USD" "cent"
  } deriving stock (Show, Eq)

instance ToJSON ReceiptLine where
  toJSON l = object
    [ "us_item_id"       .= rlUsItemId l
    , "offer_id"         .= rlOfferId l
    , "quantity"         .= rlQuantity l
    , "line_price_cents" .= toInteger (rlLinePrice l)
    ]

-- | What a cart mutation answers with: the lines the cart now holds and
-- their subtotal, which is absent once the cart is empty.
data CartReceipt = CartReceipt
  { crCartId   :: CartId
  , crLines    :: [ReceiptLine]
  , crSubtotal :: Maybe (Discrete "USD" "cent")
  } deriving stock (Show, Eq)

instance ToJSON CartReceipt where
  toJSON r = object
    [ "cart_id"        .= crCartId r
    , "lines"          .= crLines r
    , "subtotal_cents" .= fmap toInteger (crSubtotal r)
    ]

newtype ReservationId = ReservationId { unReservationId :: Text }
  deriving stock (Show, Eq)

instance ToJSON ReservationId where
  toJSON = toJSON . unReservationId

-- | The slot a reservation holds, as the cart reports it: the offer
-- fields (availability, expiry, metadata) are gone once it is held.
data ReservedSlot = ReservedSlot
  { rsSlotId :: SlotId
  , rsTiming :: SlotTiming
  , rsFee    :: Discrete "USD" "cent"
  } deriving stock (Show, Eq)

instance ToJSON ReservedSlot where
  toJSON s = object
    [ "slot_id"   .= rsSlotId s
    , "timing"    .= rsTiming s
    , "fee_cents" .= toInteger (rsFee s)
    ]

-- | A slot held for the cart until Walmart's deadline passes or the
-- order is placed.
data Reservation = Reservation
  { reservationId     :: ReservationId
  , reservationExpiry :: UTCTime
  , reservationSlot   :: ReservedSlot
  } deriving stock (Show, Eq)

instance ToJSON Reservation where
  toJSON r = object
    [ "reservation_id" .= reservationId r
    , "held_until"     .= reservationExpiry r
    , "slot"           .= reservationSlot r
    ]

-- | The barcode printed on the package, as Walmart lists it (UPC-A,
-- twelve digits). It is the key nutrition databases index by.
newtype Upc = Upc { unUpc :: Text }
  deriving stock (Show, Eq)

instance ToJSON Upc where
  toJSON = toJSON . unUpc

-- | One row of the product page's specification table.
data Specification = Specification
  { specName  :: Text
  , specValue :: Text
  } deriving stock (Show, Eq)

instance ToJSON Specification where
  toJSON s = object [ "name" .= specName s, "value" .= specValue s ]

-- | What a product page states beyond what search reports: the
-- barcode, the ingredient statement, how much is in the package, and
-- the specification table those come from.
data ProductDetail = ProductDetail
  { pdUsItemId       :: UsItemId
  , pdOfferId        :: OfferId
  , pdName           :: Text
  , pdBrand          :: Maybe Text
  , pdUpc            :: Maybe Upc
  , pdPrice          :: Maybe (Discrete "USD" "cent")
  , pdPricePerUnit   :: Maybe Text
  , pdCategoryPath   :: [Text]
  , pdIngredients    :: Maybe Text
    -- | The package size as the specification table states it, when a
    -- row names one.
  , pdNetContent     :: Maybe Text
  , pdSpecifications :: [Specification]
  , pdDescription    :: Maybe Text
  } deriving stock (Show, Eq)

instance ToJSON ProductDetail where
  toJSON p = object
    [ "us_item_id"     .= pdUsItemId p
    , "offer_id"       .= pdOfferId p
    , "name"           .= pdName p
    , "brand"          .= pdBrand p
    , "upc"            .= pdUpc p
    , "price_cents"    .= fmap toInteger (pdPrice p)
    , "price_per_unit" .= pdPricePerUnit p
    , "category_path"  .= pdCategoryPath p
    , "ingredients"    .= pdIngredients p
    , "net_content"    .= pdNetContent p
    , "specifications" .= pdSpecifications p
    , "description"    .= pdDescription p
    ]
