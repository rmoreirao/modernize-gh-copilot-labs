namespace OrderDesk.Legacy
{
    public sealed class Product
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public decimal Price { get; set; }
        public int Stock { get; set; }
    }

    public sealed class CreateOrderRequest
    {
        public int ProductId { get; set; }
        public int Quantity { get; set; }
    }

    public sealed class Order
    {
        public int Id { get; set; }
        public int ProductId { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal Total { get; set; }
        public string Status { get; set; }
    }

    public sealed class ErrorResponse
    {
        public string Message { get; set; }
    }
}
