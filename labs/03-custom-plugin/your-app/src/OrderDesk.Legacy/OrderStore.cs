using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;

namespace OrderDesk.Legacy
{
    public sealed class OrderStore
    {
        public static OrderStore Instance { get; } = new OrderStore();

        private readonly object gate = new object();
        private readonly Dictionary<int, Product> products = new Dictionary<int, Product>
        {
            { 1, new Product { Id = 1, Name = "Notebook", Price = 19.95m, Stock = 10 } },
            { 2, new Product { Id = 2, Name = "Pencil", Price = 0.10m, Stock = 10 } }
        };
        private readonly Dictionary<int, Order> orders = new Dictionary<int, Order>();
        private int nextOrderId = 1;

        private OrderStore() { }

        public Product[] GetProducts()
        {
            lock (gate)
                return products.Values.OrderBy(p => p.Id).Select(p => new Product
                {
                    Id = p.Id, Name = p.Name, Price = p.Price, Stock = p.Stock
                }).ToArray();
        }

        public Order Create(int productId, int quantity)
        {
            lock (gate)
            {
                Product product;
                if (!products.TryGetValue(productId, out product))
                    throw new OrderRejectedException(HttpStatusCode.NotFound, "Product not found.");
                if (quantity > product.Stock)
                    throw new OrderRejectedException(HttpStatusCode.Conflict, "Insufficient stock.");

                var order = new Order
                {
                    Id = nextOrderId++, ProductId = productId, Quantity = quantity,
                    UnitPrice = product.Price, Total = product.Price * quantity, Status = "placed"
                };
                product.Stock -= quantity;
                orders.Add(order.Id, order);
                return Copy(order);
            }
        }

        public Order Find(int id)
        {
            lock (gate)
            {
                Order order;
                return orders.TryGetValue(id, out order) ? Copy(order) : null;
            }
        }

        public Order Cancel(int id)
        {
            lock (gate)
            {
                Order order;
                if (!orders.TryGetValue(id, out order))
                    return null;
                if (order.Status == "placed")
                {
                    products[order.ProductId].Stock += order.Quantity;
                    order.Status = "cancelled";
                }
                return Copy(order);
            }
        }

        private static Order Copy(Order order)
        {
            return new Order
            {
                Id = order.Id, ProductId = order.ProductId, Quantity = order.Quantity,
                UnitPrice = order.UnitPrice, Total = order.Total, Status = order.Status
            };
        }
    }

    public sealed class OrderRejectedException : Exception
    {
        public HttpStatusCode StatusCode { get; }

        public OrderRejectedException(HttpStatusCode statusCode, string message) : base(message)
        {
            StatusCode = statusCode;
        }
    }
}
