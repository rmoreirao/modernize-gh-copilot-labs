using System.Net;
using System.Web.Http;

namespace OrderDesk.Legacy
{
    [RoutePrefix("api/orders")]
    public sealed class OrdersController : ApiController
    {
        [HttpPost, Route("")]
        public IHttpActionResult Create(CreateOrderRequest request)
        {
            if (request == null || !ModelState.IsValid || request.ProductId <= 0 || request.Quantity <= 0)
                return Content(HttpStatusCode.BadRequest, new ErrorResponse { Message = "Invalid order." });

            try
            {
                var order = OrderStore.Instance.Create(request.ProductId, request.Quantity);
                return CreatedAtRoute("GetOrder", new { id = order.Id }, order);
            }
            catch (OrderRejectedException exception)
            {
                return Content(exception.StatusCode, new ErrorResponse { Message = exception.Message });
            }
        }

        [HttpGet, Route("{id:int}", Name = "GetOrder")]
        public IHttpActionResult Get(int id)
        {
            var order = OrderStore.Instance.Find(id);
            return order == null
                ? Content(HttpStatusCode.NotFound, new ErrorResponse { Message = "Order not found." })
                : (IHttpActionResult)Ok(order);
        }

        [HttpPost, Route("{id:int}/cancel")]
        public IHttpActionResult Cancel(int id)
        {
            var order = OrderStore.Instance.Cancel(id);
            return order == null
                ? Content(HttpStatusCode.NotFound, new ErrorResponse { Message = "Order not found." })
                : (IHttpActionResult)Ok(order);
        }
    }
}
