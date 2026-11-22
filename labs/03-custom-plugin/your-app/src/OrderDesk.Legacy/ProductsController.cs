using System.Web.Http;

namespace OrderDesk.Legacy
{
    [RoutePrefix("api/products")]
    public sealed class ProductsController : ApiController
    {
        [HttpGet, Route("")]
        public IHttpActionResult Get()
        {
            return Ok(OrderStore.Instance.GetProducts());
        }
    }
}
