# OrderDesk HTTP contract

This is the compatibility boundary for the C# to Python exercise. Both hosts implement these JSON endpoints independently. Requests use `Content-Type: application/json` and `Accept: application/json`.

## Fresh state

Each host starts with no orders, the next order ID set to 1, and these products, returned in ID order:

| id | name | price | stock |
| --- | --- | --- | --- |
| 1 | Notebook | 19.95 | 10 |
| 2 | Pencil | 0.10 | 10 |

Restart the host for a fresh scenario. There is no reset endpoint.

## Endpoints

| Request | Response |
| --- | --- |
| `GET /api/products` | 200 and the product array |
| `POST /api/orders` with `{"productId":1,"quantity":2}` | 201, an order, and a Location header whose path is `/api/orders/1` |
| `GET /api/orders/1` | 200 and the previously created order |
| `POST /api/orders/1/cancel` | 200 and the order with status `cancelled` |

A newly created order has this shape:

```json
{"id":1,"productId":1,"quantity":2,"unitPrice":19.95,"total":39.90,"status":"placed"}
```

Property names are camelCase. Money is a JSON **number**, not a quoted string. Compare its parsed decimal value exactly; insignificant trailing zeroes and JSON property order are not contract differences. Location may be absolute or relative; compare its path, not its port.

An order reserves its quantity from the product's stock. Cancellation restores that quantity exactly once. Repeated cancellation returns the same cancelled order without adding stock again. Prices and quantities come from the server catalog and accepted request, not client-supplied totals.

## Errors and bounds

Every error below is JSON with exactly one `message` property. A failed operation leaves products and orders unchanged.

| Condition | Status | message |
| --- | --- | --- |
| Null/malformed body, missing/nonpositive product ID or quantity, or a request integer outside signed 32-bit range | 400 | Invalid order. |
| Unknown positive product ID | 404 | Product not found. |
| Requested quantity exceeds available stock | 409 | Insufficient stock. |
| Reading or cancelling an unknown order ID | 404 | Order not found. |

Request integers use the legacy Web API 2/Newtonsoft binding rules: integral JSON numbers and parseable integer strings are accepted; an out-of-range integer fails binding. Python must not silently accept arbitrary-size integers or change these declared outcomes.

The baseline covers the listed endpoints and cases, not every framework-generated error, unknown route, unsupported media type, or other coercion. No authentication, persistence, tax, customer data, timestamps, multiple order lines, or deployment is involved.

The Python host runs with one Uvicorn worker and a shared, protected in-memory store. It must remain functional with the legacy host stopped, without a CLR bridge or proxy.
